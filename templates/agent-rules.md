# Operational rules for the implementer

This is layer 2 of three, and the layering is deliberate:

1. **Benchmark notes** (`docs/local-models.md`, `bench/COMPARISON.md`) — for the human. Never
   shown to the model. Telling a model under test that it is expected to delete adjacent
   declarations, or that its family reports success it did not achieve, contaminates the
   measurement.
2. **This file** — a short, task-independent operational prompt, identical for every plan.
3. **The plan** — the task, and only the task.

Keep this file short. The single most effective change measured in this project was a section
about *output* rather than about the task: it took one model from 2/5 to 5/5 on unchanged task
text, and another from 0/5 to 5/5. Adding more explanation of the task did not help — the failing
plan was already one 30-line file with five explicit criteria and exact input-to-output examples.
There was no ambiguity left to remove. The model understood the task; it could not stop narrating.

Everything below earns its place by having prevented a specific observed failure. Nothing is here
as general good advice.

---

## EDITING RULES

- Existing files may only be modified through minimal patches.
- Never rewrite an existing file from scratch.
- Read every existing file before modifying it.
- Make the smallest possible diff that satisfies the acceptance criteria.
- Do not modify files outside the declared task scope.
- Do not refactor, rename, reformat, or clean up unrelated code.
- After each edit, read the changed section back and verify it.
- If the required target cannot be located exactly, stop and report a blocker instead of guessing.

## COMPLETION RULES

- Your completion report is not proof of success.
- Never claim a command, test, migration, or check passed unless you executed it and observed
  success.
- Report the exact checks actually performed.
- If any requested verification could not be performed, report it explicitly as unverified.
- The plan already tells you how to verify. Run those commands. Do not write your own test file,
  verification script or scratch harness — not in the repository, not in a temp directory.
- If you need to check something the plan does not cover, run it inline as a one-off command.
  Nothing you create for your own checking may survive the run.

## OUTPUT RULES

- The files you write are deliverables, not scratchpads.
- One implementation only. Never leave an earlier attempt beside a later one.
- No commentary about your own process in the code. No alternatives kept "in case".
- Write real newlines, not the two characters `\` and `n`.

---

## Why each rule is here

Stated for the maintainer, not for the model. The model sees only the rules above.

| Rule | The failure it prevents |
| --- | --- |
| Never write your own verification scripts | Measured across the `wide` rounds: 13 invented files — `verify.sh`, `test_rate.php`, `testsuite.php`, `verify_plan.sh` and more. One run produced **seven** of them and never cleaned them up, failing its file-count criterion on all three attempts at 1404s and 68,082 generated tokens. It happens at every reasoning level, so it is not a side effect of thinking too much. "The files you write are deliverables, not scratchpads" was already in these rules and did not land; naming the specific behaviour is the fix. |
| Never rewrite from scratch | A 421-line service came back as an 11-line fragment. The code was correct; its destination was not. It happened to be a parse error, so a syntax gate caught it — luck. A fragment carrying its own `class` declaration would have been valid PHP and would have deleted 410 working lines with nothing complaining. |
| Read back after editing | A model patched correctly and deleted the declaration adjacent to its insertion point, on every run. Functional tests passed both times — PHP falls back to a dynamic property, so the class still worked and a suite would be green. |
| Smallest possible diff | Scope creep is invisible in a passing test run and expensive in review, which is where the hosted-model tokens actually go. |
| Report a blocker rather than guess | Given a long plan slug, a model looked for an underscored variant, failed, and reported the plan missing rather than listing the directory. |
| Completion report is not proof | Three runs reported `status: complete` with invented summaries — "added discount calculation to order processing and updated API endpoints; all tests pass" — over a tree they had not touched. There was no order processing and there were no API endpoints in the task. |
| Real newlines | Files written as one line containing the characters `\` and `n`. It reached filenames too: a real file named `OpportunityReport.php` with a trailing newline, invisible to `ls`, evading a `*.php` check. |
| One implementation | The first artifact produced here contained three successive implementations in one file, each commenting on the last: *"Correction: the above is wrong"*, *"Actually, the rule is..."*. |

**None of these rules is enforcement.** A plan stated the `SUM(clicks)/SUM(impressions)` rule
explicitly and the wrong version shipped anyway. Stating a constraint is not the same as honouring
it: the harness gates in `bench/run` and `.handoff/bin/gemma-round` are what decide whether a
round stands.
