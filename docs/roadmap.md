# Queued work

Things worth building, with enough reasoning to pick them up cold. Ordered by expected value per
hour, not by how interesting they are.

Landed work is recorded in `docs/local-models.md` §9; this file is only what is still open.

---

## 1. Give the repair loop the diff and the reviewer's reading

**Today.** After a failed attempt the harness hands back one thing: the list of acceptance commands
that exited non-zero. Nothing else. The model does not see what it already changed, so a second
attempt partly re-derives the first — and sometimes undoes it. One run broke the fixture's syntax
on attempt 1, fixed it but littered on attempt 2, and cleaned up on attempt 3: 1048 seconds and 180
tool calls against a 182-second median for the same task done right first time.

**Proposed.** Feed the repair attempt three things instead of one:

1. **The failing commands** — as now, from the harness, never the model's account.
2. **`git diff` against the base commit** — what it actually did, as opposed to what it believes it
   did. These differ; the whole verification discipline here exists because they differ.
3. **A reading of *where* it failed** — the specific file and construct, not just the exit code.
   Some of this the harness already knows: which file failed `php -l` and on which line, which
   untouched region changed, which invented file appeared.

**The open question is how much to include**, and it cuts both ways. A 128k window fits the diff
comfortably for these plans — peak prompt use measured at ~36k on the four-file task, so there is
room. But context is not the only cost: more input is more to be distracted by, and this project
has one measurement pointing the wrong way. Reasoning at `medium` made a model write its own
verification scripts instead of running the plan's, duplicating the planner's job. Handing it a
richer failure narrative could push in the same direction.

**Design constraints worth keeping.**

- The diff is evidence, not instruction. Frame it as *"this is what your previous attempt actually
  changed"*, not as something to preserve or extend.
- Never include the model's own previous report. It is the least reliable artifact available and
  including it invites the model to believe its earlier claims.
- Cap the diff. A repair attempt on a large plan could otherwise be handed tens of kilobytes of
  its own output; truncate with an explicit marker rather than silently.
- Keep the reviewer's role separate. If a hosted model is asked to diagnose the failure, that cost
  belongs in the cost-to-accepted-patch figure, and the whole point of the local implementer is to
  avoid paying it on every attempt. A cheap harness-side diagnosis first, escalating to the hosted
  reviewer only on the final attempt, is the shape that preserves the economics.

**How to tell whether it worked.** Attempts-to-green and time-to-green on the same plans, against
the current baseline: `multi` at 4/5 first-attempt for reasoning-off, and the 1048s outlier above.
If richer feedback does not reduce attempts, it is costing tokens for nothing.

---

## 2. Converge `verify-round` and `bench/run`

Two implementations of "is this acceptable" exist. Scoring comes from `bench/run`; the evidence
bundle comes from `verify-round`. They already disagreed once — the verifier counted a
harness-staged plan file as something the model invented — and that is the mildest form the
disagreement can take.

`verify-round` should own the gates and `bench/run` should read its verdict.

---

## 3. Compute cost to an accepted patch

The metric this project exists to optimise, still not calculated. Every input now exists: attempts,
wall clock, generation throughput, context consumed, and whether a hosted reviewer was needed.
Nothing multiplies them.

Without it, "5/5 correct" reads as a uniform result when one of those five cost 5.7× the others.

---

## 4. A conformance gate for the serving stack

Turn `tools/repro-ollama-toolcall-500.py` into an engine-neutral probe — first-turn call, a call
after a substantial tool result, the real `apply_patch` schema, short/medium/~1 KB arguments,
streamed and non-streamed, a reused connection — and run it whenever the engine build, GGUF,
template, client version, context or tool-schema hash changes.

That turns "llama.cpp works today" into an enforced property. Without it, a silent engine
regression is indistinguishable from a model regression, which is the trap that cost this project
its longest investigation.

---

## 5. Byte-identical cannot see a mis-placed insertion

The guard verifies that no original line was deleted or altered. A model once split a method
signature from its body by inserting *between* two lines, altering neither — and it passed.
Asserting that original lines keep their relative order would close it.

---

## 6. Smaller open items

- **`providers/opencode.sh` buffers its log** and loses it on timeout, exactly as the Cline adapter
  did before that was fixed.
- **Raise repetitions to 15+** for any model that survives screening. Most gaps reported at n=5
  here are one or two runs wide.
- **A semantic-risk task class** — aggregate SQL, money, dates, permissions, concurrency — where a
  plausible wrong answer is indistinguishable from a right one on review.
- **Investigate the missing final message.** Several runs produce a byte-perfect tree and no report
  at all, under both gemma and gpt-oss. Now visible as its own outcome, `patch-ok-no-report`, but
  the cause is unknown.
- **Isolate ollama's defect to rendering or parsing** before proposing a patch upstream. Capture the
  raw generated stream from both engines at the same boundary — llama.cpp with
  `--skip-chat-parsing`, ollama immediately before `builtinParser.Add`.
- **Re-run the residency/offload question.** Its only evidence came through ollama and is void.
