#!/usr/bin/env bash
#
# graphs-night — replay the crawler-graphs feature overnight, with and without an orchestrator.
#
#   handoff overnight bench/queues/graphs-night.sh --until 08:00
#
# ## The question
#
# Can a feature land unattended, and does asking an orchestrator on a rejection change how far it
# gets? Seven passes over the same eight steps, from the same base, with one variable:
#
#   pure      stops at the first rejection. The completion rate with nobody in the loop.
#   consult   a rejection is diagnosed by Claude — model error earns one narrower retry;
#             an unsatisfiable criterion or any uncertainty still stops.
#
# Interleaved rather than blocked, so that a night cut short at 03:00 still holds both arms
# instead of two baselines and nothing to compare them against.
#
# ## What this is replaying
#
# A real feature, shipped in eight commits, whose nine-round session produced the field report
# these tools were built from. All eighty-five judged criteria were verified satisfiable against
# the shipped implementation before any of this was queued — so a rejection tonight is about the
# model or the process, and not about a test that could never pass. That check cost half an hour
# and no GPU, and two of that session's four failures would have been caught by it.
#
# Estimates come from that session's own round times: mean ~8 min across nine rounds, so ~65 min
# for eight steps, plus consult turns. --est is what the deadline plans against; --timeout is when
# a wedged pass is killed.

B="/home/fabbs/dev/monolith/local-implementer/bench"

job graphs-pure-1    --cwd "$B/.." --est 3000 --timeout 5400 -- "$B/graphs-pass" pure-1    pure
job graphs-consult-1 --cwd "$B/.." --est 4500 --timeout 7200 -- "$B/graphs-pass" consult-1 consult
job graphs-pure-2    --cwd "$B/.." --est 3000 --timeout 5400 -- "$B/graphs-pass" pure-2    pure
job graphs-consult-2 --cwd "$B/.." --est 4500 --timeout 7200 -- "$B/graphs-pass" consult-2 consult
job graphs-consult-3 --cwd "$B/.." --est 4500 --timeout 7200 -- "$B/graphs-pass" consult-3 consult
job graphs-consult-4 --cwd "$B/.." --est 4500 --timeout 7200 -- "$B/graphs-pass" consult-4 consult
job graphs-consult-5 --cwd "$B/.." --est 4500 --timeout 7200 -- "$B/graphs-pass" consult-5 consult
