#!/usr/bin/env bash
#
# Provider adapter: opencode CLI (SST).
#
# A provider is (binary, env block, capabilities) — not just a binary. Adapters
# expose the six functions below and nothing else; everything provider-agnostic
# lives in bin/handoff.
#
# opencode is the deliberately awkward adapter: it has no schema-enforcement flag,
# so the schema rides inside the prompt and the reply is validated afterwards.
# That makes it the test of whether the driver survives a provider whose
# structured-output guarantee is "ask nicely, then check" rather than "enforced".
#
# Env overrides: HANDOFF_MODEL (provider/model form, e.g. anthropic/claude...),
#                HANDOFF_EFFORT (maps to opencode --variant; model-specific).

provider_name() { echo "opencode"; }

# Capabilities declared honestly, each verified against `opencode run --help`
# (v1.17.4) by running it, not by assuming:
#
#   structured_output  prompt-validate  — no --json-schema / --output-schema flag
#                                         exists (the only "json" is --format, the
#                                         event-stream shape, not reply
#                                         enforcement). The schema is appended to
#                                         the prompt and the reply is validated
#                                         against it, with one retry on failure.
#
#   session_resume     native           — `opencode run -s <id>` continues the same
#                                         session (verified: the resumed run reuses
#                                         the exact session id, and the session
#                                         persists in `opencode session list`
#                                         across separate process invocations).
#
#   sandbox            none             — there is no OS sandbox. The only gate is
#                                         an interactive permission prompt, which
#                                         blocks a headless run dead, so it is
#                                         skipped with --dangerously-skip-permissions.
#                                         The agent is therefore effectively
#                                         unconstrained. Declared "none" so the
#                                         driver prints the warning and the reviewer
#                                         knows to read the diff by hand.
provider_capabilities() {
    cat <<'CAPS'
structured_output=prompt-validate
session_resume=native
sandbox=none
CAPS
}

provider_preflight() {
    command -v opencode >/dev/null 2>&1 || {
        echo "opencode not found on PATH — see https://opencode.ai" >&2
        return 1
    }
}

# Model/effort flags, emitted only when set so opencode's own defaults apply
# otherwise. --variant is provider-specific reasoning effort and not every model
# accepts it, so it is opt-in (only when HANDOFF_EFFORT is set) rather than forced.
_opencode_model_args() {
    [[ -n "${HANDOFF_MODEL:-}" ]] && printf '%s\n' -m "$HANDOFF_MODEL"
    [[ -n "${HANDOFF_EFFORT:-}" ]] && printf '%s\n' --variant "$HANDOFF_EFFORT"
}

# Build the prompt the model sees. With no schema flag, the schema travels inside
# the prompt itself. Compacted to one line: fewer tokens, and it sidesteps any
# future argument-splitting surprise.
_opencode_build_prompt() {
    local dev="$1" prompt="$2" schema="$3"
    local compact
    compact="$(python3 -c 'import json,sys; print(json.dumps(json.load(open(sys.argv[1])),separators=(",",":")))' "$schema")"
    printf '%s\n\n%s\n\nReply with ONLY a single JSON object that conforms to this JSON schema. No prose, no markdown code fences, no explanation — the JSON object and nothing else.\n\nSchema:\n%s\n' \
        "$dev" "$prompt" "$compact"
}

# The retry carries the parse/validation error back to the model so it can fix the
# one thing that was wrong rather than regenerate blind.
_opencode_retry_prompt() {
    local dev="$1" prompt="$2" schema="$3" err="$4"
    printf '%s\n\nYour previous reply did not parse or did not match the schema:\n%s\n\nReturn ONLY a corrected JSON object that conforms to the schema.\n' \
        "$(_opencode_build_prompt "$dev" "$prompt" "$schema")" "$err"
}

# Extract the model's JSON from a --format json event stream and validate it.
# On success: writes canonical JSON to <result> and exits 0 (silent).
# On failure: prints a human-readable error to stdout and exits 1, leaving
# <result> untouched so a stale file can never read as a fresh success.
#
# Extraction is tolerant on purpose. The model is told to emit raw JSON, but in
# practice it may wrap it in a markdown fence, prefix it with prose, or — because
# opencode renders the final answer through a `reply` tool — hand back a tool-call
# envelope whose payload is the real answer. All of those are unwrapped before
# validation, so the reviewer can trust the shape regardless of how the model
# framed it.
#
# stdlib only: jsonschema is not guaranteed present, so a tiny validator covers
# the vocabulary the handoff/think/debug schemas actually use (type, enum,
# required, properties, items, additionalProperties). No new dependency.
_opencode_check() {
    python3 -c '
import json, sys, re
raw, schema_path, out = sys.argv[1], sys.argv[2], sys.argv[3]

parts = []
for line in open(raw):
    line = line.strip()
    if not line:
        continue
    try:
        ev = json.loads(line)
    except Exception:
        continue
    p = ev.get("part") or {}
    if p.get("type") == "text" and "text" in p:
        parts.append(p["text"])
blob = "\n".join(parts)

# chr(34) is the double-quote; spelling it out keeps the source free of the quote
# characters that would collide with the shell wrapping this script.
Q = chr(34)

def try_loads(s):
    try:
        return json.loads(s), None
    except Exception as e:
        return None, str(e)

def balanced(s):
    depth = 0; start = None; instr = False; esc = False
    for i, c in enumerate(s):
        if esc:
            esc = False; continue
        if c == "\\":
            esc = True; continue
        if c == Q:
            instr = not instr; continue
        if instr:
            continue
        if c == "{":
            if depth == 0:
                start = i
            depth += 1
        elif c == "}":
            depth -= 1
            if depth == 0 and start is not None:
                return s[start:i+1]
    return None

def unwrap(obj):
    # opencode renders the final answer through a `reply` tool; the real payload
    # is arguments.message, often a JSON string. Peel that off recursively.
    if isinstance(obj, dict) and "name" in obj and "arguments" in obj:
        args = obj.get("arguments")
        if isinstance(args, dict) and "message" in args:
            msg = args["message"]
            if isinstance(msg, str):
                inner, e = try_loads(msg.strip())
                if inner is not None:
                    return unwrap(inner)
            elif isinstance(msg, (dict, list)):
                return unwrap(msg)
    return obj

s = blob.strip()
m = re.search(r"```(?:json)?\s*(.*?)```", s, re.S)
if m:
    s = m.group(1).strip()
obj, e = try_loads(s)
if obj is None:
    sub = balanced(s)
    if sub is not None:
        obj, e = try_loads(sub)
if obj is None:
    print("could not extract a JSON object from the reply: " + (e or "no balanced object found"))
    sys.exit(1)
obj = unwrap(obj)

schema = json.load(open(schema_path))
errs = []

def v(inst, sch, path):
    if "type" in sch:
        t = sch["type"]
        ok = ((t == "object" and isinstance(inst, dict))
              or (t == "array" and isinstance(inst, list))
              or (t == "string" and isinstance(inst, str))
              or (t == "boolean" and isinstance(inst, bool))
              or (t in ("integer", "number") and isinstance(inst, (int, float)) and not isinstance(inst, bool))
              or (t == "null" and inst is None))
        if not ok:
            errs.append(path + ": expected " + t + ", got " + type(inst).__name__)
    if "enum" in sch and inst not in sch["enum"]:
        errs.append(path + ": " + repr(inst) + " not in enum " + repr(sch["enum"]))
    if isinstance(inst, dict):
        for r in sch.get("required", []):
            if r not in inst:
                errs.append(path + ": missing required " + repr(r))
        if sch.get("additionalProperties") is False:
            allowed = set(sch.get("properties", {}).keys())
            for k in inst:
                if k not in allowed:
                    errs.append(path + ": additional property " + repr(k) + " not allowed")
        for k, val in sch.get("properties", {}).items():
            if k in inst:
                v(inst[k], val, path + "." + k)
    if isinstance(inst, list) and "items" in sch:
        for i, it in enumerate(inst):
            v(it, sch["items"], path + "[" + str(i) + "]")

v(obj, schema, "$")
if errs:
    print("schema validation failed: " + " | ".join(errs))
    sys.exit(1)
open(out, "w").write(json.dumps(obj, indent=2))
' "$1" "$2" "$3"
}

# When both attempts fail, the raw reply is still written to <result>. A failed
# round that produced no inspectable output is worse than one that parsed wrong —
# the reviewer would have nothing to diagnose. Never silently drop the reply.
_opencode_dump_raw() {
    python3 -c '
import json, sys
raw, out = sys.argv[1], sys.argv[2]
parts = []
for line in open(raw):
    line = line.strip()
    if not line:
        continue
    try:
        ev = json.loads(line)
    except Exception:
        continue
    p = ev.get("part") or {}
    if p.get("type") == "text" and "text" in p:
        parts.append(p["text"])
open(out, "w").write("\n".join(parts) if parts else "(no reply text captured)")
' "$1" "$2"
}

# The prompt-validate engine shared by run and resume:
#   1. invoke opencode (fresh, or resuming <session> when given)
#   2. extract + validate; on success, write the result and return
#   3. on failure, retry EXACTLY once, continuing the same session with the error
#   4. if the retry also fails, preserve the raw reply and exit non-zero
_opencode_prompt_validate() {
    local root="$1" schema="$2" result="$3" log="$4" dev="$5" prompt="$6" session="${7:-}"
    local model_args=(); mapfile -t model_args < <(_opencode_model_args)
    local resume_args=()
    [[ -n "$session" ]] && resume_args=(-s "$session")

    local base_prompt; base_prompt="$(_opencode_build_prompt "$dev" "$prompt" "$schema")"
    local raw err_file
    raw="$(mktemp)"; err_file="$(mktemp)"

    # Attempt 1.
    ( cd "$root" && opencode run --format json --dangerously-skip-permissions \
        "${model_args[@]}" "${resume_args[@]}" -- "$base_prompt" ) >"$raw" 2>>"$log"
    local status=$?
    cat "$raw" >>"$log"

    if _opencode_check "$raw" "$schema" "$result" >"$err_file"; then
        rm -f "$raw" "$err_file"
        return "$status"
    fi

    # Attempt 2: one retry only. Continue the same session so the model sees its
    # own bad answer alongside the error. Fall back to the id we were handed.
    local sid; sid="$(provider_parse_session_id "$raw")"
    local retry_session="${sid:-$session}"
    local retry_args=()
    [[ -n "$retry_session" ]] && retry_args=(-s "$retry_session")
    local retry_prompt; retry_prompt="$(_opencode_retry_prompt "$dev" "$prompt" "$schema" "$(cat "$err_file")")"
    ( cd "$root" && opencode run --format json --dangerously-skip-permissions \
        "${model_args[@]}" "${retry_args[@]}" -- "$retry_prompt" ) >"$raw" 2>>"$log"
    status=$?
    cat "$raw" >>"$log"

    if _opencode_check "$raw" "$schema" "$result" >"$err_file"; then
        rm -f "$raw" "$err_file"
        return "$status"
    fi

    # Both attempts failed. Preserve what came back and fail loudly — never report
    # success on output that was never validated.
    _opencode_dump_raw "$raw" "$result"
    local last_err; last_err="$(cat "$err_file")"
    rm -f "$raw" "$err_file"
    echo "==> opencode did not return schema-valid JSON after one retry; raw reply preserved in $result" >&2
    echo "==> last validation error: $last_err" >&2
    echo "==> see $log for the full opencode output" >&2
    return 1
}

# provider_run <repo_root> <schema> <result_file> <log_file> <dev_instructions> <prompt>
provider_run() {
    local root="$1" schema="$2" result="$3" log="$4" dev="$5" prompt="$6"
    _opencode_prompt_validate "$root" "$schema" "$result" "$log" "$dev" "$prompt" ""
}

# provider_resume <session_id> <schema> <result_file> <log_file> <dev_instructions> <prompt>
#
# opencode resumes natively: `opencode run -s <id>` continues the exact session,
# so the reviewer's feedback lands in the implementer's existing reasoning rather
# than having to re-establish the whole context. No prior session = nothing to
# continue = fail clearly, rather than spinning up a fresh run that would look
# like a resume but have lost everything.
provider_resume() {
    local session="$1" schema="$2" result="$3" log="$4" dev="$5" prompt="$6"
    [[ -n "$session" ]] || {
        echo "no opencode session to resume — run 'handoff do' first" >&2
        return 1
    }
    # The driver runs from the repo root; pass it on so resume lands in the same
    # project as the original run.
    _opencode_prompt_validate "$PWD" "$schema" "$result" "$log" "$dev" "$prompt" "$session"
}

# The session id rides in every --format json event as "sessionID":"ses_...".
# Each event line carries it twice (top-level and inside "part"), and `grep -oE`
# prints every match on a matched line while `-m1` only caps the line count — so
# pipe through head -n1 or the pin ends up holding two ids and resume breaks.
provider_parse_session_id() {
    grep -m1 -oE '"sessionID":"ses_[A-Za-z0-9_-]+"' "$1" 2>/dev/null | head -n1 | cut -d'"' -f4
}
