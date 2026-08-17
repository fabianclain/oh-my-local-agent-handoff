#!/usr/bin/env bash
#
# graphs-night-2 — the balancing half.
#
#   handoff overnight bench/queues/graphs-night-2.sh --until 07:45
#
# The first queue ran two pure passes against five consult ones, because consult was the arm being
# tested and the pure ones were expected to be short. They were not especially short, and the
# comparison is now the weaker for it: an average over two passes against an average over five,
# on an outcome whose per-step variance is already visible (2-collect has been accepted three
# times and rejected twice).
#
# So this adds pure passes only, to bring the arms closer to even before any difference between
# them is read as real.
B="/home/fabbs/dev/monolith/local-implementer/bench"

job graphs-pure-3 --cwd "$B/.." --est 3000 --timeout 5400 -- "$B/graphs-pass" pure-3 pure
job graphs-pure-4 --cwd "$B/.." --est 3000 --timeout 5400 -- "$B/graphs-pass" pure-4 pure
job graphs-pure-5 --cwd "$B/.." --est 3000 --timeout 5400 -- "$B/graphs-pass" pure-5 pure
