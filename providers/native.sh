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
# 40 was a bench number. On the bench it binds about 1 round in 20; on the first real feature it
# was tried against it bound on 4 rounds out of 4, including one whose reasoning had already
# worked out the complete correct implementation and simply ran out of iterations before it could
# finish writing. A cap that binds on every real round is measuring the cap, not the model.
#
# Raising it is not free — the parse fault this stack has runs at 0% below 8k, 4.0-4.5% between 8k
# and 32k, and 2.55-6.06% above 48k, and more turns means more depth. It is still the right trade:
# a turn limit reached is a certain loss, while the fault is a risk that the loop already retries.
#
# If rounds are hitting this, the better fix is usually to reduce what the model must read before
# it can write — quote the anchors in the plan — rather than to raise it again.
: "${NATIVE_MAX_TURNS:=80}"
: "${NATIVE_TEMP:=0.8}"
export HANDOFF_MODEL

_native_home() { cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd; }

# Sourced for its token accounting and nothing else; everything it defines about driving a client
# is overridden below.
#
# provider_usage_mark and provider_usage_since read llama-server's own log by byte offset, and
# native talks to that same server, so the numbers are already correct here. Reimplementing them
# against native's event log would be a second parser of the same facts — the defect shape that
# put check-plan and bench/run out of step, and bench/run out of step with verify-round earlier
# today. Without them bench/run records model_requests=0, which is what the first native runs did.
# shellcheck disable=SC1090
source "$(dirname "${BASH_SOURCE[0]}")/lcpp.sh"

provider_name() { echo "native"; }

# Keep lcpp.sh's manifest under another name rather than replacing it. It is the only place that
# records server_props — the context the round actually ran at — and overriding it wholesale is
# how three native arms ran at 32768 for an hour while the queue file, the handoff prompt and this
# comment block all said 98304, with nothing in any result file able to contradict them. The
# Cline arms recorded n_ctx and were checkable the whole time; the native arms were not.
#
# `declare -f` prints the definition, `tail -n +2` drops the name line, and eval binds the body to
# a new name. Copying the body by hand would put a second stack-recording implementation in the
# repository, which is the defect shape that put check-plan and bench/run out of step.
eval "_native_stack_manifest() $(declare -f provider_manifest | tail -n +2)"

provider_manifest() {
    _native_stack_manifest | NATIVE_FIELDS="$(printf \
        '{"provider":"native","client":"native","client_version":null,"max_turns":%s,"temp":%s}' \
        "$NATIVE_MAX_TURNS" "$NATIVE_TEMP")" python3 -c '
import json, os, sys

try:
    manifest = json.load(sys.stdin)
except ValueError:
    manifest = {}
manifest.update(json.loads(os.environ["NATIVE_FIELDS"]))
print(json.dumps(manifest, indent=2))
'
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
        --max-turns "$NATIVE_MAX_TURNS" \
        --writable "${HANDOFF_PLAN_WRITABLE:-}" \
        --readonly "${HANDOFF_PLAN_READONLY:-}" \
        ${NATIVE_EXTRA_ARGS:-}
}
