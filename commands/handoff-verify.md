---
description: Verify a finished Codex run without re-running the implementation
argument-hint: <plan-slug>
allowed-tools: Bash(handoff:*), Bash(git diff:*), Bash(git status:*), Bash(<your test command>:*), Bash(<your formatter>:*), Read, Write, Grep, Glob
---

Verify Codex's work on `$ARGUMENTS` as an adversarial reviewer. Assume the self-report is
optimistic until the evidence says otherwise.

## Inputs

- Plan (the contract): `.handoff/plans/$ARGUMENTS.md`
- Codex's self-report: `.handoff/runs/$ARGUMENTS/result.json`
- Full transcript, if you need to see how it got there: `.handoff/runs/$ARGUMENTS/stdout.log`
- Actual file changes: `handoff diff $ARGUMENTS`

## Checks

**Scope.** Diff the real changed-file list against the plan's *Files to touch*. Flag every
file changed that the plan did not authorise, and every file the plan required that is
untouched. Treat anything under *Out of scope* as a hard failure.

**Honesty.** For each entry in `tests_run`, execute the command yourself and compare. A
mismatch between claimed and observed results is the most serious finding you can make —
report it prominently.

**Acceptance criteria.** Walk the plan's checklist one item at a time. For each, state the
concrete evidence that it holds. "Looks implemented" is not evidence; a passing assertion or
a read of the actual code path is.

**Code quality.** Read the diff as a reviewer, not a linter. Look for: logic that is wrong on
edge cases, missing authorisation on new routes or actions, N+1 queries, missing
tenant scoping on new owner-scoped models, tests that assert nothing meaningful, error
paths that swallow failures.

**Hygiene.** `<your formatter>` clean; nothing committed; no stray debug output,
scratch files, or commented-out code left behind.

## Output

A verdict — **pass**, **pass with notes**, or **fail** — followed by findings ordered by
severity. Each finding: file and line, what is wrong, what should happen instead.

If the verdict is **fail**, also write the findings to
`.handoff/runs/$ARGUMENTS/feedback.md` in a form Codex can act on directly, and tell the
user they can send it back with `handoff resume $ARGUMENTS`.
