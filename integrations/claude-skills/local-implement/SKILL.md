---
name: local-implement
description: Design a feature, write a machine-verifiable plan, and have a local model on this machine implement it while the harness verifies the result. Use when the user asks to build or change something with the local model, mentions agent-handoff, or says "implement this locally". Also use when they want a plan written in verifiable form.
user-invocable: true
---

# Implementing with the local model

You design and specify. A local model (gpt-oss-20b on this machine) writes the code. The harness
decides whether the result is acceptable — not you, and never the model's own report.

Your job is the part the local model cannot do: turning a request into a specification whose every
claim is mechanically checkable. That is the measured bottleneck.

## When this is the right tool

**Good fit** — a contained change to code that already exists, with dictated signatures: adding a
method with specified behaviour, threading a parameter through, a pure service class, anything
where "did it work?" is answered by running a command.

**Almost everything should be split.** One large round is rarely the right shape; a sequence of
one-file steps usually is. See step 3 — decomposing is the default, not a fallback for when
something fails.

**Split it especially** — greenfield work, and anything mixing a service with a view.
The measured figures below come from a six-file *refactor*; creating new files from a spec is a
different shape with more freedom and far more surface to fake. Views are the worst case: a
three-line template can satisfy a text assertion while containing nothing real. Do the pure,
testable part as one round gated on its own tests, then the view as a second round gated on
rendering tests.

**Do it yourself instead** — and say so:

- Ambiguous requirements, or work needing design decisions. The implementer executes; it does not
  design. Difficulty must mean *more work*, not *more decisions*.
- Anything where a plausible wrong answer is indistinguishable from a right one: money, dates,
  aggregate SQL, permissions, concurrency. Never measured here, and where a local model is most
  dangerous.

## What to expect

~78% work on the first attempt, ~93% within three, roughly five minutes each — **on refactors**.
About one run in three produces a correct patch with no report at all. That is normal. Judge the
tree.

## The procedure

### 1. Understand the request before specifying it

Ask about anything that would change the code; stop when the answer would not. Boundary and zero
cases matter most. Read the files you intend to name.

### 2. Wire the project up

`handoff init` — idempotent, safe on a configured project.

### 3. Break the work into the smallest steps that each stand alone

**Default to decomposing.** If the user brings you a plan or a feature description, your first job
is to turn it into a *sequence* of small rounds, not one large one. One step should be something
you could describe in a sentence and verify in three commands.

Rough sizing, from what has been measured: **one to two files, three to six criteria, one
coherent behaviour.** A step touching six files is a round; a step touching one is a step.

**Be honest about what this buys.** It does *not* make the model more likely to succeed per step —
the six-file plan actually scored slightly better on first attempt (87%) than the four-file one
(80%). What it buys is:

- **Cheap failure.** A rejected step wastes one step. A rejected six-file round wastes everything,
  and a three-attempt failure costs three times a large run rather than three times a small one.
- **Localised diagnosis.** When a big plan fails you learn that *something* was wrong. When step 3
  of 5 fails you know exactly what.
- **Criteria a stub cannot fake.** This is the real prize. Narrow scope lets each criterion assert
  something specific; a six-file plan's criteria are necessarily coarser, and coarse criteria are
  what a stub slips past.
- **Banked progress.** Steps 1 and 2 are committed and safe while step 3 is retried.

**How to cut.** In order of preference:

1. **Pure logic before anything that renders.** A service class is close to an ideal fit; a view is
   the easiest thing in a codebase to fake past a text assertion. Never in the same step.
2. **One file per step** where the files are genuinely independent.
3. **One method or one behaviour per step** when a single file is doing several things.
4. **Data before presentation, and each layer gated on its own tests.**

Name them in order: `<slug>-1-service`, `<slug>-2-view`. Write every plan up front so the user can
review the whole sequence, then run them one at a time.

**Commit between steps.** This is mechanical, not stylistic: the implementer leaves changes
uncommitted, and every plan asserts how many files changed. If step 1's changes are still sitting
in the tree, step 2's file-count criterion counts them and fails. So after each accepted step, show
the user the diff and have them commit before the next one starts.

**Stop on the first rejection.** Do not run step 4 because step 3 failed — fix step 3's plan and
re-run it. Later steps usually assume the earlier ones landed.

### 4. Write the tests yourself, before the run

**This is the highest-leverage rule here.** If the implementer writes both the code and the test
that judges it, they agree with each other and are wrong together. A hand-written expectation of
`fresh: 6, stale: 1` caught an invented freshness rule; a model-authored test would have asserted
`fresh: 0, stale: 7` and passed green.

For anything numeric or stateful, write the assertions first, with the numbers you worked out
yourself. Then list those files under `## Files to read, not modify` so the implementer cannot
edit them:

```markdown
## Files to read, not modify

| Path | Why |
| --- | --- |
| `tests/Feature/RankingTest.php` | written by the reviewer; it judges this change |
```

The harness fails the round if a file listed there comes back modified.

### 5. Write the plan

Plans go where `.handoff/config.sh` says. Shape from `templates/plan.md`.

1. **One acceptance criterion, exactly one executable command, same order.** Enforced.
2. **Dictate the signatures** — exact names, parameters, return types.
3. **Assert against a stub, not against nothing.** The bar is not "would a do-nothing tree fail" —
   it is "would a *stub* fail". Four of ten criteria once passed against a three-line blade whose
   own comment said it only needed to render the string above. A single `assertSee('Rankings v2')`
   is indistinguishable from a real page. Assert what a stub cannot fake: the component type,
   several independent strings, a computed value, and the *absence* of placeholder markers.
4. **Name every file**, and assert the count:
   `test "$(git status --porcelain -- . ':(exclude).handoff' | wc -l)" -eq N`
5. **Anything you are tempted to repeat or bold needs a command instead.** Prose emphasis is not a
   control. A route-ordering constraint stated twice, in two sections, was still violated; what
   caught it was an acceptance command returning 404. If you find yourself writing "remember to",
   you have found a missing criterion.

### 6. Check it

`handoff check <slug>`. Fix what it rejects; read the advisories. Acceptance is not quality.

### 7. Run it

```bash
HANDOFF_PROVIDER=local handoff do <slug> >/tmp/run.log 2>&1; echo "verdict exit=$?"
```

**Redirect; do not pipe.** `handoff do x | tail` returns *tail's* exit status, not the verdict, and
that has already caused a failing round to be reported as passing.

**Isolation.** The implementer runs arbitrary commands in the live working tree with approval
disabled. One run wrote a bootstrap script that booted the real application against the real
database. If the project has live services, a shared SQLite file, or anything else with side
effects, run it in a scratch worktree instead:

```bash
git worktree add ../scratch-<slug> -b <slug>
```

and work there. Nothing in the harness does this for you.

### 8. Report what actually happened

Read `.handoff/runs/<slug>/evidence/evidence.md` and `handoff diff <slug>`. Report the verdict,
which gates failed, what changed from the diff, any **advisory** findings, and anything under
**"Not checked"** — absence of failure there is not evidence of correctness.

**Never repeat the model's report as fact.** Reports have claimed success over untouched trees. If
the gates accept and the report is missing, say the patch is good and the report is missing.

The implementer never commits.

### 9. When the gates reject

Read the failing command's output first. Usual causes in order: the plan was ambiguous, an
acceptance command was wrong, the model got it wrong. Fix the plan and re-run rather than patching
by hand.

**After two failed rounds, split that step further rather than attempting a third.** Two rounds failing the
same way is evidence about the task's shape, not about the model.

## Setup

`tools/setup-local-implementer` from the agent-handoff checkout. `llama-server` does not survive a
reboot: `tools/llamacpp-serve start gpt-oss-20b 65536`. Full guide: `docs/START-HERE.md`.
