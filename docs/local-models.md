# Driving a local model as the implementer

Notes from running Gemma 4 12B (Q4_K_M, 128k context, RTX 5060 Ti) against real plans in a
Laravel repository. Every claim here was measured; where a number is quoted it came from a run.

Update this file after each round. The point is to find what actually moves the success rate,
not to collect impressions.

## What is measured so far

| Change | Before | After |
| --- | --- | --- |
| Output-discipline section added to the plan | 2/5 criteria | **5/5**, and faster (90s → 77s) |
| Short single-word plan slug | false "plan not found" blocker | round proceeds |
| stdin closed on the opencode invocation | 31 min stall, 0-byte log | round runs |

For comparison on the same plan, codex scored 5/5 in 104s. A guided Gemma beat it on wall clock.

## The failures, and what each one taught

### 1. It writes its reasoning into the deliverable

First real artifact contained three successive implementations in one file, each commenting on
the last: *"Correction: the above is wrong"*, *"Re-writing logic properly"*, *"Actually, the rule
is..."*. Syntactically valid, semantically three half-finished drafts.

**Fix that worked:** an explicit *Output discipline* section — one implementation, no
self-commentary, no alternatives, read the file back before finishing. Took the same model from
2/5 to 5/5 on an unchanged task. This is now in `templates/plan.md`.

**What did NOT need fixing:** task size. The plan was already one 30-line file with five explicit
criteria and exact input-to-output examples. "Make the task smaller and more specific" would have
changed nothing, because ambiguity was never the problem.

### 2. It mis-transcribes long hyphenated identifiers

Given `search-log-persist-total-results`, it looked for `search_log_persist_total_results`,
failed, and reported the plan as missing rather than listing the directory. Renaming the plan to
`totals.md` made the same round proceed.

**Fix:** keep plan slugs short and ideally one word. Also worth teaching it to `ls` before
concluding a file is absent — a model that gives up on a path typo wastes a whole round.

### 3. It reports success it did not achieve

The most dangerous failure seen. A round returned `status: complete`, **zero deviations, zero
blockers**, and claimed *"Migration executed successfully"*, *"All search-related tests passed"*
and *"Updated the UI"*. In reality:

- the migration was a **single line of literal `\n` characters** — a PHP parse error, so it never
  ran and the column was never created
- it also broke a production file (`EntryIngestor.php`) with a mangled array close
- the UI file was untouched
- no tests were written
- `(int) ($x ?? 0)` turned a legitimate null into `0`, silently corrupting a "not reported" value
  into "zero results"

**Fix:** treat the report as untrusted metadata and check the tree first. `.handoff/bin/gemma-round`
runs `php -l` over every changed file **before** anyone reads the report, and reverts the round if
anything fails to parse. A syntactically broken file blocks every later round, and unattended
there is nobody to notice.

Compare with a hosted model on the same pipeline: codex returned `partial` with a blocker
correctly naming a file **it did not own** as the cause of a failing test. That is the behaviour
you want and cannot assume.

### 4. Escaped newlines in written files

Related to 3 but distinct and worth naming in the plan text itself: the tool-call path can emit
`\n` as two characters. Plans now say **write real newlines, then run `php -l` and confirm it
parses**. A file that does not parse is not progress.

## Failures that were NOT the model's fault

Worth separating, because blaming the model for harness bugs leads to the wrong fixes.

- **A 31-minute stall with a 0-byte log.** `opencode run` reads stdin when stdin is not a TTY, so
  in a background shell it waited forever. The model had loaded, gone idle, hit its keep_alive
  timeout and unloaded. Fixed by closing stdin. The codex adapter had the identical bug.
- **"Plan file not found" from qwen2.5-coder:14b**, twice, in 18 seconds. The harness copies the
  plan into the worktree before every run and Gemma read it through the same adapter. A
  fabricated blocker, not a harness problem — but it looks like one until you check.

## Telling a working round from a hung one

From outside they are identical: process alive, no exit code, log not growing. Two signals
together resolve it, and `.handoff/bin/watch-local` checks both:

- **GPU busy + log flat** → normal, it is generating
- **no model in `ollama ps` + log flat** → dead; kill it

A wall-clock timeout alone is the wrong instrument: it eventually catches a stall, but only after
wasting the whole budget. Stall detection catches it in minutes.

## Model selection

Check `ollama show <model>` for `tools` under Capabilities before anything else. Without tool
calling the model cannot edit a file or run a command through opencode — it will produce prose
and change nothing, scoring zero for a reason that says nothing about its coding ability.

Observed: `deepseek-coder-v2:16b` and a third-party lite quant both advertise only
`completion` (+`insert`). Unusable as implementers regardless of how good the weights are.

Context must be **baked into a derived model** with `PARAMETER num_ctx`. Ollama defaults `num_ctx`
to 4096 regardless of a model's advertised ceiling, so a 262k-capable model silently truncates at
4k. Declaring the window in opencode's model entry is not enough on its own.

## Open questions, to test next

- Does splitting a genuinely multi-file task into sequential single-file rounds help, or does the
  loss of context hurt more than the focus helps? Untested — the one real multi-file attempt was
  destroyed by the stdin bug before it produced anything.
- Does a lower temperature reduce the draft-in-file behaviour beyond what the prompt already
  fixed?
- Do explicit per-file instructions ("create exactly this file, with exactly these methods") beat
  a descriptive plan for a 12B?
