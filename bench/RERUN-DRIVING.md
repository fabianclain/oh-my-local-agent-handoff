# One variable: where the waiting happens

Feature 2 of the machine-panels series is re-run with **the same plans, the same tests, the same
base commit**. Nothing about the work changes. The only difference is that the sequence is driven
from a subagent instead of from the reviewer's own session.

This is not a test of the model, the plans or the feature. All three are already known-good — these
exact plans landed the panel. It is a test of one number.

## What is being measured

    feature 2, driven from the reviewer's session   1,877 turns   603.6M cache reads   408,017 output
    feature 1, driven from subagents                  257 turns    66.1M               362,566
    target                                           ~250 turns   under 80M

Nine times the cost, same series, same reviewer role. The subagents were never preventing the
polling — they were holding it somewhere cheap, ~36k a turn instead of ~321k.

## Setup

    cd /home/fabbs/dev/monolith/local-implementer
    TREE="$(bench/monolith-worktree machine-rerun fe871179)"
    cd "$TREE"
    git log --oneline -1     # MUST be fe87117 "Machine panels 5b — the Pressure panel"

That commit is feature 1 complete and feature 2 not started. Copy the two plans and the tests that
feature 2 finished with — they are the known-good ones, and re-deriving them would reintroduce the
variable this run exists to remove:

    P=/home/fabbs/dev/bench-trees/machine-panels
    cp $P/.claude/plans/machine-panels-6b-thermals-metrics.md .claude/plans/
    cp $P/.claude/plans/machine-panels-7b-thermals-panel.md   .claude/plans/
    cp $P/tests/Feature/Machine/*Thermal* tests/Feature/Machine/ 2>/dev/null || true
    git add -A && git commit -m "the thermals plans and tests, as feature 2 finished with them"

Then confirm the tree is clean and both plans pass:

    handoff prepare machine-panels-6b-thermals-metrics
    handoff prepare machine-panels-7b-thermals-panel

## The run

**Drive from a subagent. Tell it explicitly not to return until the sequence has exited.** Give it
only the repository path and the two slugs — nothing about the feature, the design or why.

    handoff sequence --reroll 2 machine-panels-6b-thermals-metrics machine-panels-7b-thermals-panel

Then **produce nothing** until it returns. No polling, no shell checks, no status turns, no
per-step monitor. If you catch yourself typing "I'll wait", you have just paid a full context pass
to say so.

You will probably want to poll anyway — that is the point. Inside the subagent it costs ~36k a
turn; in your session it costs ~321k. The container is what makes the lapse affordable.

## Report

    turns (assistant messages, from bench/token-report)
    cache_read total
    output tokens
    rounds, and each step's verdict and seconds
    T_impl

    bench/token-report machine-rerun

Then say plainly: **did you poll, and where?** An honest answer is worth more than a low number —
if the container held the cost down despite polling, that is the finding, and if you genuinely did
not poll then the instruction works when the plans are already written and nothing needs diagnosing.

## What would falsify the containment hypothesis

Turns near 1,877 again. That would mean the subagent is not where the polling lives and something
else drives it — most likely that the reviewer polls in proportion to how much it feels it needs to
diagnose, in which case a run with known-good plans was always going to be cheap and feature 2's
cost was re-specification, not containment.

Say so if that is what the numbers show.
