#!/usr/bin/env bash
#
# Bench label: lcgptossl0 — gpt-oss 20B, llama.cpp, reasoning low. Identical to lcgptossl in every
# respect except the serving stack's sampling, which is deterministic:
#
#   --temp 0 --top-p 1 --top-k 1 --seed 42
#
# The default was llama.cpp's own — temperature 0.8, top_p 0.95, top_k 40, random seed. That is a
# creative-writing profile, and it had never been varied here despite every comparison in this
# project being limited by run-to-run spread: wall clock ranging 4.9x within one arm, and two arms
# that are identical by construction differing 13/15 against 8/12 on their first attempt.
#
# Sampling cannot be set from Cline, which exposes no such flag, so it is set on the server and
# recorded in the manifest. Its control is round 6's lcgptossl arm (n=15).
#
# What to look at first is not the mean but the SPREAD, and the attempt-1 green rate.
: "${HANDOFF_MODEL:=gpt-oss-20b}"
: "${HANDOFF_CLINE_THINKING:=low}"
export HANDOFF_MODEL HANDOFF_CLINE_THINKING
# shellcheck disable=SC1090
source "$(dirname "${BASH_SOURCE[0]}")/lcpp.sh"
provider_name() { echo "lcgptossl0"; }

# Assert the condition this label claims.
#
# Sampling is a server setting, so unlike the feedback pin this adapter cannot impose it — and a
# label that cannot enforce what it names is one bad launch away from silently benchmarking the
# control twice. So it refuses instead of trusting whoever started llama-server.
_lcgptossl0_base_preflight() { :; }
eval "_lcgptossl0_base_preflight() { $(declare -f provider_preflight | tail -n +2) }"

provider_preflight() {
    _lcgptossl0_base_preflight || return 1
    local port="${LLAMACPP_PORT:-8071}" temp
    temp="$(curl -fsS --max-time 5 "http://127.0.0.1:${port}/props" 2>/dev/null |
        python3 -c 'import json,sys; print(json.load(sys.stdin)["default_generation_settings"]["params"]["temperature"])' 2>/dev/null)"
    [[ -n "$temp" ]] || { echo "could not read sampling settings from llama-server" >&2; return 1; }
    awk -v t="$temp" 'BEGIN { exit (t < 0.0001) ? 0 : 1 }' || {
        echo "this provider requires deterministic sampling; the server is at temperature ${temp}." >&2
        echo "Start it with: LLAMACPP_EXTRA_ARGS=\"--temp 0 --top-p 1 --top-k 1 --seed 42\" \\" >&2
        echo "                 tools/llamacpp-serve start ${HANDOFF_MODEL:-gpt-oss-20b} 65536" >&2
        return 1
    }
}
