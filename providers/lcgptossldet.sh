#!/usr/bin/env bash
#
# Bench label: lcgptossldet — gpt-oss 20B, llama.cpp, reasoning low, served with deterministic
# sampling. Identical to lcgptossl in every other respect.
#
# THE QUESTION
#
# llama.cpp's harmony parser discards output it cannot map, and two sessions of measurement say the
# rate depends on how deep the conversation has gone rather than on the context window. Both of the
# shapes it discards are malformed *control tokens* —
#
#   <|channel|>final <|constrain|>JSON<|message|>{...}          a report addressed to the wrong channel
#   <|channel|>functions.run_commands<|channel|>commentary ...  a header with its halves transposed
#
# — and malformed control tokens are what a high sampling temperature produces. The server has been
# running at llama.cpp's default of temperature 0.8, top_p 0.95, top_k 40 and a random seed the
# whole time: a creative-writing profile, driving a task whose signatures are dictated and whose
# acceptance is mechanical.
#
# Sampling has been varied in this project before, but only ever against outcome variance, where
# determinism made the spread *wider* (CV 61% -> 76%). It has never been measured against the
# parse-failure rate, which is a different question with a different mechanism.
#
# WHAT WOULD COUNT
#
# The per-round measure, not the per-completion one: a report is emitted once per round, so
# `patch-ok-no-report` is roughly five times more sensitive than the rate `tools/peg-audit` prints.
# Baseline across 48 `wide` runs at temperature 0.8 is 16 no-report rounds — 33%. Eight runs at 0/8
# would be p = 0.04 against that, which is enough to detect a complete fix and not enough to
# measure a partial one.
#
# Expect the outcome numbers to get *worse* if the earlier finding holds. That is not a
# contradiction: this arm is aimed at the parse rate, and the two can move in opposite directions.
#
# Temperature is a server setting — Cline exposes no sampler controls — so this adapter cannot
# impose it and asserts it instead. Start the server with:
#
#   LLAMACPP_EXTRA_ARGS="--temp 0 --top-p 1 --top-k 0 --seed 42" \
#       tools/llamacpp-serve start gpt-oss-20b 98304
: "${HANDOFF_MODEL:=gpt-oss-20b}"
: "${HANDOFF_CLINE_THINKING:=low}"
export HANDOFF_MODEL HANDOFF_CLINE_THINKING
# shellcheck disable=SC1090
source "$(dirname "${BASH_SOURCE[0]}")/lcpp.sh"
provider_name() { echo "lcgptossldet"; }

_lcgptossldet_base_preflight() { :; }
eval "_lcgptossldet_base_preflight() { $(declare -f provider_preflight | tail -n +2) }"

provider_preflight() {
    _lcgptossldet_base_preflight || return 1
    local port="${LLAMACPP_PORT:-8071}" temp
    # Asserted from the server rather than assumed from how it was started. An arm whose entire
    # variable is a server flag is exactly the shape that becomes a silent no-op when the flag does
    # not take — and a no-op arm is indistinguishable from a real one in every artifact it leaves.
    temp="$(curl -fsS --max-time 5 "http://${LLAMACPP_HOST:-127.0.0.1}:${port}/props" 2>/dev/null |
        python3 -c 'import json,sys; print(json.load(sys.stdin)["default_generation_settings"]["params"]["temperature"])' 2>/dev/null)"
    [[ -n "$temp" ]] || { echo "could not read the sampling temperature from llama-server" >&2; return 1; }
    python3 -c "import sys; sys.exit(0 if abs(float('$temp')) < 1e-6 else 1)" || {
        echo "this arm requires deterministic sampling; the server is at temperature=${temp}." >&2
        echo "Start it with:" >&2
        echo "  LLAMACPP_EXTRA_ARGS=\"--temp 0 --top-p 1 --top-k 0 --seed 42\" \\" >&2
        echo "      tools/llamacpp-serve start gpt-oss-20b 98304" >&2
        return 1
    }
}
