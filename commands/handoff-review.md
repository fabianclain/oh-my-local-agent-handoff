---
description: Adversarial gap-hunt over a finished feature — unhandled states, fake fixtures, tests that can't fail
argument-hint: <feature or plan slug>
allowed-tools: Bash(consult:*), Bash(git diff:*), Bash(git log:*), Bash(<your test command>:*), Read, Write, Grep, Glob
---

Run after a feature is implemented and verified, **before** you consider it done. This is not a
design debate and not a style review — it hunts for what a user will hit that no test covers.

Target: `$ARGUMENTS`

## Why this exists

Tests written from a plan inherit the plan's blind spots. When a specification omits a state,
that state is not built, not tested, and nothing looks wrong — the suite is green and the
feature is broken. Real examples from this repo:

- A parser was tested against **invented** HTML fixtures. Twelve tests passed while it could not
  parse a single real page, because the class it selected on no longer existed.
- A keyword page 404'd for every tracked keyword with no captures — the normal starting state.
  The plan never mentioned an empty state, so it was never written and never tested.

Neither was an implementation error. Both were faithful builds of incomplete specs. This
command exists to catch that class specifically.

## 1. Write the brief

`.handoff/think/<slug>-review/position.md`. Include:

- **What exists** — the real files, models, routes, commands. Concrete paths, not prose.
- **The claim under attack** — normally "this feature is usable end to end and its tests deserve
  the confidence placed in them".
- **Where you already know you are weak** — be specific and honest. A brief that oversells the
  work gets a review that agrees with it.
- **An explicit instruction not to trust the test suite as evidence.**

## 2. Send it

```bash
consult think <slug>-review
```

Read-only sandbox; it cannot modify anything. Run with `run_in_background: true`.

## 3. What to demand it look for

State these in the brief, roughly in this order — they are ranked by how often they have
actually bitten:

1. **Unhandled states** — zero rows, exactly one, the documented maximum, absent optional
   fields, a record referenced before it has data, a parse or fetch that failed. Which break a
   page, 404, or silently produce a misleading number?
2. **Invented fixtures** — any test asserting against hand-authored data that is supposed to
   mirror an external system. Demand the file be named. This is the highest-value check here.
3. **Aggregation correctness** — if there is a shared de-duplication or scoping rule, does
   *every* consumer use it, or does one path count raw rows?
4. **Tenant isolation** — especially where a global scope is inactive: console commands, queued
   jobs, and unauthenticated API routes.
5. **Tests that cannot fail** — assertions inside callbacks that never run, tests asserting on
   seeded data without exercising the code path, tests with no meaningful assertion.
6. **N+1 and unbounded queries** on anything that grows with usage.

## 4. Triage the verdict

`verdict.json` gives `objections[]` with `severity` and `confidence`, plus
`missed_considerations` and `what_it_gets_right`.

Verify every objection in the code before acting — cite the file and line that confirms or
refutes it. A confidently-worded objection about code that does not work that way is the most
expensive output here, and it happens.

Sort into: **real and worth fixing now**, **real but deferred** (say so explicitly rather than
silently dropping), and **wrong** (state the evidence).

Weight by `confidence` as well as `severity` — a low-confidence fatal is usually worth checking;
a high-confidence minor is usually worth just fixing.

## 5. Act

Turn the confirmed findings into a feedback round via `handoff resume <slug>`, or a
fresh plan if the gap is large. Report to the user: what was found, what you are fixing, what
you are deferring and why.

Do not fix things from inside this command without telling the user what changed.
