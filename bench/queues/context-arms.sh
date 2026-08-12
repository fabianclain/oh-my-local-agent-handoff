# Does making the conversation shorter make the loop better?
#
#   handoff overnight bench/queues/context-arms.sh --until HH:MM
#
# THE QUESTION
#
# Last night established the mechanism and left the fix unmeasured. Depth is what the parse fault
# tracks — 0.00% below 8k, 4.04% at 8–16k, 4.53% at 16–32k over 3,131 completions — and the loop
# spends its depth badly: tool results are 76% of the text the conversation carries, and 59% of
# read results had been superseded by a later write to the same file by the end of the round.
#
# So the model is re-sent, every turn, the old contents of files it has already rewritten. Three
# arms ask whether fixing that is worth anything.
#
#   native        control. Unchanged, and the arm that went 18/18 last night.
#   nativeprune   --prune-superseded alone, so the effect of pruning is not confounded with the
#                 other two changes.
#   nativelean    all three: pruning, submit_report withdrawn above 10k, and the loop stopped after
#                 three unparseable writes.
#
# WHAT WOULD COUNT AS AN ANSWER
#
# Acceptance is the wrong headline here and will not move: native was 18/18 last night, so there is
# no room above it and any change can only look neutral or worse. The measures that can move:
#
#   final depth per round     the thing being changed. If this does not drop, nothing else can.
#   peg faults per round      85 across 18 rounds last night. Depth is its only known lever.
#   turn-limit rate           26 of 73 provider calls. Pruning buys turns without buying depth.
#   generated tokens          median 12,146 last night.
#
# A NULL RESULT IS THE LIKELY ONE and should be recorded as such. Two prompt-layer changes have
# already moved nothing here, and the register's standing lesson is that a mechanism that sounds
# right is not evidence. What makes this different from those is that it is not an instruction —
# but that argues it *could* work, not that it does.
#
# THE STACK, asserted rather than assumed. Same as last night so the numbers compare.
CLONE="${BENCH_CLONE:-$HOME/dev/agent-handoff-bench}"
HANDOFF="${HANDOFF_HOME:-$PWD}"

export BENCH_TIMEOUT_SECONDS=1200
export BENCH_MAX_ATTEMPTS=2
export HANDOFF_EXPECT_CTX=98304

job doctor --no-gpu --timeout 120 -- "$HANDOFF/tools/doctor"
job conformance --timeout 900 -- \
    "$HANDOFF/tools/engine-conformance" --engine llamacpp --model gpt-oss-20b --repeat 3
job sync-clone --no-gpu --timeout 300 -- "$HANDOFF/tools/sync-bench-clone" "$CLONE"

# Waves, so an interruption leaves the arms balanced. Last night proved the value of that twice.
for wave in 1 2 3 4 5 6; do
    flag="--append"
    [[ "$wave" == 1 ]] && flag="--force"

    for arm in native nativeprune nativelean; do
        job "w$wave-$arm" --cwd "$CLONE" --est 260 --timeout 3600 -- \
            ./bench/run --plan wide --providers "$arm" --repeat 3 "$flag"
    done

    job "w$wave-readout" --no-gpu --cwd "$CLONE" --timeout 300 -- \
        ./bench/compare wide native nativeprune --acts-on first-attempt
done

# --- the morning ---------------------------------------------------------------------------------

job final-prune --no-gpu --cwd "$CLONE" --timeout 300 -- \
    ./bench/compare wide native nativeprune --acts-on first-attempt
job final-lean --no-gpu --cwd "$CLONE" --timeout 300 -- \
    ./bench/compare wide native nativelean --acts-on first-attempt
job final-summary --no-gpu --cwd "$CLONE" --timeout 300 -- ./bench/summary

# The measures the comparison table does not carry. bench/compare scores outcomes; depth, faults
# and turn economy are where this change is supposed to act, and if they have not moved then a
# null on acceptance says nothing at all.
job depth-and-faults --no-gpu --timeout 300 -- \
    "$HANDOFF/tools/report-audit" "$CLONE/bench/results/wide/native" \
    "$CLONE/bench/results/wide/nativeprune" "$CLONE/bench/results/wide/nativelean"
job turn-economy --no-gpu --timeout 300 -- \
    "$HANDOFF/tools/turn-economy" "$CLONE/bench/results/wide/native" \
    "$CLONE/bench/results/wide/nativeprune" "$CLONE/bench/results/wide/nativelean"
job final-peg-audit --no-gpu --timeout 120 -- "$HANDOFF/tools/peg-audit" --show 1
