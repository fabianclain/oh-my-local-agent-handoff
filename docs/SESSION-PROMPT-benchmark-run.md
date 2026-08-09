# Session prompt: unattended benchmarking of local implementers

Paste this to continue benchmarking while I am away. I have granted ~10 hours of continuous local
model use, so wall clock is cheap and repetitions are the currency.

---

Continue the local-implementer benchmarking in `agent-handoff`. I am stepping away — keep running,
keep measuring, and write down what you learn. Do not wait for me between rounds.

## Read first

- `docs/how-it-works.md` — the system, the gates, the four prompt layers
- `docs/roadmap.md` — queued improvements, in priority order
- `docs/local-models.md` — every measured finding, including the ones that turned out wrong

## Where things stand

**Established.** gpt-oss-20b served by **llama.cpp** (not ollama), driven by Cline, is a working
local implementer: 15/15 at 9/9 on the four-file `multi` plan, and passing the six-file `wide`
plan. Ollama's harmony path corrupts this model's tool calls — every gpt-oss result obtained
through ollama is void.

**The open question.** Reasoning `low` versus `off`. My theory is that `off` should win, because
the hosted planner has already done the thinking and the implementer should only execute. **The
data does not support that yet.** On `multi`, five runs each: both 5/5 correct, medians 182s (low)
against 335s (off), totals 1783s against 1833s. Indistinguishable on correctness, and `off` was not
slower overall.

Prove it or dismiss it. Do not assume the conclusion.

## What to run

The `wide` round in flight covers `lcgptossl` (low) then `lcgptossnt` (off), 5 each. When it
finishes, raise repetitions — n=5 is too small, and at n=1 this model's spread is wider than any
difference being measured. Three separate first-run readings were overturned by the fifth run in
one day.

```bash
tools/llamacpp-serve status                       # must be serving gpt-oss-20b
BENCH_TIMEOUT_SECONDS=900 BENCH_MAX_ATTEMPTS=3 \
  bench/run --plan wide --providers lcgptossl,lcgptossnt --repeat 15 --force
bench/report
```

If 15 each still does not separate them, the honest answer is "no measurable difference, choose on
architecture" — say so rather than manufacturing a winner. If they do separate, report median
*and* spread; one 1048s outlier already ate an entire apparent advantage once.

If `wide` turns out too easy to discriminate, write a harder plan. Difficulty means **more work,
not more decisions**: more files, more methods, more tool calls, every signature dictated. Validate
any new plan against a reference solution, its trap, and a do-nothing tree before using it to
measure anything — all three plans in `bench/plans/` were validated that way.

## While rounds run

Work through `docs/roadmap.md` in order. Item 1 is giving the repair loop the `git diff` of what
the previous attempt actually changed. Items 2 and 3 — converging `verify-round` with `bench/run`,
and computing cost-to-accepted-patch — are the highest value after that.

Test every guard against the exact failure it targets. Several guards here passed their first test
vacuously and were wrong.

## Write things down

- New findings → `docs/local-models.md`, with the run that produced them
- New improvement ideas → `docs/roadmap.md`, with enough reasoning to pick up cold
- Round results → `bench/COMPARISON.md`

Record what was wrong as prominently as what was right. Most of the confident conclusions in this
project's history turned out to be harness bugs, and that record is the most useful thing in it.

## Rules that are not optional

- **A run blocked by the harness, adapter, config or machine is void.** Not a model result. The
  test: could a different harness, config or machine have produced a different outcome for the same
  model and prompt? If yes, void it and fix the cause first.
- **The model's report is not evidence.** Judge the tree.
- **One benchmark at a time.** Concurrent runs share the GPU and measure contention.
- **Do not commit or push.** Leave work on `local-implementer-llamacpp`; I will review.

Report a compact summary when I return: what ran, what it showed, what you changed, and what you
got wrong.
