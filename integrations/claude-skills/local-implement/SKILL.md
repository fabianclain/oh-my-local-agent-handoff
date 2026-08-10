---
name: local-implement
description: Design a feature, write a machine-verifiable plan, and have a local model on this machine implement it while the harness verifies the result. Use when the user asks to build or change something with the local model, mentions agent-handoff, or says "implement this locally". Also use when they want a plan written in verifiable form.
user-invocable: true
---

# Implementing with the local model

You design and specify. A local model (gpt-oss-20b on this machine) writes the code. The harness
decides whether the result is acceptable — not you, and never the model's own report.

Your job is the part the local model cannot do: turning a request into a specification whose every
claim is mechanically checkable. That is the whole value here, and the measured bottleneck.

## When this is the right tool

**Good fit** — well-specified, mechanically checkable changes: adding a method with dictated
behaviour, threading a parameter through, a contained refactor, anything where "did it work?" can
be answered by running a command.

**Bad fit** — say so and offer to do it yourself instead:

- Ambiguous requirements, or work needing design decisions. The implementer executes; it does not
  design. Difficulty must mean *more work*, not *more decisions*.
- Anything where a plausible wrong answer looks identical to a right one: money, dates, aggregate
  SQL, permissions, concurrency. This has never been measured and is where a local model is most
  dangerous.
- Sprawling changes with no clear file list.

## What to expect, measured

~78% work on the first attempt, ~93% within three, roughly five minutes each. About **one run in
three produces a correct patch with no report at all** — that is normal, not a failure. Judge the
tree.

## The procedure

### 1. Understand the request before specifying it

Ask about anything that would change the code, and stop asking once the answer would not. Boundary
and zero cases matter most: "what happens with no rows?" has caught more defects here than any
other question. Read the files you intend to name.

### 2. Make sure the project is wired up

```bash
handoff init
```

Idempotent, and safe on a project that is already set up. It creates the plans directory, copies a
config template if there is none, and adds gitignore entries — skipping any path the project
already tracks, because a project can legitimately keep plans under `.claude` and ignoring it there
would quietly stop new plans being added.

If `handoff` is not found, the agent-handoff checkout's `bin/` is not on PATH.

### 3. Write the plan

Plans live where `.handoff/config.sh` says (`HANDOFF_PLANS_DIR`), commonly `.handoff/plans/<slug>.md`
or `.claude/plans/<slug>.md`. Copy the shape from `templates/plan.md` in the agent-handoff
checkout.

Four rules. The first is enforced; the rest decide whether the verdict is worth anything:

1. **One acceptance criterion, exactly one executable command, same order.** The harness refuses a
   plan whose counts disagree — a plan with six criteria and two commands caps every run at 2/6.
2. **Dictate the signatures.** Give exact method names, parameters and return types.
3. **Cover the boundary and the zero case**, each as its own criterion.
4. **Name every file in `## Files to touch`**, and assert the count in a command:
   `test "$(git status --porcelain -- . ':(exclude).handoff' | wc -l)" -eq N`

Write commands that a do-nothing tree would fail. `php -l` on an unmodified file passes and
measures nothing; make the criterion assert behaviour instead.

### 4. Check it before running

```bash
handoff check <slug>
```

Fix everything it rejects. Take its advisories seriously — they are the difference between a plan
that runs and a plan whose verdict means something. Acceptance is not quality.

### 5. Run it

```bash
HANDOFF_PROVIDER=local handoff do <slug>
```

Five to twenty minutes. It implements, then verifies, and its **exit status is the harness's
verdict** — 0 means the gates accepted the tree even if the model's report was missing.

### 6. Report what actually happened

Read `.handoff/runs/<slug>/evidence/evidence.md` and `handoff diff <slug>`. Then tell the user:

- the verdict and which gates failed, if any
- what actually changed, from the diff
- any **advisory** findings — they do not reject but often matter
- anything under **"Not checked"** — absence of a failure there is not evidence of correctness

**Never repeat the model's report as if it were fact.** It is untrusted metadata: reports here have
claimed success over trees that were never touched. If the gates accept and the report is missing,
say the patch is good and the report is missing.

The implementer never commits. Leave that to the user.

### 7. When the gates reject

Read the failing command's output in the evidence bundle first. Usual causes, in order: the plan
was ambiguous, an acceptance command was wrong, or the model got it wrong. Fix the plan and re-run
rather than patching the code by hand — if the plan was wrong, the next run repeats the mistake.

## Setup, if it is not working

```bash
tools/setup-local-implementer     # from the agent-handoff checkout
```

It probes the stack with a real tool call and refuses rather than half-succeeding. If `handoff` is
not found, the checkout's `bin/` is not on PATH.

Full guide: `docs/START-HERE.md` in the agent-handoff checkout.
