# <Title>

> Plan contract for a Codex implementation run. Claude writes this file; Codex reads it as
> the single source of truth. Anything not written here is out of scope.

## Goal

<One paragraph: what the user gets when this is done. Outcome, not implementation.>

## Context

<What Codex needs to know that it cannot cheaply discover: which domain this lives in, which
existing pattern to copy, the relevant models/tables, why the obvious approach is wrong.
Cite files as `path/to/file.php:42`.>

## Files to touch

| Path | Action | Notes |
| --- | --- | --- |
| `app/Domains/X/...` | create | ... |
| `routes/x.php` | modify | ... |

## Steps

1. ...
2. ...
3. ...

## States to handle

**Fill this in. Every defect this pipeline has shipped came from a state the plan did not
mention** — unmentioned means unbuilt, untested, and green. Say explicitly what happens for
each that applies:

- **Zero** — no rows, no results, nothing captured yet. This is the *normal starting state* for
  anything a user creates before data arrives. Does it render an empty state, or 404?
- **One** — anything that compares or diffs consecutive items has no pair when there is one.
- **Maximum** — the documented limit, and one past it. Reject, truncate, or drop-oldest?
- **Absent optional fields** — null snippet, missing title, unparseable URL.
- **Failed upstream** — a parse error, a failed fetch, a stub not implemented. Recorded and
  skipped, or does it abort the batch?
- **Unauthenticated context** — console commands and API routes where a global scope is
  inactive. Where does ownership come from?

## Fixtures

If this work needs test fixtures that mirror an external system (HTML, API responses, file
formats), state where they come from. **Captured from the real thing, or invented?**

Invented fixtures produce tests that pass while the code cannot work — a parser here once
passed twelve tests against hand-authored HTML while being unable to parse a single real page.
If no real sample is available, say so and mark the tests as unproven rather than implying
coverage.

## Acceptance criteria

Each item must be objectively checkable. Codex reports `complete` only when every box is true.

Include at least one criterion per non-trivial state listed above — especially the zero case.

- [ ] ...
- [ ] ...
- [ ] `<your test command>` passes
- [ ] `<your formatter>` leaves no changes

## Verification commands

```bash
<your test command>
<your formatter>
```

## Out of scope

Explicitly do NOT do these, even if they look obviously needed. Report them as `follow_ups`.

- ...
- ...
