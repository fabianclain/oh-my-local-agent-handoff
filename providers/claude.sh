#!/usr/bin/env bash
#
# Provider adapter: Claude Code CLI.
#
# This adapter is model-agnostic. The binary is a harness, not a model — pointing it at a
# different Anthropic-compatible endpoint changes which model does the work while every flag
# here stays identical. providers/glm.sh is exactly this file plus an env block.
#
# Env overrides: HANDOFF_MODEL, HANDOFF_PERMISSION_MODE

provider_name() { echo "claude"; }

# structured_output  native  — --json-schema enforces the shape of the final message
# session_resume     native  — --resume continues the same conversation
# sandbox            weak    — permission modes restrict tool use, but this is process-level
#                             policy, not an OS sandbox. A misbehaving run is constrained by
#                             the harness rather than the kernel. Declared honestly so the
#                             driver prints it; do not upgrade this to "native" for parity.
provider_capabilities() {
    cat <<'CAPS'
structured_output=native
session_resume=native
sandbox=weak
CAPS
}

provider_preflight() {
    command -v claude >/dev/null 2>&1 || {
        echo "claude not found on PATH — see https://claude.com/claude-code" >&2
        return 1
    }
}

_claude_common_args() {
    local schema="$1" dev_instructions="$2"
    # Two traps here, both found by running it rather than reading it:
    #
    # 1. --json-schema takes the schema INLINE as JSON, unlike codex's --output-schema which
    #    takes a path. Passing a path fails with "Unrecognized token '/'" — the CLI parses the
    #    filename as JSON. Flag semantics do not carry across providers.
    #
    # 2. Args travel to the caller as newline-delimited text read by `mapfile -t`, so any value
    #    containing a newline is silently split into separate arguments. Pretty-printed JSON
    #    arrives as a lone "{". Compact it to one line.
    local schema_inline
    schema_inline="$(python3 -c 'import json,sys; print(json.dumps(json.load(open(sys.argv[1])), separators=(",",":")))' "$schema")"
    printf '%s\n' \
        --print \
        --output-format json \
        --json-schema "$schema_inline" \
        --permission-mode "${HANDOFF_PERMISSION_MODE:-bypassPermissions}" \
        --append-system-prompt "$dev_instructions"
    if [[ -n "${HANDOFF_MODEL:-}" ]]; then
        printf '%s\n' --model "$HANDOFF_MODEL"
    fi
}

# The harness wraps the model's answer in a metadata envelope; the schema-validated content is
# in .result. Extract it so every provider writes the same file shape, or the driver and the
# reviewer would each need provider-specific parsing.
_claude_extract_result() {
    local raw="$1" out="$2"
    # Fails loudly. An earlier version swallowed parse errors with sys.exit(0), so a run whose
    # envelope was unparseable produced no result.json at all and reported success — the
    # reviewer then had nothing to read and no indication why.
    python3 -c '
import json,sys
raw, out = sys.argv[1], sys.argv[2]
try:
    envelope = json.load(open(raw))
except Exception as e:
    print(f"could not parse provider envelope {raw}: {e}", file=sys.stderr)
    sys.exit(1)
payload = envelope.get("result", envelope)
if isinstance(payload, str):
    try:
        payload = json.loads(payload)
    except Exception:
        print("provider returned a non-JSON result body; writing it verbatim", file=sys.stderr)
open(out, "w").write(payload if isinstance(payload, str) else json.dumps(payload, indent=2))
' "$raw" "$out" || {
        echo "==> WARNING: could not extract a handoff report from $raw" >&2
        return 1
    }
}

provider_run() {
    local root="$1" schema="$2" result="$3" log="$4" dev="$5" prompt="$6"
    local args=(); mapfile -t args < <(_claude_common_args "$schema" "$dev")
    local raw="${result}.envelope.json"
    # --add-dir is variadic (<directories...>), so it swallows any following positional — the
    # prompt included, producing "Input must be provided either through stdin or as a prompt
    # argument". It must come first, terminated by the next flag, leaving the prompt last.
    # stdout is the JSON envelope, stderr is warnings/progress. Merging them with 2>&1 puts
    # the "claude.ai connectors are disabled" banner in front of the JSON and it will not parse.
    ( cd "$root" && claude --add-dir "$root" "${args[@]}" "$prompt" ) >"$raw" 2>"$log"
    local status=$?
    cat "$raw" >>"$log"
    _claude_extract_result "$raw" "$result"
    return "$status"
}

provider_resume() {
    local session="$1" schema="$2" result="$3" log="$4" dev="$5" prompt="$6"
    local args=(); mapfile -t args < <(_claude_common_args "$schema" "$dev")
    local raw="${result}.envelope.json"
    claude "${args[@]}" --resume "$session" "$prompt" >"$raw" 2>>"$log"
    local status=$?
    cat "$raw" >>"$log"
    _claude_extract_result "$raw" "$result"
    return "$status"
}

# The session id lives in the JSON envelope rather than being printed as a log line, so parse
# it from there. Falls back to a log scan in case the envelope was not written.
provider_parse_session_id() {
    local log="$1" raw
    raw="$(dirname "$log")/result.json.envelope.json"
    if [[ -f "$raw" ]]; then
        python3 -c 'import json,sys
try: print(json.load(open(sys.argv[1])).get("session_id",""))
except Exception: pass' "$raw" 2>/dev/null && return 0
    fi
    grep -m1 -oE '"session_id":"[0-9a-f-]+"' "$log" 2>/dev/null | cut -d'"' -f4
}
