#!/usr/bin/env bash
#
# native — the harness runs the loop itself, against llama-server directly.
#
#   HANDOFF_PROVIDER=native handoff do <slug>
#
# Every other provider here drives a third-party agent CLI. This one does not: tools/native-agent
# holds the conversation, dispatches the tools and asks for the report. See that file's header for
# why, but the short version is that measurement kept producing fixes no client could express —
# the largest being that removing tools for the report turn takes reporting from 44% to 100%, and
# no CLI exposes per-turn tool selection.
#
# It is a second provider, not a replacement. Cline remains the arm every published number was
# measured under, and the two can be run against the same plan for comparison.
#
# The event log is written in Cline's shape deliberately, so tools/journal, tools/final-turn-shape
# and tools/replay-final-turn keep working against native runs without changes.
: "${HANDOFF_MODEL:=gpt-oss-20b}"
: "${NATIVE_MAX_TURNS:=40}"
: "${NATIVE_TEMP:=0.8}"
export HANDOFF_MODEL

_native_home() { cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd; }

provider_name() { echo "native"; }

provider_manifest() {
    printf '{"provider":"native","model":"%s","max_turns":%s,"temp":%s}\n' \
        "$HANDOFF_MODEL" "$NATIVE_MAX_TURNS" "$NATIVE_TEMP"
}

# Structured output is native here in the strict sense: the report is a tool call whose input
# schema IS the report schema, and the fallback turn is asked with the schema restated inline.
provider_capabilities() { echo "structured_output=native"; }

provider_preflight() {
    local host="${LLAMACPP_HOST:-127.0.0.1}" port="${LLAMACPP_PORT:-8071}"
    curl -fsS --max-time 5 "http://${host}:${port}/health" >/dev/null 2>&1 || {
        echo "no llama-server on http://${host}:${port}" >&2
        echo "Start one: tools/llamacpp-serve start ${HANDOFF_MODEL} 98304" >&2
        return 1
    }
    command -v python3 >/dev/null || { echo "native needs python3" >&2; return 1; }
}

# provider_run <repo_root> <schema> <result_file> <log_file> <dev_instructions> <prompt>
provider_run() {
    local repo_root="$1" schema="$2" result_file="$3" log_file="$4" system="$5" prompt="$6"
    python3 "$(_native_home)/tools/native-agent" \
        --repo "$repo_root" \
        --schema "$schema" \
        --result "$result_file" \
        --log "$log_file" \
        --system "$system" \
        --prompt "$prompt" \
        --host "${LLAMACPP_HOST:-127.0.0.1}" \
        --port "${LLAMACPP_PORT:-8071}" \
        --model "$HANDOFF_MODEL" \
        --temp "$NATIVE_TEMP" \
        --max-turns "$NATIVE_MAX_TURNS"
}
