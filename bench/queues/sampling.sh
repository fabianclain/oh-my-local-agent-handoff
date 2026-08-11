# Does deterministic sampling stop the harmony parser discarding output?
#
#   tools/overnight bench/queues/sampling.sh
#
# The two shapes llama.cpp discards are both malformed control tokens, and the server has been
# running at temperature 0.8 with a random seed throughout — llama.cpp's default, which is a
# creative-writing profile. Sampling has been varied here before, but only against outcome
# variance; never against the parse-failure rate.
#
# THE MEASURE IS PER ROUND, NOT PER COMPLETION
#
# A report is emitted once per round, so `patch-ok-no-report` is roughly five times more sensitive
# than the completion-level rate peg-audit prints. Baseline over 48 `wide` runs at temperature 0.8
# is 16 no-report rounds, 33%. Eight runs returning 0/8 is p = 0.04 against that — enough to detect
# a complete fix, not enough to size a partial one. If this comes back at 3/8 or 4/8, the answer is
# "no effect visible at this n", not "a small improvement".
#
# 98304 rather than 131072, matching the wave run this morning, so window is held constant and
# temperature is the only thing that moves.
#
# EXPECT THE OUTCOME NUMBERS TO GET WORSE. Deterministic sampling previously widened the run-to-run
# spread (CV 61% -> 76%). That is a different question from the one being asked here, and the two
# can move in opposite directions. Do not read a drop in accepted rounds as evidence about the
# parse rate, or the reverse.

CLONE="${BENCH_CLONE:-$HOME/dev/agent-handoff-bench}"
HANDOFF="${HANDOFF_HOME:-$PWD}"

export BENCH_TIMEOUT_SECONDS=900
export BENCH_MAX_ATTEMPTS=2

# The whole variable. lcgptossldet reads it back from /props and refuses if it did not take, so a
# flag that silently fails to apply cannot masquerade as a result.
export LLAMACPP_EXTRA_ARGS="--temp 0 --top-p 1 --top-k 0 --seed 42"

job serve-deterministic --timeout 600 -- \
    "$HANDOFF/tools/llamacpp-serve" start gpt-oss-20b 98304

# Safety check only. This CANNOT detect the fault under test — it passed 21/21 on the broken stack
# twice, because it exercises tool calls and the fault is a final-channel message. It is here to
# catch a stack that deterministic sampling has broken outright.
job conformance --timeout 900 -- \
    "$HANDOFF/tools/engine-conformance" --engine llamacpp --model gpt-oss-20b --repeat 3

job sync-clone --no-gpu --timeout 300 -- \
    "$HANDOFF/tools/sync-bench-clone" "$CLONE"

job wave-deterministic --cwd "$CLONE" --est 2100 --timeout 5400 -- \
    ./bench/run --plan wide --providers lcgptossldet --repeat 8 --force

# Against lcgptossl96, which is the same plan at the same window and differs only in sampling.
job readout --no-gpu --cwd "$CLONE" --timeout 300 -- \
    ./bench/compare wide lcgptossl96 lcgptossldet --acts-on first-attempt

# The mechanism, measured directly. The server restart above truncated the log, so this reads only
# the deterministic session.
job peg-audit --no-gpu --timeout 120 -- "$HANDOFF/tools/peg-audit" --show 1
