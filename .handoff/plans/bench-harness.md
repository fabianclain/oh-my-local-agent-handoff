# bench/ — run the same plan through several providers, honestly

## Goal

Run one plan through multiple providers under identical conditions and record what actually
happened, so a comparison rests on evidence rather than on one anecdote and a good feeling.

**The output is a record, not a verdict.** This harness must never emit a ranking, a score out
of ten, or a "winner". The single most likely way this feature does harm is by producing a
number someone quotes.

## Context

Read `bin/handoff` and `providers/*.sh` first — the harness drives the existing driver and must
not reimplement any of it. Follow the house style: guard clauses, `set -euo pipefail`, comments
that name the failure a mechanism prevents.

### Why the current evidence is not enough

One plan has been run through Codex and one different plan through GLM. That supports no
comparison at all: different tasks, different difficulty, single runs each, and no isolation
between them. Anyone reading the repo could reasonably infer a claim that the data does not
support. This harness exists to make the difference between *anecdote* and *evidence* visible.

## Isolation is the core requirement

Providers must not see each other's work. Each run happens in a **separate `git worktree`** off
the same base commit:

```
git worktree add bench/.work/<plan>-<provider> <base-commit>
```

Run the provider there, capture the artifacts, then remove the worktree. Never run two providers
in the same tree, and never let run N+1 start from run N's output.

If a worktree cannot be created, **stop** — do not silently fall back to running in place. A
contaminated comparison is worse than none.

## What to measure

Only things that can be checked mechanically. For each (plan, provider, repetition):

| Metric | How |
| --- | --- |
| `status` | from the handoff report |
| `criteria_total` / `criteria_met` | count `- [ ]` lines in the plan; re-run the plan's verification commands and record pass/fail |
| `scope_violations` | files in the tree diff that the plan's *Files to touch* table does not list |
| `deviations` / `blockers` | counts from the report |
| `rounds_to_green` | 1 for a first-pass success; not attempted automatically — see below |
| `wall_clock_seconds` | measured |
| `exit_code` | the driver's |

**Do not compute a composite score.** Emit the raw numbers.

`rounds_to_green` cannot be automated honestly, because deciding what feedback to give is a
judgement. Record `1` when the first round meets every criterion, and `null` otherwise, with a
note that resume rounds are a manual follow-up. Do **not** fake it by re-dispatching with a
generic "fix it" prompt — that measures something else entirely.

### Repetitions

These models are non-deterministic. A single run per provider tells you almost nothing.
`--repeat=N` (default 3) runs each pairing N times, and the report shows **every** run, not an
average. Variance between repetitions of the same provider is itself a finding, and averaging
hides it.

## Commands

```
bench/run --plan <slug> --providers codex,glm --repeat 3
bench/report                                    # render results/ as markdown
```

Results land in `bench/results/<plan>/<provider>/<n>/` — handoff report, tree diff, timing,
verification output. Raw artifacts are kept; the report is derived and regenerable.

## The methodology document

`bench/METHODOLOGY.md`, written before any results are published. It must state plainly:

- **What this measures**: how a provider performs on a well-specified plan inside this protocol.
- **What it does not measure**: general model capability, performance without a plan, long-horizon
  work, or anything about tasks unlike those benchmarked.
- **Plan quality dominates.** In this project every observed defect originated in a
  specification, not an implementation. A benchmark of implementers is substantially a benchmark
  of the plans they were given, and the plans were written by one person with their own blind
  spots.
- **Task selection bias.** Whoever writes the plans chooses the shape of the work. Say who wrote
  them and what kinds of task are represented.
- **Cost is not compared** unless the pricing basis is stated, since subscription and
  pay-as-you-go are not comparable per token.
- **Sample size.** State N. With small N, report runs individually and draw no statistical
  conclusion.
- **Non-determinism.** Same provider, same plan, different results — show the spread.

Include a short "how to read this" section warning against quoting a single row as a capability
claim.

## The plan set

Create `bench/plans/` with **three** plans of deliberately different shape, each self-contained,
each verifiable mechanically, and none depending on this repo's own state:

1. **mechanical** — a small script with clearly specified behaviour and guards
2. **integration** — something that must inspect an existing interface and conform to it
3. **ambiguity** — a plan containing one deliberate internal contradiction, to see whether the
   provider flags it under `deviations` or silently picks a side

The third is the most interesting and the most likely to be got wrong. It exists because a
provider that follows a bad instruction *and reports it* is doing the right thing, and no
pass/fail metric captures that. Its result must be recorded as a quoted deviation, not a score.

## States to handle

- a provider not installed or unauthenticated → record `skipped` with the reason; do not abort
  the whole matrix
- a worktree that cannot be created → abort loudly
- a run that times out → record `timeout` with the elapsed seconds, keep artifacts
- a handoff report that is missing or unparseable → record it as a failure mode, not a crash
- `--repeat 1` → works, and the report says the sample is one run
- results directory already populated → refuse to overwrite without `--force`

## Fixtures

No new dependencies. `python3` is already required. Do not add a test framework; verify by hand
and report exact commands and output.

## Files to touch

| Path | Action |
| --- | --- |
| `bench/run` | create, chmod +x |
| `bench/report` | create, chmod +x |
| `bench/METHODOLOGY.md` | create |
| `bench/plans/{mechanical,integration,ambiguity}.md` | create |
| `bench/.gitignore` | create — ignore `.work/` and `results/` |
| `README.md` | modify — one short section pointing at bench/, explicitly saying no results are published yet |

Do not modify `bin/`, `providers/`, or `schemas/`.

## Acceptance criteria

- [ ] `bench/run --plan mechanical --providers codex --repeat 1` completes and writes artifacts
- [ ] Each run happens in its own worktree, removed afterwards; `git worktree list` is clean
- [ ] A missing or unauthenticated provider is recorded as `skipped`, and the matrix continues
- [ ] Scope violations are computed from the plan's *Files to touch* table against the tree diff
- [ ] `criteria_total` is parsed from the plan's checklist
- [ ] **No composite score, ranking, or "winner" appears anywhere** in code or output
- [ ] `bench/report` renders every run individually; nothing is averaged
- [ ] `METHODOLOGY.md` states what is not measured, and names plan quality as the dominant factor
- [ ] Re-running without `--force` refuses rather than overwriting results
- [ ] `bash -n` passes on both scripts; no new dependencies
- [ ] README says clearly that no comparison results are published yet

## Verification

```bash
bash -n bench/run bench/report
bench/run --plan mechanical --providers codex --repeat 1
git worktree list
bench/report | head -40
```

## Out of scope

- Publishing any results. This round builds the harness; running it is a separate decision.
- Modifying `bin/`, `providers/`, or `schemas/`.
- Any scoring, weighting, ranking, or aggregate metric.
- Automating `rounds_to_green` by generating feedback.
- Adding dependencies or a test framework. Committing.
