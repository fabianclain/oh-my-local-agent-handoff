# providers/opencode.sh — the degraded adapter

## Goal

An adapter for the `opencode` CLI. It matters less as a provider than as a test of the
abstraction: opencode has **no schema-enforcement flag and no session resume**, so if the driver
survives it without special-casing, the provider seam is real. If it does not, the seam is
shaped around capabilities that happen to be universal so far.

## Context

Read `bin/handoff`, then `providers/codex.sh` and `providers/claude.sh` — they are the two
reference adapters and the only interface documentation. Follow their structure and commenting
style: comments explain *why*, naming the failure a mechanism prevents.

Inspect the installed CLI before writing anything: `opencode --help`, `opencode run --help`.
**Do not assume flags.** A previous round in this project specified a test command that silently
discovered no tests at all, because the invocation was assumed rather than checked.

## Requirements

Implement the five interface functions: `provider_name`, `provider_capabilities`,
`provider_preflight`, `provider_run`, `provider_resume`, `provider_parse_session_id`.

Declare capabilities **honestly**. Expected, but verify against the actual CLI:

```
structured_output=prompt-validate
session_resume=replay
sandbox=none
```

- **prompt-validate** — no schema flag, so append the schema to the prompt, then validate the
  reply against it. On invalid JSON, retry **once** with the parse error included; if the retry
  also fails, write what came back and exit non-zero. Never silently accept unvalidated output:
  the whole point of the schema is that the reviewer can trust the shape.
- **replay** — no session resume, so `provider_resume` re-sends the plan, the current diff, and
  the feedback as one prompt. Say in a comment that this loses the implementer's reasoning
  context and costs more tokens, so a reviewer reading the log knows why a resumed round behaves
  differently.
- **sandbox=none** — the driver already prints non-native capabilities. Do not paper over it.

Validation must use `python3` (already required by `providers/claude.sh`). Do not add `jq` or
any other dependency.

## States to handle

- `opencode` not on PATH → preflight fails with an install pointer
- the model returns prose instead of JSON → one retry, then a non-zero exit and the raw reply
  preserved for inspection
- the model returns JSON that parses but violates the schema → same path as unparseable
- `provider_resume` called with no prior run → fail clearly rather than replaying an empty diff

## Fixtures

No test framework exists in this repo and this round must not add one. Verify by hand and report
the exact commands and their output.

## Files to touch

| Path | Action |
| --- | --- |
| `providers/opencode.sh` | create, chmod +x |
| `README.md` | modify — one row in the provider table only |

Do not modify `bin/handoff`, `bin/consult`, the other providers, or the schemas. If the driver
genuinely cannot accommodate this provider without a change, **stop and report that under
`blockers`** — that finding is more valuable than a working adapter.

## Acceptance criteria

- [ ] `bash -n providers/opencode.sh` passes; file is executable
- [ ] All six interface functions exist and are callable
- [ ] Capabilities are declared honestly and match the real CLI, verified against `--help`
- [ ] Preflight fails clearly when `opencode` is absent
- [ ] Invalid JSON triggers exactly one retry, then exits non-zero preserving the raw reply
- [ ] No new dependencies beyond `python3`
- [ ] `bin/handoff` is unmodified — confirm with `git diff --stat`
- [ ] README provider table gains one row and nothing else changes

## Verification

```bash
bash -n providers/opencode.sh
opencode --help | head -20
git diff --stat bin/
```

## Out of scope

- Modifying the driver, other providers, or schemas. Adding dependencies or a test framework.
- Making opencode a *good* provider — the point is proving the seam, not optimising it.
- Committing.
