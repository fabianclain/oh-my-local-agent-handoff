# agent-handoff

One coding agent writes the plan and verifies the result. Another writes the code.

It is a few hundred lines of bash. The value is not the code — it is the protocol, and the
failure modes it exists to catch.

> **Status: early.** Extracted from ~30 real rounds on a production Laravel codebase. One
> provider adapter (Codex) works today; the provider seam exists so others can be added without
> touching the driver.

## Why

Handing a task to a coding agent and reading the diff works until it doesn't. The failures that
matter are quiet: a parser that passes twelve tests against fixtures someone invented, a health
check that always returns success, an aggregate that silently double-counts.

Over ~30 rounds building a real feature this way, **every defect that shipped originated in a
specification, not an implementation.** The implementer built what it was told, faithfully, every
time. The tests passed because they were written from the same specification that was wrong.

That single observation drives every design decision here.

## What it does

```
handoff do <slug>       implement .handoff/plans/<slug>.md
handoff resume <slug>   feed back review comments, same session
handoff diff <slug>     exactly what changed during the run
```

The plan is a **contract**: goal, context, files to touch, states to handle, fixture provenance,
objectively checkable acceptance criteria, and a binding *out of scope* list. The implementer
returns **schema-enforced JSON**, not prose:

```jsonc
{ "status": "complete|partial|blocked",
  "files_changed": [...], "tests_run": [{ "command": "...", "passed": true, "detail": "..." }],
  "deviations": [...], "blockers": [...], "follow_ups": [...] }
```

The implementer never commits. The reviewer reads the diff, re-runs the tests, and owns the
commit.

## Four mechanisms, each from a specific failure

**Tree-snapshot diffing.** Before/after `git write-tree` using a throwaway index, so you get
exactly what the implementer touched. Plain `git diff` is useless in a repo that already has
uncommitted work — and most real repos do.

**Session-pinned resume.** Review rounds continue the same conversation, so feedback is "fix line
42" rather than re-explaining the design. Pinned to a recorded session id, not "most recent".

**A read-only advisory lane.** `consult think` and `consult debug` run sandboxed read-only. An
implementer that *can* edit files *will* edit files; separating review at the sandbox level is
the only reliable way to get a review that cannot quietly fix what it finds.

**`deviations` in the schema.** The highest-value field. Its best catch: the implementer was told
to stop using an endpoint, correctly realised this left the connection test unable to fail,
implemented it as instructed anyway, and *reported the problem*. A health check that always
returns success is invisible in a diff.

## What the tests will not catch

This is the part worth reading twice.

- **Tests inherit the specification's blind spots.** A parser passed twelve tests while unable to
  parse a single real page, because the class it selected on had been removed months earlier.
  More tests would have deepened the illusion.
- **Fixtures must be captured, not imagined.** If a fixture mirrors an external system, it must
  come from that system. This is the single highest-value rule here.
- **Never trust the self-report.** Re-run every claimed test. Three reports were wrong: two
  hijacked by an unrelated harness hook, one falsely claiming `blocked` while the work was
  complete and correct.
- **Verify against real data, not just tests.** Every genuinely valuable check was a live request
  or a query against the real database.
- **The zero case is where defects live.** "What happens with no rows?" caught more than any
  other single question. The plan template makes it mandatory.

What actually found things: an adversarial read of plan-against-code, a browser console, and a
person clicking a link.

## Setup

```bash
git clone https://github.com/fabianclain/agent-handoff
export PATH="$PWD/agent-handoff/bin:$PATH"

cd your-project
mkdir -p .handoff/plans
cp path/to/agent-handoff/templates/config.sh .handoff/config.sh   # edit it
echo ".handoff/runs/" >> .gitignore
```

`.handoff/config.sh` carries your project's conventions into every prompt. Without it the
implementer cannot know how your project builds, tests, or formats — the largest avoidable source
of review churn.

Copy `commands/*.md` into `.claude/commands/` if you drive this from Claude Code.

## Providers

A provider is `(binary, env block, capabilities)`, not just a binary. Adapters declare what they
support natively and the driver **degrades loudly** — a prompt-and-validate JSON round is not the
same guarantee as a schema-enforced one, and the difference is printed rather than hidden.

| | structured output | session resume | sandbox |
| --- | --- | --- | --- |
| `codex` | native | native | native |

Adding one means implementing five functions in `providers/<name>.sh`. Nothing above the adapter
is provider-specific.

## Licence

Apache 2.0 — see [LICENSE](LICENSE).
