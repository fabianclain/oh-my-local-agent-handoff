---
name: local-drive
description: Drive an existing agent-handoff plan through the local model and report what the harness decided. Use when plans already exist and the job is running them, not writing them — "run the plans", "drive this through the local model", "get these steps through the gates".
user-invocable: true
---

# Driving an existing plan through the local model

## What you are doing

Someone else wrote the plans. A local model (gpt-oss-20b, on this machine) writes the code. A
harness runs each plan's own acceptance commands against the working tree and decides whether a
round stands.

You are the operator. You get the plans through the gates, or you report precisely why they cannot
get through. **You are not the planner.** The specification is someone else's work and changing what
it asks for destroys the only independent check in the loop.

You may narrow. You may not redesign:

| Allowed | Not allowed |
| --- | --- |
| Split a step into two smaller steps | Change what the feature does |
| Add a criterion that makes an existing one checkable | Drop a criterion because it keeps failing |
| Fix an acceptance command that is wrong about its own subject | Loosen a command until the code passes |
| Tighten a vague instruction into an exact signature | Choose a different design |

If a plan is wrong rather than unclear — the wrong approach, a missing dependency, an impossible
requirement — **stop and report it**. That is a finding, not a failure. Weakening a criterion until
the tree passes produces a green verdict that means nothing, which is worse than a red one.

## 1. Check the machine before you blame the model

```bash
handoff doctor
```

Blocking problems must be fixed before anything else runs. An environment fault and a model failure
are indistinguishable from the evidence bundle, and in this project six harness defects were
mistaken for model behaviour before anyone checked.

If `handoff` is not on PATH, use the absolute path to `bin/handoff` in the agent-handoff checkout —
an agent's shell does not always inherit an interactive PATH. If nothing answers on the llama.cpp
port, the model server is down, **or** your sandbox is blocking localhost.

## 2. Read the plans, and check them before running them

```bash
ls .handoff/plans/
handoff check <slug>          # would the harness accept this plan at all?
```

`check` rejects a plan whose acceptance criteria and verification commands differ in number — that
plan can never score full marks, and running it wastes a round. If it rejects a plan you were
given, fix the *counts* (one command per criterion, same order) and say you did. That is narrowing,
not redesigning.

Read every plan in the sequence before running the first. Later steps usually assume earlier ones
landed, and knowing where you are going changes how you read a failure.

## 3. Run one step at a time

```bash
HANDOFF_PROVIDER=local handoff do <slug>
```

It implements, verifies, and folds the verdict into its exit status, so a round the gates reject
fails even when the model exits cleanly. Do not pipe it to `tail` and read `$?` — you will get
`tail`'s status.

**Read the verdict, never the model's report.** About one run in three returns a correct patch with
no report at all, and reports have claimed success over trees that were never touched. The evidence
bundle is at `.handoff/runs/<slug>/evidence/evidence.md`.

## 4. When a round is rejected, find out which kind of failure it was

```bash
handoff log <slug>      # every round: outcome, criteria score, writes, adapter errors
```

The **writes** column decides what to do next, and getting this wrong wastes the most time:

| What you see | What it means | What to do |
| --- | --- | --- |
| `writes` is 0, adapter errors present | The round never happened | **Re-run the same plan once.** Do not re-specify |
| `context-overflow` | The task did not fit the window | Split the step. More instructions make it worse |
| `output-token-limit` | The turn was cut off mid-write | Expect a truncated file. Split the step |
| Criteria score dropped from the round before | The repair is damaging the tree | Stop. Revert to the last good state and take a different approach |
| A real, specific criterion failed | The model got it wrong | Repair once, then narrow the step |

`handoff stats` gives the same picture across every run in the project.

## 5. Repair once, then narrow

The harness will hand the model its own failing commands if you point it at the feedback:

```bash
HANDOFF_FEEDBACK_FILE=.handoff/runs/<slug>/feedback.md \
  HANDOFF_PROVIDER=local handoff do <slug>
```

Or let the ladder do the whole loop, including a hosted planner writing a narrower plan when two
local attempts have failed:

```bash
handoff auto <slug> --planners glm --attempts 2 --escalations 1
```

Use `--planners glm` when you are the operator: a second model reading the failure is worth more
than the same model that is already driving. The ladder refuses to let the planner and the
implementer be the same model, will not run a plan `check-plan` would refuse, and stops the moment
a round scores worse than the round before it.

**Never re-run an unchanged plan more than once.** The harness already retried internally with the
failing commands in hand. The exception is the "never happened" row above.

## 6. Commit accepted steps, and nothing else

The implementer never commits. You do, and only for a step the gates accepted:

```bash
handoff diff <slug>       # exactly what the round changed
git add -A && git commit -m "<what the step did>"
```

This is not optional in a sequence: every plan asserts how many files changed, so step 1's
uncommitted work fails step 2's file count.

**Never push. Never amend or rebase. Never commit a rejected round.** Work on a branch, and leave
the branch for a person to review.

## 7. Stop and report

Stop when the sequence is done, or when you hit any of these:

- Two rounds failing the same way. That is evidence about the task's shape, not the model's ability.
- A plan that is wrong rather than unclear.
- A rejected round whose fix would mean changing what the feature does.
- Anything requiring a decision you were not given the authority to make.

Report, in this order and in this much detail:

1. **Per step**: slug, accepted or not, criteria score, wall time.
2. **What you changed in any plan**, quoted, and why it was narrowing rather than redesign.
3. **What failed and how**, using the failure classes in step 4 — say which one, not just "it
   failed".
4. **What is uncommitted in the tree right now.**
5. **Specific questions for the planner.** "Should `fresh` mean 7 days or 30?" is useful.
   "The plan was unclear" is not.

Do not claim a step passed unless the harness said so. Your account of the work is subject to the
same rule as the local model's: the tree decides.
