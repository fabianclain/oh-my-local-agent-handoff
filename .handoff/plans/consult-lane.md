# bin/consult — the read-only advisory lane

## Goal

`bin/consult` is the counterpart to `bin/handoff`. Where `handoff` writes code, `consult` never
does: it runs the provider sandboxed **read-only** and returns a structured opinion.

Two lanes:

- `consult think <slug>` — adversarially attack a design position
- `consult debug <slug>` — generate competing hypotheses for a bug

Both exist because an implementer that can also edit files will edit files. Separating the
advisory lane at the sandbox level is the only reliable way to get a review that cannot
"helpfully" fix what it finds.

## Context

Read `bin/handoff` first and follow its structure exactly — guard clauses, `set -euo pipefail`,
provider sourcing, run directories, comments that name the failure a mechanism prevents.

Read `providers/codex.sh` for the adapter interface. Note that `provider_run` and
`provider_resume` take a sandbox from `HANDOFF_SANDBOX`; consult must force `read-only`
regardless of what the caller set, and must not silently inherit a writable sandbox.

Schemas already exist: `schemas/think.schema.json`, `schemas/debug.schema.json`. Use them as-is;
do not modify them.

The slash-command protocols these lanes implement are in `commands/handoff-think.md` and
`commands/handoff-debug.md` — read them so the file layout matches what they instruct users to
write.

### Inputs and outputs

```
.handoff/think/<slug>/position.md    the design being attacked   (user writes)
.handoff/think/<slug>/verdict.json   structured objections       (consult writes)
.handoff/debug/<slug>/symptom.md     observations only           (user writes)
.handoff/debug/<slug>/hypotheses.json                            (consult writes)
<lane>/<slug>/rebuttal.md            for --again                 (user writes)
<lane>/<slug>/stdout.log, session-id
```

`--again` continues the same session with the rebuttal, so the reviewer reconsiders its own
argument rather than meeting a summary of it cold.

### A trap that cost four thousand log lines

The first version of this lane deadlocked. An unrelated harness hook ran on session end, tried
to write state, was denied by the read-only sandbox, blocked the shutdown, and the provider
retried forever. The codex adapter already passes `--disable hooks` for this reason; consult
must not undo it.

## Requirements

- Force read-only. `HANDOFF_SANDBOX` from the environment must be **ignored**, not merged.
- After the run, assert the working tree is unchanged by comparing before/after tree snapshots
  (same throwaway-index technique as `bin/handoff`). If anything changed, print a loud warning
  listing the files — a read-only lane that quietly wrote something is worse than no assertion.
- Only overwrite `session-id` on a successful parse; a failed parse must not wipe a good id.
- Same capability-degradation notice as `bin/handoff`.
- No new dependencies. Bash only, no jq.

## States to handle

- unknown lane (not think/debug) → usage to stderr, exit 64
- missing input file → name the exact path expected, exit non-zero
- `--again` with no recorded session id → explain that the first run must happen, exit non-zero
- `--again` with no rebuttal file → name the path, exit non-zero
- provider missing from PATH → the adapter's preflight already covers this; do not duplicate it
- the working tree changed during a read-only run → warn loudly, list files, still exit with the
  provider's status

## Fixtures

No test framework exists in this repo yet and this round must not add one. Verification is
manual and mechanical:

- `bash -n bin/consult`
- every guard above triggered by hand, with its message and exit code checked

Report the exact commands run and their output.

## Files to touch

| Path | Action |
| --- | --- |
| `bin/consult` | create, chmod +x |

Nothing else. Do not modify `bin/handoff`, the providers, or the schemas.

## Acceptance criteria

- [ ] `bash -n bin/consult` passes and the file is executable
- [ ] `consult` with no arguments prints usage to stderr and exits 64
- [ ] an unknown lane exits 64 with a message naming the valid lanes
- [ ] a missing `position.md` / `symptom.md` names the exact expected path and exits non-zero
- [ ] `--again` without a session id, and without a rebuttal, each fail with distinct messages
- [ ] the sandbox is forced to read-only even when `HANDOFF_SANDBOX=workspace-write` is exported
      — demonstrate this, do not merely assert it
- [ ] a tree-change warning path exists and lists files
- [ ] no new dependencies; no reference to any specific CLI outside `providers/`

## Verification

```bash
bash -n bin/consult
./bin/consult                      # usage, exit 64
./bin/consult nope x               # unknown lane, exit 64
./bin/consult think missing        # names the missing position.md
HANDOFF_SANDBOX=workspace-write ./bin/consult think missing   # still read-only
```

## Out of scope

- Modifying `bin/handoff`, `providers/*`, `schemas/*`, or `commands/*`.
- Adding a test framework, a linter, or any dependency.
- Adding a second provider. Committing.
