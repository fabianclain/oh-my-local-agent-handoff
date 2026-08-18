# Surveying — moving the reading, not the typing

## The negative result this starts from

Measured across five runs, the route this project built costs **4.3× the wall clock and 2.0× the
orchestrator's output tokens** of simply doing the work. That is not a tuning problem and no
amount of re-rolling fixes it, because the loss is structural:

| phase | share of orchestrator cost | who does it |
|---|---|---|
| planning | **84%** (of which ~89% is deciding, not writing) | the orchestrator |
| implementation | ~16% | the local model |

The split hands the local model the cheap half and then adds a review phase on top. A route that
offloads 16% and adds a phase was always going to come out behind. **We automated the typing.
Typing was never the cost.**

## Where the cost actually is

Planning is expensive not because deciding is hard but because deciding requires *reading the
repository*, and a stateless conversation re-sends everything it has read on every subsequent
turn. Planning cost is context accumulation. The local model has a GPU that is already paid for
and a context window that costs nothing to fill, so reading is precisely the work that is free on
this side of the wall.

So the inversion: **the orchestrator never opens a repository file.** It writes a brief in domain
terms and reviews a finished plan. Everything between those two points — locating, reading,
quoting, enumerating, drafting — happens locally.

## Why this is not obviously safe

Implementation was safe to delegate for exactly one reason: it had a gate. Acceptance criteria run
mechanically, so a bad round is a *detected* bad round and a re-roll costs GPU time instead of
correctness.

Reading has no such gate, and the failure surface is already known to be here rather than in the
model: **eight of nine rejections on the first feature were defects in the specification**, written
by the party that had actually read the files. A dossier that is confidently wrong is worse than
no dossier, because the planner decides on false premises and nothing downstream disagrees.

## What makes it gateable

A dossier, unlike a decision, contains no judgement. Every claim `schemas/survey.schema.json`
permits is one of three shapes, and all three are checkable by machine:

| claim | check |
|---|---|
| a quoted excerpt | must appear byte-for-byte in the file it names |
| a search | the literal command is re-run; the files it returns are compared with the files claimed |
| a path | must exist — or must *not* exist, when the dossier calls the file new |

`tools/dossier-verify` is that gate. It converts fabrication into a detected failure with a cheap
re-roll, which is the same trade that made the implementation half work — applied upstream for the
first time. Nothing before this gated the reading.

## The division that follows

**Orchestrator** — the brief, and one accept/annotate turn on the finished plan. The rule that
makes the saving real is that it *may not open a repository file*; without it the context quietly
refills and the saving evaporates. This is checkable: a file read during the brief is a violation.

**Local model** — survey the repository into a verified dossier, then draft the plan and its
criteria from brief + dossier.

**Machine** — `dossier-verify`, then `plan-lint`, then `bench/audit-criteria`: every criterion must
*fail* on the unmodified tree. Then `tools/sequence` implements it, exactly as today.

Locally-proposed criteria are less alarming than they sound, because `audit-criteria` already kills
the vacuous ones automatically. What survives is the criterion that is satisfiable but does not
capture intent — which is what the orchestrator's single review turn is for. Judgement stays.
Reading leaves.

## The hole, stated plainly

**`dossier-verify` catches invention. It does not catch omission.** A dossier that quotes six files
perfectly and never finds the seventh verifies clean, and the plan built from it is silently
incomplete — criteria included, because the criteria come from the same incomplete reading.

This is not a hypothetical, and the instrument demonstrates it on purpose. Against the dead-hosts
feature, a synthetic dossier carrying **2 of the 9 real files** scores:

```
verdict trustworthy, fidelity 1.00, recall 0.22
```

Search replay bounds the problem a little — a search claiming three hits where the tree returns
seven is caught — but it does not close it. Which is why the probe measures recall against real
diffs rather than trusting the gate, and why **recall, not fidelity, is the number that decides
whether this route is viable at all.**

## The probe

`bench/survey-probe` asks the one question everything else depends on: every measurement this
project has taken handed the model a **closed** task (here is the plan, execute it), and it went
15/15 and 14/14 first-roll. Surveying is an **open** task — nobody tells the model when it has
looked at enough — and stopping early or looping are the characteristic failures of a 20B model.
We had never asked it.

Two features are used, chosen so git already knows the answer:

| task | commit | files | why this one |
|---|---|---|---|
| `dead-hosts` | `7071556` | 9 | PHP **and** Rust; modifies an existing `FrontierService` |
| `visual-track` | `7fbe3a3` | 11 | different domain; modifies an existing editor and teleprompter |

Both were checked at content level for documentary leakage — not merely by filename. Three
candidates were **rejected** during selection, and the reasons are the method:

- **`bab8c56`** — its parent's `CLAUDE.md` already documents the feature verbatim, down to "the
  `/machine` host selector appears once a second host exists".
- **`41daf2b`** — a sibling plan in the tree describes the target page in detail and names the
  central file.
- **`0f6df67`, `5b3b4a5`** — almost entirely new files, so recall against them is trivially high
  and measures nothing.

Two further contamination channels were closed in the instrument itself. The ground-truth commit
lives in `GROUND-TRUTH.tsv` and **not** in the brief, because `tools/survey` cats the brief
straight into the prompt and a SHA in a comment is a SHA the model can `git show`. And the
checkout is a **history-free export**, not a worktree, because a worktree shares the object
database — `git log --all` from the parent commit still reaches the child. That is also the more
faithful setup: for a task that has not been done yet there is no future commit to find.

The briefs are written in user terms and name no file, no class and no directory. A brief that
says "add a HostHealthService" scores 100% recall and means nothing.

Sampling is at temperature 0.8, so **variance is a result, not noise**: if recall swings widely
between samples of one task, the dossier is not a dependable input even when its average looks
acceptable, because the planner cannot tell which sample it got.

## Status

The instrument is built and controlled in both directions — a perfect dossier scores 1.00/1.00, a
fabricated quote is caught at fidelity 0.00, and a 2-of-9 dossier passes the gate at recall 0.22.
`tools/dossier-verify-selftest` mutation-tests all thirteen fabrication shapes.

Results against gpt-oss-20b are recorded below once the probe has run.
