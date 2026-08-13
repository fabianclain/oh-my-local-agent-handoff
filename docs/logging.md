# What gets recorded, and where

Everything this harness concludes is reconstructed from files on disk. Nothing is taken from the
implementer's own account of what it did — three runs in this project reported `status: complete`
over trees they had never touched, one with invented file paths. So the rule that shapes all of it:

> Every claim is produced by running a command and recording what it returned.

The implementer's report is preserved, and it is preserved as *evidence of what was claimed*, never
as evidence of what happened.

There are three layers. They answer different questions and fail in different ways.

---

## 1. Per-run artifacts — `bench/results/<plan>/<arm>/<repetition>/`

Written by `bench/run`, and copied out of the throwaway worktree **before it is deleted**. That
ordering is the whole reason anything survives: the worktree is disposable by construction.

### What the model did

| File | Contents |
| --- | --- |
| `provider.log` | the agent's complete event stream — every tool call, its arguments, its result, every reasoning block. One JSON object per line |
| `prompt-attempt-N.md` | exactly what the model was sent on attempt N, developer instructions included |
| `handoff-report.json` | the model's own schema-validated report |
| `deviations.txt`, `note.txt` | what it said it did differently, and why a run ended early |

### What actually changed

| File | Contents |
| --- | --- |
| `tree-before`, `tree-after` | `git write-tree` hashes taken through a throwaway index, so this works in a repo that already has uncommitted work — and most real repos do |
| `tree.diff` | exactly what the run changed, between those two trees |
| `tree-files.txt` | the files changed in the **final** tree |
| `touched-files.txt` | the files touched across **every attempt** |

The last two are not the same question, and keeping both is deliberate. A file created on attempt 1
and deleted on attempt 2 leaves no trace in the final tree, but the model still wrote it. *"Can a
reviewer take this patch"* and *"did this model behave well"* have different answers, and one
column cannot carry both.

### What the gates said

| File | Contents |
| --- | --- |
| `verification-attempt-N.log` | every acceptance command, its output, its exit code |
| `verification.log` | the final attempt's, for convenience |
| `evidence/`, `evidence.log` | `verify-round`'s bundle: each gate, its command, its exit code, a digest — **and an explicit list of what it could not check** |
| `scope-violations.txt`, `litter.txt`, `rewrite-violations.txt` | files touched outside the plan, files invented, files regenerated rather than patched |
| `feedback-attempt-N.md` | what a repair attempt was told about the one before it |

The "not checked" list in the evidence bundle is load-bearing. `pint`, `phpstan` and `pest` run
only if present, and a gate that quietly runs fewer checks than you think converts absence of
evidence into apparent evidence of correctness.

### The scored summary

`metrics` is the one machine-readable file, `key=value` per line. Beyond the obvious counts:

| Key | Why it exists |
| --- | --- |
| `outcome` | the taxonomy: `accepted`, `patch-ok-no-report`, `patch-incomplete`, `patch-damaged`, `fabricated`, `no-op`, `protocol-failed` |
| `harness_commit`, `harness_dirty` | which harness produced this. A clone drifted from the working checkout once and 25 of 61 runs exercised an adapter bug that had already been fixed elsewhere |
| `harness_tree` | a `write-tree` hash of the harness itself. The commit is **not enough** — three arms once recorded the same commit with different uncommitted edits, and nothing could tell them apart |
| `truncated_requests`, `context_overflows` | a run that silently lost history is a configuration result, not a model result |
| `usage_unattributable` | set when the server log shrank mid-round, so tokens cannot honestly be assigned |

---

## 2. Server-side — `~/.cache/agent-handoff/llamacpp.log`

`llama-server`'s own output: parse failures, slot timings, tokens decoded per request.

**This is measurement substrate, not a convenience log.** Token accounting brackets each attempt by
*byte offset* into this file. A log that is missing, truncated mid-round or replaced makes usage
unattributable, and `bench/summary` says so rather than printing a plausible number.

Two failures worth knowing, both real:

- **It went to the journal.** Started as a systemd unit without an explicit destination, the
  server's output goes to journald and this file freezes at its last byte. `peg-audit`,
  `bench/summary` and `doctor` all keep reading it and all keep reporting stale numbers, without
  erroring. The unit must direct output here.
- **It was truncated per session.** Per-session isolation is right — a parse-failure rate pooled
  across every session since boot is a rate for nothing — but achieving it by truncation destroyed
  695 KB of real-use data. It now **rotates**: `llamacpp.log.<timestamp>`, ten kept.

---

## 3. Queue-level — `.overnight/<timestamp>/`

Written by `tools/overnight` for an unattended run.

| File | Contents |
| --- | --- |
| `overnight.log` | the narrative, one line per event, written incrementally so a `kill -9` still leaves a record |
| `<job>.log` | one per job, whatever that job printed |
| `state.tsv` | machine-readable: `name`, status, seconds, detail. **Appended**, so a resumed job has one line per attempt |
| `summary.md` | the morning report: one row per job, its last outcome, and an attempt count when it took more than one |

`state.tsv` is what `--resume` reads. Only jobs recorded `ok` are skipped; failed and interrupted
ones run again.

---

## Reading it back

| Tool | Reads | Answers |
| --- | --- | --- |
| `tools/turn-economy` | `provider.log` | where the turns went — prologue, work, epilogue; failed edits; reads and commands that bought nothing |
| `tools/report-audit` | `provider.log` | which channel each report arrived through, at what depth, and why one did not |
| `tools/final-turn-shape` | `provider.log` | whether a text block ever arrived in the final turn |
| `tools/peg-audit` | `llamacpp.log` | what the parser discarded, classified, by context depth |
| `tools/journal` | run artifacts | the two columns a person reads: files touched, and errors |
| `tools/verdict-crosscheck` | `metrics` + `evidence.log` | whether `bench/run` and `verify-round` still agree |
| `bench/summary` | `metrics` | cost per usable patch, charging failed runs to the successful ones |
| `bench/report` | `metrics` | the per-run record, every run individually |
| `bench/compare` | `metrics` | one arm against another, with the attempt-1 control |
| `tools/roundup` | run artifacts | the end-of-round report, and what the score does not cover |

All of them read preserved artifacts only. None talks to a model, and all are safe to run while a
round is in flight.

---

## Three ways to misread this

**Denominators.** `peg-audit`'s rate is per *completion*, and the fault it counts concentrates on
the report — which is emitted once per **round**. A plan whose rounds run a dozen completions
therefore reads far higher than one whose rounds run fifty, with nothing about the stack having
changed. Measured on one night: 18.6% over one plan against 1.3% over another. Compare plans by
report loss per round, never by that figure.

**Provenance.** Two arms are only comparable if they ran under the same harness. `harness_commit`
does not establish that; `harness_tree` does. `bench/compare` prints a **CONFOUNDED** warning when
they differ, and says so when older runs carry no tree at all.

**Union versus final.** `bench/run`'s scope check reads every file touched across all attempts;
`verify-round` reads the final tree. When they disagree it is usually not drift — it is the two
questions above. `tools/verdict-crosscheck` exists to tell those apart from real drift.

---

## Where the artifacts live

`bench/results/` is `.gitignore`d, and so are `.overnight/` and `*.log`. None of this is committed:
the artifacts contain your source, your plans and full provider transcripts. Archive an arm before
re-running its label — `bench/run --force` deletes the provider directory it is about to write.
