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

## Result: gpt-oss-20b cannot survey, and the reason is not effort

Six samples, two unrelated features, 56 minutes of GPU.

| task | sample | verdict | fidelity | change surface | recall | code recall | unknowns |
|---|---|---|---|---|---|---|---|
| dead-hosts | 1 | fabricated | 0.50 | 4 files | 0.11 | 0.12 | 0 |
| dead-hosts | 2 | trustworthy | 1.00 | **0 files** | 0.00 | 0.00 | 0 |
| dead-hosts | 3 | fabricated | 1.00 | 5 files | 0.11 | 0.12 | 0 |
| visual-track | 1 | fabricated | 0.86 | 3 files | 0.09 | 0.11 | 0 |
| visual-track | 2 | fabricated | 1.00 | 4 files | 0.27 | 0.33 | 0 |
| visual-track | 3 | fabricated | 0.71 | 4 files | 0.27 | 0.33 | 0 |

**Recall 0.00–0.27, mean 0.14.** Not one sample found even a third of the files its feature
touched. Five of six were caught fabricating. The single `trustworthy` verdict is the worst
sample in the set: 751 seconds to produce a dossier claiming *nothing*, which passes a gate that
can only check claims that exist.

### It surveys lexically, not structurally

This is the mechanism, and it is the same in both domains:

    across all six surveys:  20 files proposed, 1 of them new
    across both real changes: 20 files touched, 7 of them new

The model looks for **files whose text contains the words in the task**. New files contain none of
those words — they do not exist yet — so it proposes almost none. For `visual-track` it planned to
display visual information the schema has nowhere to store, never once proposing a migration.

That is not a diligence problem and no prompt fixes it. Roughly 35% of each real change was
structure that had to be *invented*, and the search-shaped survey is blind to all of it by
construction.

### It never declares uncertainty

`unknowns: 0` in all six, while covering a seventh of the change. The schema devotes a field to
this, describes it as an answer rather than a failure, and states the model is not scored on
confidence. It declined every time. A dossier cannot be safely consumed if the party writing it
will not mark its own edges.

### The gate works, and needs all three checks

Sample 3 quoted **flawlessly — fidelity 1.00** — and was still fabricating: it ran
`grep -R "DeadHost" -n tests/Feature`, which correctly returned nothing, then reported

    tests/Feature/Crawler/DeadHostReportTest.php
    tests/Feature/Crawler/DeadHostsPageTest.php

as the result. It invented plausible filenames for the feature it was asked to survey, which would
have told a planner that partial support already existed. **A quote-only gate would have passed
this dossier.** The search replay is what caught it, and that is the argument for three independent
claim shapes rather than one good one.

### Variance is high relative to the mean

`visual-track` drew 0.09, 0.27, 0.27; `dead-hosts` drew 0.11, 0.00, 0.11. A planner has no way to
know which draw it received, so even the mean overstates what one dossier is worth.

## What this settles

**The orchestrator cannot stop reading.** Reading is where the 84% lives, and this was the one
cheap way to move it. It does not move. The negative result stands and the route is closed at
20B — not because implementation is weak, but because *deciding what must change* is, which is the
same seam the implementation numbers already showed: plan 6a (design a partial) lost three rolls
and 2,450 seconds, while plan 6b (register a section, with 5b already there to copy) landed 14/14
first roll.

**The boundary that predicts success is whether a sibling exists to copy** — not frontend versus
backend, and not planning versus implementing. The local model is strong at producing another one
of something and weak at establishing what is true. Every result in this project fits that line.

**One confound was found and corrected.** The first run's export stripped `.git` to close a leak,
so `git grep` answered "fatal: not a git repository" — and the model reported two files as its
result anyway. The snapshot now runs `git init` with a single commit: the tool works, the future is
still unreachable. A re-run of `dead-hosts` under the corrected instrument moved nothing:

| run | sample 1 | sample 2 | sample 3 | new files proposed |
|---|---|---|---|---|
| original (no `.git`) | 0.11 | 0.00 | 0.11 | 1 of 9 |
| corrected (`git grep` works) | 0.11 | 0.11 | 0.11 | **0 of 14** |

The model reached for `git` **zero times out of three searches** in the first corrected sample,
which is why the confound was smaller than it looked: it does not use the tool whose absence was
handicapping it. Recall is flat at 0.11 across six samples of this task.

The corrected run also produced the worst single dossier of the whole probe — sample 3 at
**fidelity 0.111, eight of nine quotes absent** — while reading exactly as confident as the others.
Nothing in its prose distinguishes it from sample 1 at 0.909. That is the case the gate exists for,
and the only reason it is visible.

## What is NOT settled

Whether a larger local model surveys. Nothing here separates "20B cannot do this" from "this is
hard"; the failure shape — lexical search, no invented structure, no declared uncertainty — is
characteristic of small models, but that is a hypothesis this probe cannot test.

The instrument is reusable and the ground truth is free: point `bench/survey-probe` at another
model and it answers in an hour.
