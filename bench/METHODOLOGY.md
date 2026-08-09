# Benchmark methodology

## What this protocol measures

This protocol measures how a provider performs on a well-specified plan under the conditions in
`bench/run`: the same base commit, a separate worktree, the same project instructions, and fresh
verification of the plan after each attempt. The output is a record of observed runs.

It does not measure general model capability, work performed without a plan, long-horizon work,
or performance on tasks unlike the plans in this set. Results from these fixtures do not support
claims about another repository, language, workflow, or task shape.

## Limits on interpretation

Plan quality is the dominant factor. In this project every observed defect originated in a
specification, not an implementation. A benchmark of implementers is therefore substantially a
benchmark of the plans they receive, and these plans were written by one project maintainer with
that author's own blind spots.

Task selection is also a source of bias. The same project maintainer selected the initial set:
one mechanical shell task, one interface-integration shell task, and one deliberately
contradictory shell task. That selection does not represent coding work in general.

Cost is not compared unless a report states the pricing basis. Subscription access and
pay-as-you-go access are not comparable per token without that context.

The default repetition count is N=3 for each plan-provider pairing. The rendered report states
the actual N and shows every run individually. With a small N, no statistical conclusion is
drawn. Repetition is necessary because provider output is non-deterministic: the same provider
and plan can produce different results, and the spread must remain visible.

## How to read this

Read a row as evidence about one provider attempt on one plan inside this protocol. Do not quote a
single row as a general capability claim. Check the raw handoff report, verification log, tree
diff, and any reported deviation together; the ambiguity fixture in particular is informative
because acknowledging the contradiction is part of the evidence even when both checks cannot
pass.

## Void runs

A run blocked by a defect in the harness, the adapter, the configuration or the machine is not a
model result and is not scored. Re-run it after fixing the cause.

Counting harness faults as model faults yields confident wrong conclusions. In this repository's
own history, a model was recorded as fabricating a blocker when it had been served a 4,096-token
context and could not see the plan; another was recorded as stalling when the adapter had blocked
on stdin; and a whole round vanished because `--force` deleted every provider's results rather
than the one being re-run.

The test: could a different harness, configuration or machine have produced a different outcome
for the same model and the same prompt? If yes, the run is void.

A result stays counted when the cause is real and outside the harness — a model that runs out of
context because the hardware cannot hold more is a configuration result, reported as such, and it
changes when the configuration does.
