#!/usr/bin/env bash
#
# Provider adapter: Cline CLI.
#
# The reason this adapter exists is the tool-call gate. opencode requires the model to emit native
# tool calls, and several capable local models cannot — Qwen3-Coder needed a proxy shim to be
# usable at all, and four of its five benchmark runs were then lost to the cost of hand-escaping
# source code into JSON. Cline drives its own tool loop and reaches the same models without that
# layer: probed here, qw3c-32k read a file and returned the marker in two iterations with the shim
# switched off entirely.
#
# Nothing about opencode changes. This is a sibling adapter, selected by HANDOFF_PROVIDER, so the
# existing gemma/qw3c/gptoss results stay comparable and reproducible.
#
# Env overrides: HANDOFF_MODEL (ollama model id), HANDOFF_CLINE_PROVIDER, HANDOFF_CLINE_CONFIG,
#                HANDOFF_CLINE_TIMEOUT, HANDOFF_CLINE_RETRIES

provider_name() { echo "cline"; }

# Everything that decides what "this model" actually means, recorded with every run.
#
# "gpt-oss" already names several different serving stacks here — ollama's repackaged build, the
# Hugging Face MXFP4 GGUF, a fine-tuned distill, each behind a different engine — and results from
# them are not comparable. A run without this manifest is a number whose provenance has to be
# reconstructed from memory, which is how a provider regression ends up attributed to a model.
#
# Adapters that serve models elsewhere override this and add their own fields.
provider_manifest() {
    python3 -c '
import json, os, subprocess

def cmd(*args):
    try:
        return subprocess.run(args, capture_output=True, text=True, timeout=10).stdout.strip()
    except Exception:
        return None

print(json.dumps({
    "client": "cline",
    "client_version": cmd("cline", "--version"),
    "client_provider": os.environ.get("HANDOFF_CLINE_PROVIDER", "ollama"),
    "model": os.environ.get("HANDOFF_MODEL"),
    "reasoning": os.environ.get("HANDOFF_CLINE_THINKING") or "(client default)",
    "engine": "ollama",
    "engine_version": cmd("ollama", "--version"),
}, indent=2))
'
}

# Verified against `cline --help` (3.0.52) and by running it, not by assuming:
#
#   structured_output  prompt-validate  — there is no schema flag. --json controls the event
#                                         stream shape, not the reply's contents. The schema rides
#                                         in the prompt and the reply is validated afterwards,
#                                         with one retry.
#   session_resume     none             — `--id` exists, but combining it with --json and a prompt
#                                         argument fails in 3.0.52 with "JSON output mode requires
#                                         a prompt argument or piped stdin". Tested with both a
#                                         real session id from <config>/data/sessions and the
#                                         taskId this adapter used to parse; both fail identically,
#                                         so it is the flag combination, not the id.
#
#                                         This was declared 'native' on the strength of --id being
#                                         in the help text. It was never exercised, and the cost
#                                         was that the prompt-validate retry silently never ran:
#                                         every malformed report became unrecoverable, including
#                                         runs whose patch was byte-perfect.
#   sandbox            none             — the run is --auto-approve, so the agent is effectively
#                                         unconstrained. Declared none so the driver warns and the
#                                         reviewer reads the diff by hand.
provider_capabilities() {
    cat <<'CAPS'
structured_output=prompt-validate
session_resume=none
sandbox=none
CAPS
}

# The config directory holds the provider credentials written by `cline auth`. Keeping it out of
# ~/.cline by default means a benchmark cannot disturb, or be disturbed by, the user's own Cline
# setup.
#
# --config, NOT --data-dir. `cline auth --help` states that --data-dir "enables sandbox mode", and
# in that mode commands are spawned without a shell: `ls -la` came back as
# `Executable not found in $PATH: "ls -la"`, and the agent then thrashed for 31 iterations against
# a toolset that could not work. That run said nothing about the model and was discarded.
_cline_config_dir() { echo "${HANDOFF_CLINE_CONFIG:-$HOME/.cline-handoff}"; }

provider_preflight() {
    command -v cline >/dev/null 2>&1 || {
        echo "cline not found on PATH — install with 'npm i -g cline'" >&2
        return 1
    }

    # cline nests its state one level down, at <config>/data/settings/providers.json.
    local config; config="$(_cline_config_dir)"
    [[ -f "$config/data/settings/providers.json" ]] || {
        echo "Cline has no provider configured at ${config}." >&2
        echo "Run: cline auth -p ollama -m <model> -k dummy --config ${config}" >&2
        echo "(-k is required even for ollama, which ignores it.)" >&2
        return 1
    }

    local host="${OLLAMA_HOST:-http://127.0.0.1:11434}"
    curl -fsS --max-time 5 "${host%/}/api/tags" >/dev/null 2>&1 || {
        echo "No Ollama daemon answering at ${host}." >&2
        return 1
    }
}

# Cline resolves relative paths against a project root it discovers by walking up from the working
# directory. Given a plain directory it walked past the target entirely and read
# /tmp/.handoff/plans/probe.md instead of the file inside the temp dir. Every bench worktree is a
# git checkout so this holds there, but a caller pointing the driver at a non-repo would hit it.
_cline_assert_repo_root() {
    local root="$1"
    git -C "$root" rev-parse --show-toplevel >/dev/null 2>&1 || {
        echo "cline needs a git repository as its working directory; ${root} is not one" >&2
        return 1
    }
}

# The developer instructions are prepended to the prompt rather than passed via --system.
#
# --system REPLACES Cline's own system prompt, which is where its tool definitions and tool-call
# protocol live. Overriding it would remove the agent loop this adapter exists to use.
# How the completion report is asked for.
#
#   message  (default)  the model's final assistant message must be the JSON object
#   file                the model writes the JSON to a path with its file tool
#
# The case for `file` is mechanical rather than aesthetic. This model emits tool calls reliably —
# 14 of 14 well formed at the engine level, including a ~1 KB freeform payload after a 20 KB tool
# result — and final text unreliably: 33% to 40% of first attempts end with a reasoning block and a
# tool call and no text block at all, which is the single largest non-success outcome measured
# here. Asking for the report through the channel that works should remove that class entirely.
#
# It is opt-in and unmeasured. An earlier change tonight was applied on equally good reasoning and
# made things measurably worse, so nothing becomes the default here until a round says it should.
_cline_report_channel() {
    if declare -F provider_report_channel >/dev/null; then
        provider_report_channel
    else
        echo "${HANDOFF_REPORT_CHANNEL:-message}"
    fi
}

_cline_build_prompt() {
    local dev="$1" prompt="$2" schema="$3" report_rel="${4:-}"
    local compact
    compact="$(python3 -c 'import json,sys; print(json.dumps(json.load(open(sys.argv[1])),separators=(",",":")))' "$schema")"

    if [[ -n "$report_rel" ]]; then
        # The path is under .handoff/runs, which every scope and litter gate already excludes, so
        # writing it cannot be scored as a file the plan never named.
        printf '%s\n\n%s\n\nWhen the work is finished, write your completion report to the file `%s`, creating it if necessary. Its entire contents must be a single JSON object conforming to the schema below — no prose, no markdown code fences, no explanation. Write the file with your normal file-writing tool; do not put the report in your reply.\n\nSchema:\n%s\n' \
            "$dev" "$prompt" "$report_rel" "$compact"
        return
    fi

    printf '%s\n\n%s\n\nWhen the work is finished, your FINAL message must be a single JSON object conforming to this JSON schema, and nothing else — no prose, no markdown code fences, no explanation.\n\nSchema:\n%s\n' \
        "$dev" "$prompt" "$compact"
}

_cline_retry_prompt() {
    printf 'Your previous final message did not parse or did not match the required schema:\n%s\n\nReply with ONLY a corrected JSON object conforming to the schema. Do not redo the work.\n' "$1"
}

# Reduce the event stream to the assistant's final text.
#
# Cline emits one event per token, so a run produces tens of thousands of lines; the accumulated
# answer arrives in `content_end` events of contentType "text". Reasoning is a separate
# contentType and is excluded deliberately — a reasoning trace concatenated onto the reply would
# never validate as a bare JSON object.
_cline_final_text() {
    python3 -c '
import json, sys
parts = []
for line in open(sys.argv[1], errors="replace"):
    line = line.strip()
    if not line:
        continue
    try:
        event = json.loads(line).get("event") or {}
    except Exception:
        continue
    if event.get("type") == "content_end" and event.get("contentType") == "text":
        text = event.get("text")
        if isinstance(text, str) and text:
            parts.append(text)
open(sys.argv[2], "w").write("\n".join(parts))
' "$1" "$2"
}

# Writes the event stream to the log AS IT ARRIVES, not after the process returns.
#
# An earlier version buffered to a temp file and copied it into the log afterwards. A run killed
# by the bench timeout never reached the copy, so the one run that most needed diagnosing — 30
# minutes, zero files written — preserved no provider log at all, and the only evidence left was
# that it had produced nothing. A round with no inspectable output is worse than one that failed
# loudly.
#
# The same pattern is present in providers/opencode.sh and has the same consequence there; left
# alone for now because changing a working adapter mid-comparison is its own risk.
_cline_invoke() {
    local root="$1" raw="$2" prompt="$3" session="$4"
    local args=(
        --json
        --config "$(_cline_config_dir)"
        --cwd "$root"
        --provider "${HANDOFF_CLINE_PROVIDER:-ollama}"
        --auto-approve true
        --retries "${HANDOFF_CLINE_RETRIES:-6}"
        --timeout "${HANDOFF_CLINE_TIMEOUT:-3000}"
    )
    [[ -z "${HANDOFF_MODEL:-}" ]] || args+=(--model "$HANDOFF_MODEL")
    # --id is deliberately not passed. It is incompatible with --json plus a prompt argument in
    # 3.0.52 and makes the invocation fail outright, so a retry that passed it never ran at all.
    # The retry therefore starts a fresh session and carries the validation error in its prompt,
    # which is weaker than resuming but is the difference between one retry and none.
    : "${session:=}"
    # Reasoning level. Left at Cline's default unless set, because it is a real variable: gemma
    # emitted 15,441 reasoning tokens in a single probe, and Cline's ollama path reported
    # "Model reached the maximum output token limit before completing the turn" twice in one run
    # — truncating a file write mid-string so that literal \n characters reached disk. Whether
    # reasoning is competing with the output budget is measurable by varying this and nothing else.
    [[ -z "${HANDOFF_CLINE_THINKING:-}" ]] || args+=(--thinking "$HANDOFF_CLINE_THINKING")
    # stdin closed: every other adapter here has been bitten by a CLI that reads stdin when it is
    # not a TTY and then blocks forever in a background shell.
    local log="${CLINE_LIVE_LOG:-/dev/null}"
    ( cd "$root" && cline "${args[@]}" -- "$prompt" ) </dev/null 2>&1 | tee -a "$log" >"$raw"
    return "${PIPESTATUS[0]}"
}

_cline_prompt_validate() {
    local root="$1" schema="$2" result="$3" log="$4" dev="$5" prompt="$6" session="${7:-}"
    _cline_assert_repo_root "$root" || return 1

    local checker; checker="$(dirname "${BASH_SOURCE[0]}")/lib/handoff-json-check.py"
    local raw reply err_file
    raw="$(mktemp)"; reply="$(mktemp)"; err_file="$(mktemp)"

    # Where the model is asked to put the report, when the channel is `file`. Under .handoff/runs,
    # which every scope and litter gate excludes. Removed first: a stale file from a previous
    # attempt would otherwise be read as this attempt's report — the model would get credit for a
    # report it never wrote, which is precisely the fabrication the gates exist to catch.
    local report_abs="" report_rel=""
    if [[ "$(_cline_report_channel)" == file ]]; then
        report_abs="$(dirname "$result")/agent-report.json"
        report_rel="${report_abs#"$root"/}"
        rm -f "$report_abs"
    fi

    local base_prompt; base_prompt="$(_cline_build_prompt "$dev" "$prompt" "$schema" "$report_rel")"
    CLINE_LIVE_LOG="$log" _cline_invoke "$root" "$raw" "$base_prompt" "$session"
    local status=$?

    # Prefer the file when that channel was requested, and fall through to the final message when
    # it is absent. The fallback is deliberate: it turns "the model ignored the instruction" into
    # the old behaviour rather than into a lost run.
    if [[ -n "$report_abs" && -s "$report_abs" ]]; then
        cp "$report_abs" "$reply"
        if python3 "$checker" "$reply" "$schema" "$result" >"$err_file"; then
            rm -f "$raw" "$reply" "$err_file"
            return "$status"
        fi
        echo "==> report file present but did not validate; falling back to the final message" >&2
    fi

    _cline_final_text "$raw" "$reply"
    if python3 "$checker" "$reply" "$schema" "$result" >"$err_file"; then
        rm -f "$raw" "$reply" "$err_file"
        return "$status"
    fi

    # One retry, continuing the same session so the model sees its own bad answer next to the
    # error. Told explicitly not to redo the work: the tree is already correct at this point and a
    # second implementation pass is how a good round turns into a damaged one.
    local sid; sid="$(provider_parse_session_id "$raw")"
    local retry_session="${sid:-$session}"
    CLINE_LIVE_LOG="$log" _cline_invoke "$root" "$raw" \
        "$(_cline_retry_prompt "$(cat "$err_file")")" "$retry_session"
    status=$?

    _cline_final_text "$raw" "$reply"
    if python3 "$checker" "$reply" "$schema" "$result" >"$err_file"; then
        rm -f "$raw" "$reply" "$err_file"
        return "$status"
    fi

    # Both attempts failed. Preserve whatever came back rather than leaving the reviewer with
    # nothing to diagnose, and fail loudly — never report success on unvalidated output.
    if [[ -s "$reply" ]]; then
        cp "$reply" "$result"
    else
        echo "(no final text captured)" >"$result"
    fi
    local last_err; last_err="$(cat "$err_file")"
    rm -f "$raw" "$reply" "$err_file"
    echo "==> cline did not return schema-valid JSON after one retry; raw reply preserved in $result" >&2
    echo "==> last validation error: $last_err" >&2
    return 1
}

# provider_run <repo_root> <schema> <result_file> <log_file> <dev_instructions> <prompt>
provider_run() {
    _cline_prompt_validate "$1" "$2" "$3" "$4" "$5" "$6" ""
}

# provider_resume <session_id> <schema> <result_file> <log_file> <dev_instructions> <prompt>
provider_resume() {
    local session="$1"
    [[ -n "$session" ]] || {
        echo "no cline session to resume — run 'handoff do' first" >&2
        return 1
    }
    _cline_prompt_validate "$PWD" "$2" "$3" "$4" "$5" "$6" "$session"
}

# Cline's resumable identifier is the taskId ("conv_..."), carried on its hook events. agentId is
# a different value and --id does not accept it.
provider_parse_session_id() {
    grep -m1 -oE '"taskId":"conv_[A-Za-z0-9_]+"' "$1" 2>/dev/null | head -n1 | cut -d'"' -f4
}
