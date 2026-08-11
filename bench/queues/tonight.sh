# Overnight queue — waves, not rounds.
#
#   tools/overnight bench/queues/tonight.sh --until 07:00
#   tools/overnight bench/queues/tonight.sh --list        # what would run, and for how long
#
# WHY WAVES
#
# The obvious way to run this is one arm to n=20, then the next. Do not. Two hours per arm means
# the first readout arrives after four hours, and an interruption at any point before the end
# leaves one complete arm and nothing to compare it against.
#
# A wave is four repetitions of every arm. The arms therefore stay balanced at every moment of the
# night: whenever it stops — a deadline, a dead server, you waking up early and wanting to look —
# there is a usable comparison at whatever n it reached. The statistics at the end are identical.
# Only the failure mode differs, and only one of the two failure modes is survivable.
#
# It also fixes the feedback interval, which is the thing actually worth optimising here. A wave is
# under an hour and each is followed by a readout, so by morning there is a *progression* of five
# comparisons rather than one verdict. At this plan's documented noise floor — roughly 20
# percentage points at n≈15 — a single verdict is quite likely to say "chance", and a progression
# at least shows whether the arms are drifting apart or sitting on top of each other.
#
# WHAT IS BEING ASKED
#
#   lcgptossl       control. gpt-oss 20B via llama.cpp, reasoning low. The arm every published
#                   number in bench/COMPARISON.md was taken under.
#   lcgptossllint   round 16. Identical, except the editing rules demand a syntax check after every
#                   write and a repair before anything else. Targets the failure that ended the two
#                   most promising rounds of a real feature: a parse error, then the rest of the
#                   budget spent building on a file that no longer parsed.
#
# Round 15 (whole-file writes) is deliberately absent. Its own entry in docs/BENCHMARK-QUEUE.md
# says round 16 probably matters more, and 15 additionally conflicts with the patch-only gate —
# a conflict worth resolving deliberately rather than at midnight.
#
# Round 17 is here as a log audit rather than an hour of GPU time, because the evidence turned out
# to already exist in llama-server's own log. Round 12 is dropped: the audit shows the missing
# reports are a parser fault, so an arm that changes the report channel is measuring the wrong
# thing.

CLONE="${BENCH_CLONE:-$HOME/dev/agent-handoff-bench}"
HANDOFF="${HANDOFF_HOME:-$PWD}"

# Shorter than the defaults, on purpose. `wide` has a ~300s median, so an hour-long timeout means a
# single wedged run costs twelve normal ones. Two attempts rather than three for the same reason:
# both arms act on the first write, so the third attempt is mostly buying wall-clock.
export BENCH_TIMEOUT_SECONDS=900
export BENCH_MAX_ATTEMPTS=2

# --- before anything spends GPU time ------------------------------------------------------------

# Round 17, answered from the server's own log. Seconds, not an hour.
job peg-audit --no-gpu --timeout 120 -- \
    "$HANDOFF/tools/peg-audit" --show 1

# The largest context that stays fully GPU-resident, measured rather than chosen. Everything below
# runs on whatever this settles on, so it must happen before the first wave and never again.
job calibrate --timeout 900 -- \
    "$HANDOFF/tools/llamacpp-serve" calibrate gpt-oss-20b

# The stack must be emitting usable tool calls before any of this means anything. An engine fault
# and a model failure are indistinguishable from a results directory.
job conformance --timeout 900 -- \
    "$HANDOFF/tools/engine-conformance" --engine llamacpp --model gpt-oss-20b --repeat 3

job sync-clone --no-gpu --timeout 300 -- \
    "$HANDOFF/tools/sync-bench-clone" "$CLONE"

# --- the waves ----------------------------------------------------------------------------------
#
# Four repetitions of each arm, then a readout, five times. --append is what makes the second and
# later waves add to the same results directory instead of refusing or replacing it.

for wave in 1 2 3 4 5; do
    flag="--append"
    [[ "$wave" == 1 ]] && flag="--force"   # wave 1 starts clean; the rest continue it

    job "wave$wave-control" --cwd "$CLONE" --est 1500 --timeout 4200 -- \
        ./bench/run --plan wide --providers lcgptossl --repeat 4 "$flag"

    job "wave$wave-lint" --cwd "$CLONE" --est 1500 --timeout 4200 -- \
        ./bench/run --plan wide --providers lcgptossllint --repeat 4 "$flag"

    # The readout. --acts-on first-attempt because both arms differ from the very first write, so
    # attempt 1 is a result here rather than a control.
    job "wave$wave-readout" --no-gpu --cwd "$CLONE" --timeout 300 -- \
        ./bench/compare wide lcgptossl lcgptossllint --acts-on first-attempt

    # Placed after the third wave rather than at the end: it is a different axis from the arms
    # above, and if the night is cut short this is the part that is not recoverable by simply
    # running more repetitions tomorrow.
    if [[ "$wave" == 3 ]]; then
        job semantic-gates --cwd "$CLONE" --est 2400 --timeout 5400 -- \
            ./bench/run --plan semantic --providers lcgptossl --repeat 6 --force
    fi
done

# --- the morning --------------------------------------------------------------------------------

job final-summary --no-gpu --cwd "$CLONE" --timeout 300 -- ./bench/summary

# Re-run at the end as well as the start. The interesting number is not the total but whether the
# parse faults cluster in the deep-context bucket, and a night of runs is a much larger sample of
# deep context than the log had this morning.
job final-peg-audit --no-gpu --timeout 120 -- "$HANDOFF/tools/peg-audit" --show 0
