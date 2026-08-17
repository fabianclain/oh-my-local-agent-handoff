#!/usr/bin/env bash
#
# graphs-seven — the same feature with the repair step removed.
#
#   handoff overnight bench/queues/graphs-seven.sh --until HH:MM
#
# Last night, ten passes over eight steps: half of them stopped for reasons that had nothing to do
# with whether the model could write the code. Three died on `3b-shape`, a repair plan from the
# original session with no work left to do once `3-series` succeeds; two died on pint alone.
#
# This drops `3b-shape` and changes nothing else. Pint is deliberately left as it was — having the
# harness format for the model would remove a whole failure class, but it also stops the round
# being judged on it, and that is a decision to take deliberately rather than fold into a run that
# is measuring something else.
#
# So this answers exactly one question: with the step that should never have been in the sequence
# removed, how far does a feature get unattended?
B="/home/fabbs/dev/monolith/local-implementer/bench"
S="crawler-graphs-1-schema crawler-graphs-2-collect crawler-graphs-3-series crawler-graphs-4a-command crawler-graphs-4b-wiring crawler-graphs-5a-chart crawler-graphs-5b-page"

job seven-pure-1    --cwd "$B/.." --est 4200 --timeout 6000 -- env "GRAPHS_STEPS=$S" "$B/graphs-pass" seven-pure-1    pure
job seven-consult-1 --cwd "$B/.." --est 5400 --timeout 7200 -- env "GRAPHS_STEPS=$S" "$B/graphs-pass" seven-consult-1 consult
job seven-pure-2    --cwd "$B/.." --est 4200 --timeout 6000 -- env "GRAPHS_STEPS=$S" "$B/graphs-pass" seven-pure-2    pure
job seven-consult-2 --cwd "$B/.." --est 5400 --timeout 7200 -- env "GRAPHS_STEPS=$S" "$B/graphs-pass" seven-consult-2 consult
