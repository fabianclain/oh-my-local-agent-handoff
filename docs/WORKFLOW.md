# How this is actually used

The day-to-day loop, as opposed to the design. Three steps, two models, and one rule that makes the
whole thing worth doing.

## The rule

**Whoever writes the plan does not decide whether the result is acceptable.**

Everything below follows from that. It is not ceremony: a model reviewing its own work will accept
its own misreading of the task, every time, and that is the failure this repository exists to
catch. The plan is written by one model, the code by another, and the verdict comes from commands
run against the files on disk.

## Step 1 — plan with the hosted model, and ask for *only* the plan

Describe what you want to Claude (or Codex) and say plainly: **write the plan, do not implement
it.** That instruction matters more than it looks. Left to itself a capable model will start
editing, and then it is both author and reviewer of its own work, which is the one arrangement this
is built to avoid.

What comes back is a file under `.handoff/plans/<slug>.md` with, at minimum:

- **Files to touch** — a table. Anything not in it is out of scope, enforced.
- **Acceptance criteria** — one line each, in prose.
- **Verification** — one shell command per criterion, exit 0 for pass.

The criteria are the deliverable. Prose in the plan body is advice; only the commands are binding.
A real example of why: a plan said, in bold, *"do not comment out the removed blocks, delete
them."* The model commented the import out anyway — the line above it was already a commented
import, so local convention beat the instruction. `test "$(grep -c 'SearchConsole' …)" -eq 0`
caught what the prose did not.

Check it before spending model time:

```bash
handoff check <slug>
```

It refuses plans whose criteria and commands disagree in count, which is the cheapest possible way
to find out that a criterion is unverifiable.

**Decompose.** A plan with more than ~10 criteria or ~6 files is better as two. When a round fails
you want the failure localised to something small enough to re-run in under a minute, not to a
monolith that has to be redone whole.

## Step 2 — hand it to the local model

```bash
/local-implementer          # from Claude Code, or:
handoff do <slug>           # directly
```

The local model implements; the harness verifies and prints the verdict. Nothing is committed —
you own the commit, always.

`handoff do` exits non-zero when the gates reject the round, so it composes:

```bash
handoff do <slug> >/tmp/run.log 2>&1; echo "verdict exit=$?"
```

**Redirect, do not pipe.** `handoff do x | tail` returns *tail's* exit status, not the verdict.

## Step 3 — read the gaps, not the report

The model's own account of what it did is the least reliable artifact available and is never
trusted. Read the verdict, then the diff.

| What you see | What it means | What to do |
| --- | --- | --- |
| `accepted` | every criterion passed, scope respected | read the diff, then commit |
| `patch-ok-no-report` | the tree is good; the report was lost in transport | treat as accepted, read the diff |
| `patch-damaged` | a gate rejected the tree | read *which* gate before assuming the model was wrong |
| `infra-failed`, 0 writes, fast | the adapter broke; the model never really ran | **re-run once. Do not re-specify a good plan** |
| `no-op` | nothing changed | the plan is probably unclear, not the model |

**Things the gates cannot catch, which are yours to check by hand:**

- **Whitespace scarring.** A deletion leaves the blank line around it; an edit inside a nested block
  can come back re-indented. No acceptance command sees either. With a formatter this is invisible;
  without one it lands in the commit. Budget for it.
- **Whether the change was a good idea.** The gates prove the plan was implemented. They say
  nothing about whether the plan was right.

Then write the gaps down — what the round did not cover, what you fixed by hand, what the criteria
missed. That list is the input to the next plan, and it is where this gets better over time.

## What this costs

Honest accounting from real use, so the tradeoff is a decision rather than a surprise:

- Specification takes longer than a small change. A five-minute edit is not worth a plan.
- The value on small tasks is **not speed** — it is being forced to say exactly what you mean,
  which is what catches specification bugs before code exists.
- The ratio inverts on mechanical changes across many files, where the tedium is real and the
  thinking is not.

## Before a run, once

```bash
tools/install-local                              # once per machine
tools/llamacpp-serve start gpt-oss-20b 98304     # does not survive a reboot
HANDOFF_EXPECT_CTX=98304 tools/doctor            # assert the stack, do not assume it
```

That last one is not decoration. A server left running at 32768 while every document said 98304
cost a benchmark night its first hour, and nothing objected, because `doctor` only complained
*below* 32768.

**Start from a clean tree.** A verdict over a dirty one is a verdict about more than this round.
Files already untracked before the run are no longer charged to the model, but the diff you read at
the end is still clearer without them.
