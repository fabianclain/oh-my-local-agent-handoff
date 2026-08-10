# Session prompt: unattended benchmarking of local implementers

Paste this to continue benchmarking while I am away. Wall clock is cheap and repetitions are the
currency.

---

Continue the local-implementer benchmarking in `agent-handoff`. I am stepping away — keep running,
keep measuring, and write down what you learn. Do not wait for me between rounds.

## Read first

- `docs/how-it-works.md` — the system, the gates, the four prompt layers
- `docs/roadmap.md` — what is built, what is open, and the method notes at the end
- `docs/local-models.md` — every measured finding, including the ones that turned out wrong
- `bench/COMPARISON.md` — round by round results

## Where things stand

**Established.** gpt-oss-20b served by **llama.cpp** (not ollama), driven by Cline, is a working
local implementer. `tools/engine-conformance` confirms the pairing at the engine level: 14 turns,
every tool call well formed, 12 of them `apply_patch` — including after a 20 KB tool result,
streamed, and over a reused connection. Every gpt-oss result obtained through ollama is void.

**The open question is still reasoning `low` versus `off`.** The theory is that `off` should win,
because the hosted planner has already done the thinking. Correctness is at ceiling under both, so
the question is cost, and at n=5 the two rounds disagreed with each other — `low` looked better on
`multi`, `off` looked better on `wide`. That is what n=5 buys you.

## The rules that are not optional

- **A run blocked by the harness, adapter, config or machine is void.** Not a model result. The
  test: could a different harness, config or machine have produced a different outcome for the same
  model and prompt? If yes, void it and fix the cause first. Ten harness defects have been found
  here and six were mistaken for model behaviour first.
- **The model's report is not evidence.** Judge the tree.
- **One benchmark at a time.** Concurrent runs share the GPU and measure contention. Token
  accounting reads the server log by byte offset, so a second client is charged to whichever run is
  open.
- **Do not commit or push.** Leave work on `local-implementer-llamacpp`.

## How to run things

Benchmarks run from a **clone**, not the working checkout, because each attempt runs in a
`git worktree` created from HEAD — so a run uses the *committed* harness, and the working checkout
has to stay uncommitted for review.

```bash
CLONE=<scratchpad>/benchrun/repo

tools/sync-bench-clone "$CLONE"          # the only supported way to update it
tools/engine-conformance --engine llamacpp --model gpt-oss-20b --repeat 2
cd "$CLONE" && BENCH_TIMEOUT_SECONDS=1800 BENCH_MAX_ATTEMPTS=3 \
    ./bench/run --plan wide --providers lcgptossl,lcgptossnt --repeat 15 --force
./bench/report      # every run individually
./bench/summary     # cost per usable patch, failures charged to the successes
```

The clone drifting from the working checkout is not hypothetical: it happened, and 25 of 61 runs
exercised an adapter bug that had already been fixed. Every metrics file now records
`harness_commit` and `harness_dirty`. Check them before trusting a comparison.

The harness tests need no GPU and take about a minute:

```bash
tools/harness-selftest tools/feedback-selftest tools/patch-shape-selftest tools/shim-selftest
```

## What to do next

1. **Finish or extend the reasoning round** and report median *and* spread, plus generated-token
   counts. If 15 each still does not separate them, the honest answer is *"no measurable
   difference, choose on architecture"* — say that rather than manufacturing a winner.

   **Do not expect tokens to be a lower-variance instrument than wall clock.** I assumed they
   would be and they are not: measured over round 6, throughput sits in a 47.7–54.6 tok/s band
   (5.4% CV) while wall clock spans 4.9×. Seconds are tokens divided by a near-constant, so the
   two carry the same signal. What tokens add is different and still worth having — they
   decompose a slow run into *generated more* versus *generated slower* (it is almost always the
   former), and they are hardware-independent, so a number taken on another machine is still
   comparable.
2. **Measure `BENCH_FEEDBACK_DETAIL=full` against `commands`** on the same plan and provider.
   Richer repair feedback is built and switchable but unmeasured, so it is a hypothesis. Only runs
   reaching a second attempt exercise it — about half of `wide` runs — so it needs repetitions.
3. **Run `bench/plans/semantic.md`.** Written and validated, never run against a model. It measures
   a different axis: whether a plausible wrong answer survives. Reference scores 8/8, the
   round-each-line trap scores 5/8, a do-nothing tree scores 1/8.
4. Then `docs/roadmap.md`, in order.

## Two traps that cost time last night

**Never `pgrep -f` for a string your own command line contains.** A waiter written as
`while pgrep -f "bench/run --plan wide"` matches itself and never exits; the same mistake as
`pkill -f` killed a shell. Use `flock -n "${TMPDIR:-/tmp}/agent-handoff-bench.lock" true`, which
succeeds exactly when no benchmark is running.

**`cd` explicitly in every command.** Two documentation appends landed in the benchmark clone,
where the next `rsync --delete` would have erased them.

## Write things down

- New findings → `docs/local-models.md`, with the run that produced them
- New ideas → `docs/roadmap.md`, with enough reasoning to pick up cold
- Round results → `bench/COMPARISON.md`

Record what was wrong as prominently as what was right. Most of the confident conclusions in this
project's history turned out to be harness bugs, and that record is the most useful thing in it.

Report a compact summary when I return: what ran, what it showed, what you changed, and what you
got wrong.
