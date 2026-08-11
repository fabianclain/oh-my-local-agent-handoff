# Does dropping the window from 128k to 96k reduce the parse-failure rate?
#
#   tools/overnight bench/queues/ctx-98304.sh
#
# Last night ran at 131072 and llama.cpp's harmony parser discarded 23 of 1743 completions —
# 1.32%, against 0.69% across the earlier era at 32k and 64k. The two `header-transposition`
# faults known before that night both sat at 47–49k, so raising the window to 128k let
# conversations reach depths where the fault had already been observed. This asks whether pulling
# the window back takes the rate with it.
#
# `llamacpp-serve start` truncates the server log, so the audit at the end of this queue measures
# this session and nothing before it. That is the only reason a rate from one wave means anything.
#
# ON POWER, BEFORE READING THE RESULT
#
# Eight repetitions is roughly 350 completions. At 1.32% that is about 5 expected failures; at
# 0.69%, about 2. Those distributions overlap heavily, so this wave CANNOT settle the rate
# question — separating those two rates needs on the order of 1000+ completions, which is about 23
# runs and 2.5 hours. What eight repetitions can do is show a gross effect if there is one, and
# give the outcome comparison (usable tree, damage) against last night's 20 runs at 128k.
#
# Recorded here rather than discovered afterwards, because a small sample that produces a small
# difference reads as confirmation to anyone who has forgotten how small it was.

CLONE="${BENCH_CLONE:-$HOME/dev/agent-handoff-bench}"
HANDOFF="${HANDOFF_HOME:-$PWD}"

export BENCH_TIMEOUT_SECONDS=900
export BENCH_MAX_ATTEMPTS=2

# 98304, explicitly, rather than calibrate — calibrate would choose 131072 again, which is the
# thing being tested against.
job serve-96k --timeout 600 -- \
    "$HANDOFF/tools/llamacpp-serve" start gpt-oss-20b 98304

job conformance --timeout 900 -- \
    "$HANDOFF/tools/engine-conformance" --engine llamacpp --model gpt-oss-20b --repeat 3

# Carries the scratch/journal exclusion fix. Without it this wave would repeat last night's
# misclassification and report ~75% usable for a tree that was fine.
job sync-clone --no-gpu --timeout 300 -- \
    "$HANDOFF/tools/sync-bench-clone" "$CLONE"

# A separate arm label, so 96k runs never mix with last night's 128k runs in one directory.
# lcgptossl96 differs from lcgptossl only by asserting the server's window.
job wave-96k --cwd "$CLONE" --est 2100 --timeout 5400 -- \
    ./bench/run --plan wide --providers lcgptossl96 --repeat 8 --force

job readout --no-gpu --cwd "$CLONE" --timeout 300 -- \
    ./bench/compare wide lcgptossl lcgptossl96 --acts-on first-attempt

job peg-audit --no-gpu --timeout 120 -- "$HANDOFF/tools/peg-audit" --show 1
