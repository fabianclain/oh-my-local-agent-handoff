---
description: Form competing bug hypotheses with Codex, then let an experiment decide
argument-hint: <the bug, error, or misbehaviour>
allowed-tools: Bash(consult:*), Bash(<your test command>:*), Bash(git log:*), Bash(git diff:*), Read, Write, Edit, Grep, Glob
---

Diagnose a bug by having two models theorise independently, then settling it with evidence
rather than argument. The failure mode this exists to prevent is committing to the first
plausible explanation — usually the most *available* one, not the most likely.

Symptom: `$ARGUMENTS`

## 1. Write the symptom down, then theorise separately

Write `.handoff/debug/<slug>/symptom.md` with only what is **observed**, not what you
suspect:

- What happens, what should happen, and the exact error text or failing assertion.
- Reproduction steps, and whether it is deterministic or intermittent.
- When it started, and what changed around then (`git log` is usually the fastest lead).
- What you have already ruled out, and how.

Keep your own hypotheses out of this file. Seeding Codex with your theory collapses the two
independent investigations into one, which is the entire thing this command is trying to
avoid.

Then, in parallel:

```bash
consult debug <slug>
```

Run it with `run_in_background: true`, and while it works, form **your own** hypotheses from
the code. Write them down before reading its answer, so you can tell afterwards which model
was right rather than reconstructing a story where you agreed all along.

## 2. Compare

`.handoff/debug/<slug>/hypotheses.json` gives `hypotheses[]` (each with `mechanism`,
`evidence_for`, `evidence_against`, `confidence`, `discriminating_test`), `most_likely`,
`cheapest_decisive_test`, `ruled_out`, `missing_evidence`.

Three cases:

- **You agree** — good, but agreement between two models is not evidence. Both can be wrong in
  the same way, especially on a bug that looks like a familiar pattern. Still run the test.
- **You disagree** — this is the productive case. Find the check whose outcome separates the
  two theories, and run that.
- **It found something you missed** — check `ruled_out` too. Something you were about to spend
  an hour on may already be eliminated, with a reason.

Verify any `mechanism` that cites specific files by reading them. A confidently-stated causal
chain through code that does not work that way is the most dangerous output here.

## 3. Let the experiment decide

Run `cheapest_decisive_test`, or a better one if you have it. Prefer a check that halves the
hypothesis space over one that confirms your favourite — a test that can only ever agree with
you tells you nothing.

Report the actual result, including when it refutes both theories. That outcome is
informative and common; treat it as progress, not failure.

If everything is eliminated, write what the experiments ruled out to
`.handoff/debug/<slug>/rebuttal.md` and run
`consult debug <slug> --again` for a second round informed by the new
evidence.

## 4. Report

State the root cause, the evidence that establishes it (not the reasoning that suggested it),
and the fix you propose. Note which model got there and where the other went wrong — over time
that tells you which lane to trust for which kind of bug.

Do not fix it from inside this command unless the user asks. If the fix is more than a couple
of lines, write it up as a plan and hand it to `/codex-do`.
