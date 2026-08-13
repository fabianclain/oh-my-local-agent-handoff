# Continuation queue — the two arms that are still producing information.
#
#   tools/overnight bench/queues/site-night-2.sh --until 06:45
#
# site-night.sh runs five waves and finishes around 04:00, leaving three hours of card idle. This
# picks up from there, and it drops what has stopped paying.
#
# WHAT CHANGED, AND WHY
#
#   `site` is dropped entirely. Ten development runs and six queue runs, every one accepted at
#   12/12 on the first attempt. It was kept as a regression control on the theory that a change in
#   it would mean a harness change, and nothing has changed in it — including through five harness
#   fixes tonight. Sixteen identical results is enough.
#
#   `site-dark` continues, and the reason inverted overnight. It looked saturated at 12/12, then
#   run 16 failed genuinely: a dark block covering thirteen selectors and missing five containers,
#   so the feature cards render #c9d1d9 on an un-overridden #ffffff at 1.54:1. Two independent
#   gates agree on it. That makes this a ~1-in-16 instrument rather than a happy path, and the
#   failure rate is worth pinning down — n=16 puts it somewhere between 0.2% and 30%.
#
#   `semantic` continues because it carries the headline number. Sixteen implementations tonight,
#   all correct under 4,000-trial fuzzing, against one wrong in the nine recorded before. Every
#   further wave narrows an interval that started at 2%–43%.
#
# WAVES, SMALLER AND MORE OF THEM
#
# Three repetitions rather than four, so a readout lands roughly every fifteen minutes and an
# interruption costs less. The arithmetic at the end is identical either way.

CLONE="${BENCH_CLONE:-$HOME/dev/agent-handoff-bench}"
HANDOFF="${HANDOFF_HOME:-$PWD}"

export BENCH_TIMEOUT_SECONDS=900
export BENCH_MAX_ATTEMPTS=2

# No calibration, no --force anywhere in this file. Both arms APPEND to what site-night.sh
# collected: same clone, same harness_tree, same plans, so the runs pool honestly. A --force here
# would delete the very data this is meant to extend.
job doctor --no-gpu --timeout 300 -- "$HANDOFF/tools/doctor"

job peg-audit-before --no-gpu --timeout 120 -- "$HANDOFF/tools/peg-audit" --show 0

for wave in 6 7 8 9 10 11 12; do
    job "wave$wave-site-dark" --cwd "$CLONE" --est 900 --timeout 3600 -- \
        ./bench/run --plan site-dark --providers native --repeat 3 --append

    job "wave$wave-semantic" --cwd "$CLONE" --est 700 --timeout 3600 -- \
        ./bench/run --plan semantic --providers native --repeat 3 --append

    # The plan directory, never an arm inside it. Narrowed to an arm this exits 0 having checked
    # nothing, which is how it was silently disabled earlier tonight.
    job "wave$wave-fuzz" --no-gpu --cwd "$CLONE" --timeout 900 -- \
        ./bench/checks/fuzz-all-semantic bench/results/semantic

    job "wave$wave-readout" --no-gpu --cwd "$CLONE" --timeout 300 -- ./bench/summary
done

job peg-audit-after --no-gpu --timeout 120 -- "$HANDOFF/tools/peg-audit" --show 0

job turn-economy --no-gpu --cwd "$CLONE" --timeout 300 -- \
    "$HANDOFF/tools/turn-economy" bench/results/site-dark bench/results/semantic

job report-audit --no-gpu --cwd "$CLONE" --timeout 300 -- \
    "$HANDOFF/tools/report-audit" bench/results/site-dark bench/results/semantic

job final-summary --no-gpu --cwd "$CLONE" --timeout 300 -- ./bench/summary
