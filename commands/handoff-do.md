---
description: Hand a plan to Codex to implement, then verify the result
argument-hint: <plan-slug> [or: a task description to plan first]
allowed-tools: Bash(handoff:*), Bash(git diff:*), Bash(git status:*), Bash(<your test command>:*), Bash(<your formatter>:*), Read, Write, Edit, Grep, Glob
---

You are the **planner and verifier**. Codex is the implementer. You do not write the
implementation yourself.

Argument: `$ARGUMENTS`

## 1. Resolve the plan

If `.handoff/plans/$ARGUMENTS.md` exists, use it.

Otherwise treat the argument as a task description and write the plan first:

- Read `.handoff/plans/TEMPLATE.md` for the required shape.
- Investigate the codebase enough to fill in **Context** and **Files to touch** concretely —
  real paths, real class names, the existing pattern Codex should copy. A vague plan produces
  a vague implementation; this step is where the quality comes from.
- Every acceptance criterion must be objectively checkable.
- Fill **Out of scope** honestly. This is the main lever against Codex over-reaching.
- Save to `.handoff/plans/<slug>.md` with a short kebab-case slug.
- Show the user the plan and get agreement before handing off.

## 2. Hand off

```bash
handoff do <slug>
```

Run it with `run_in_background: true` — implementation runs take minutes. Tell the user it
started, then poll for completion rather than blocking.

## 3. Verify — do not trust the report

Read `.handoff/runs/<slug>/result.json` for Codex's structured self-report, then
independently check it:

- `handoff diff <slug>` — the actual file list. Compare it against
  `files_changed` in the report and against the plan's **Files to touch**. Anything touched
  that the plan did not authorise is a finding, especially anything under **Out of scope**.
- `git diff` the changed paths and read the code properly. Codex's `summary` is a claim, not
  evidence.
- Re-run the plan's verification commands yourself. A `passed: true` you did not observe
  does not count.
- `<your formatter>` — must leave nothing to change.
- Confirm nothing was committed: the changes should still be in the working tree.

## 4. Iterate or finish

If verification fails, or the report has non-empty `blockers` or unacceptable `deviations`:

1. Write specific, actionable feedback to `.handoff/runs/<slug>/feedback.md` — quote the
   failing test output, name the file and line, state what the correct behaviour is.
2. `handoff resume <slug>` — this continues Codex's existing session, so it keeps
   full context of what it already built.
3. Verify again. After three failed rounds, stop and bring the problem to the user rather than
   looping.

When it passes, report to the user: what landed, what the tests said, any `deviations` and
`follow_ups` worth their attention. Leave the commit to them unless they ask.
