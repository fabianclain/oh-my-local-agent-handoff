# Overnight queue — hunting harness defects with a plan shape the gates have never seen.
#
#   tools/overnight bench/queues/site-night.sh --until 07:00
#   tools/overnight bench/queues/site-night.sh --list
#
# WHAT IS BEING ASKED, AND WHY IT IS NOT A MODEL COMPARISON
#
# The goal this night is harness reliability, not a number about gpt-oss. Every gate here was
# built against PHP fixtures; `site` and `site-dark` are the first plans that create a file rather
# than edit one, verify with something other than `php -r`, and gate on markup and colour. The
# runs are a way to walk those paths under load and see what breaks.
#
# That reframes what counts as a good night. A run the model fails is cheap; a run the HARNESS
# mis-scores, crashes on, or attributes to the model is the find. Six of this project's recorded
# defects were mistaken for model behaviour before they were caught.
#
#   site        the happy path, already measured at 3/3 accepted, ~110s, one edit. Kept because a
#               regression here is a harness regression: nothing about the plan can drift.
#   site-dark   the same page in two colour schemes. Expected to fail often, which is the point —
#               the repair loop, the feedback renderer and the failure branches of the outcome
#               taxonomy only execute on runs that fail once.
#   semantic    the one plan that asks whether a plausible WRONG answer gets through. Nine
#               implementations exist and one disagreed with the specification on 2,283 of 4,000
#               fuzzed trials while passing every gate. That rate is the project's headline safety
#               claim and its confidence interval is currently 2%-43%.
#
# WAVES, NOT ARMS IN SEQUENCE
#
# Four repetitions of each plan, then a readout, repeated. Whenever this stops — a deadline, a
# dead server, someone waking up early — the plans are balanced at whatever n they reached, and
# the statistics at the end are identical to running them in blocks. Only the failure mode differs.

CLONE="${BENCH_CLONE:-$HOME/dev/agent-handoff-bench}"
HANDOFF="${HANDOFF_HOME:-$PWD}"

# `site` medians ~110s and `site-dark` is a longer page, so 900s is roughly six times the expected
# worst case — enough that a wedged run is caught rather than allowed to eat the night.
export BENCH_TIMEOUT_SECONDS=900
export BENCH_MAX_ATTEMPTS=2

# --- before anything spends GPU -----------------------------------------------------------------

# Answered from the server's own log, in seconds. Also establishes the pre-night baseline for the
# parse-failure rate, which is the number the morning audit is compared against.
job peg-audit-before --no-gpu --timeout 120 -- \
    "$HANDOFF/tools/peg-audit" --show 1

# The linter before the model, every time. It caught a scope guard in site.md that had silently
# stopped guarding — `git status --porcelain` collapses an untracked directory to one line.
job plan-lint --no-gpu --timeout 120 -- \
    "$HANDOFF/tools/plan-lint" "$HANDOFF/bench/plans/site.md" "$HANDOFF/bench/plans/site-dark.md" \
        "$HANDOFF/bench/plans/semantic.md"

# The gates themselves, against pages built to trip them. If these fail, every score tonight is
# meaningless and it is better to learn that at 00:30 than at 07:00.
job gate-selftests --no-gpu --timeout 900 -- \
    "$HANDOFF/bench/checks/site-audit-selftest"

# NOT calibrating. The context is pinned at 98304, verified resident with 2,165 MiB free, and
# `calibrate` walks candidates and leaves the LAST passing one serving — which on this card is
# 131072 and 948 MiB, a size no document names and too tight for a machine driving a display.
job doctor --no-gpu --timeout 300 -- \
    "$HANDOFF/tools/doctor"

# --- the waves ------------------------------------------------------------------------------------

for wave in 1 2 3 4 5; do
    flag="--append"
    [[ "$wave" == 1 ]] && flag="--force"

    job "wave$wave-site-dark" --cwd "$CLONE" --est 1200 --timeout 4200 -- \
        ./bench/run --plan site-dark --providers native --repeat 4 "$flag"

    job "wave$wave-semantic" --cwd "$CLONE" --est 900 --timeout 4200 -- \
        ./bench/run --plan semantic --providers native --repeat 4 "$flag"

    # `site` is the control that cannot drift. Two per wave rather than four: it is here to catch a
    # harness regression, not to be measured again.
    #
    # Wave 1 forces, which ARCHIVES the ten development runs rather than appending to them. Those
    # were taken while the plan and the gates were still being changed, and pooling a development
    # phase with a measurement phase is how a number stops meaning anything.
    job "wave$wave-site" --cwd "$CLONE" --est 500 --timeout 2400 -- \
        ./bench/run --plan site --providers native --repeat 2 "$flag"

    job "wave$wave-readout" --no-gpu --cwd "$CLONE" --timeout 300 -- \
        ./bench/summary

    # Acceptance is the weaker claim. A semantic run the gates accepted and the fuzzer rejects is
    # the finding worth waking up to, and it costs no GPU.
    #
    # The PLAN directory, not an arm inside it — this iterates the arms beneath what it is given.
    #
    # It was briefly narrowed to bench/results/semantic/native, to stop wave 1 reporting a finding
    # recorded days earlier. That silently disabled it: given an arm it reads each run as an arm,
    # checks nothing, and exits 0, which in a queue log is indistinguishable from "all correct".
    # The fuzzer now refuses to report a pass over zero implementations, and the way to scope a
    # night is to archive the arms that do not belong to it — which is what was actually needed.
    job "wave$wave-fuzz" --no-gpu --cwd "$CLONE" --timeout 900 -- \
        ./bench/checks/fuzz-all-semantic bench/results/semantic
done

# --- what the morning reads ---------------------------------------------------------------------

job peg-audit-after --no-gpu --timeout 120 -- "$HANDOFF/tools/peg-audit" --show 0

job turn-economy --no-gpu --cwd "$CLONE" --timeout 300 -- \
    "$HANDOFF/tools/turn-economy" bench/results/site-dark bench/results/site bench/results/semantic

job report-audit --no-gpu --cwd "$CLONE" --timeout 300 -- \
    "$HANDOFF/tools/report-audit" bench/results/site-dark bench/results/semantic

job final-summary --no-gpu --cwd "$CLONE" --timeout 300 -- ./bench/summary
