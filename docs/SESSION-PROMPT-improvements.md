# Session prompt: continue the improvement work

Paste this after a compaction. Everything below is committed and pushed on
`local-implementer-llamacpp`.

---

Continue improving `agent-handoff` in `~/dev/agent-handoff`. The harness drives a local
model (gpt-oss-20b via llama.cpp, provider `local`) as an implementer, with a hosted model planning
and the harness verifying.

## First, prove nothing is broken

```bash
tools/smoke-e2e         # the whole journey, ~2 seconds. Start here when something is broken.
tools/selftest-all      # every suite + the plan-parser agreement check. No GPU, ~90 seconds.
```

`selftest-all` must print `everything passes`. Run it before trusting a change and again before
committing one. `smoke-e2e` is the fast one to keep re-running while editing: it walks
`init → check → do → verify → diff` against the stub provider and asserts the state at each step,
that every path in a documented command exists, that all four prompt layers arrive, and that each
documented refusal exits with its status *and says why*.

Every check in both was mutation-tested. If you add one, mutate the thing it guards and confirm it
fails — three checks in `smoke-e2e` passed vacuously on the first attempt, each because the fixture
failed for a second reason and so could not isolate what it claimed to test.

## Read first

- `docs/START-HERE.md` — the user-facing guide, including the calibration table
- `docs/BENCHMARK-QUEUE.md` — what is queued and, more usefully, what was considered and rejected
- `bench/COMPARISON.md` — nine rounds, the scoreboard, and the findings that were wrong
- `~/.claude/skills/local-implement/SKILL.md` — the procedure a driver follows

## Where things stand

A real greenfield Laravel task went **0 accepted in 5 rounds** against documented figures of 78%
first-attempt. Those figures are a six-file refactor of existing code; the gap is calibration, not
regression, and it is recorded in START-HERE.

The failure taxonomy from those five rounds, by frequency:

1. **File corruption** — 2 of 5, both fatal, both a docblock running into a method body on a second
   edit of a file over 150 lines. An editing failure, not a reasoning one.
2. **Invented conditions** — 3 of 5. Thresholds and guards the plan never mentioned.
3. **Scratch files** — 2 of 5, despite prose forbidding them. Both were app-bootstrapping scripts
   to print one value.
4. **Silent contract drift** — three row fields dropped, one renamed.
5. **Specified dependency ignored** — injected as instructed, then never called.
6. **Placement errors** — a route below the catch-all, after two prose warnings.

What worked: reviewer-written tests caught every numeric error; splitting produced the best round
(9/12 on one file against 4–5 on six); worktree isolation held.

## Done today, do not redo

Non-ASCII paths (`core.quotePath=false`), the read-only gate's baseline for untracked files,
`resume` verifying, `handoff init`/`check`, `tools/check-plan`, the advisory/verdict split, the
report-as-MCP-tool channel, and the skill's decomposition and diagnose-then-re-specify steps.

## Next, in order

**1. Linter as a post-write hook.** The highest-value untried change. Round 5 spent its whole budget
building on a file that had not parsed since its first edit. Cline exposes `--hooks-dir`; a
post-write hook running the project's linter and feeding the error straight back would let the
model repair a truncation immediately instead of at verification, when the round is already spent.
Queued as round 16.

**2. Whole-file writes for files under ~400 lines.** Queued as round 15. Note the tension: the
patch-only gate exists because a 421-line service came back as an 11-line fragment. It is advisory
now so it will not reject the arm, but truncation is the shared failure mode of both approaches —
which is why 1 probably matters more than 2. Run 16 first if you only run one.

**3. A sanctioned REPL and a disposable scratch dir.** Both litter incidents were the model trying
to inspect a value with no legitimate way to do it. Expose an eval tool, and redirect writes outside
the plan's allowed paths into a temp dir that is cleaned up — converting a round-failing violation
into a non-event. Prose forbidding it has now failed twice.

**4. Flag regressions in the evidence header.** Round 5 went 9/12 to 3/14 by corrupting a file it
had nearly finished. A "regressed from 9/12" line would say plainly: stop resuming, take over.

**5. Skill: assert the full shape of anything a later step consumes.** Step 1's tests gated what its
own aggregates read, so three fields step 2 needed went unguarded. Step 1 would have been accepted
and step 2 would have failed on a gap step 1 was meant to guarantee.

**6. Skill: any named API that must be used deserves a grep criterion.** "Use `deduplicatedQueries`"
was ignored while the constructor dutifully accepted the dependency. `grep -q 'deduplicatedQueries'`
catches it in a second. Same for the no-scratch-files rule — greppable, and prose failed it twice.

## Measuring 1 and 2

Both are measurable against `wide`. **The control is `wide/lcgptossl-r6`** (15 runs) — `wide/lcgptossl`
is an empty directory left by a queue that was stopped before recording anything.

```bash
tools/sync-bench-clone "$CLONE"        # once per queue, never between rounds
cd "$CLONE" && ./bench/run --plan wide --providers <arm> --repeat 15 --force
./bench/compare wide lcgptossl-r6 <arm> --acts-on first-attempt
```

`--force` deletes the provider directory it writes. Archive any arm that is a published control
first. Expect `chance`: this plan's noise floor is around 20 points at n≈15, measured from two arms
that were identical by construction.

## Rules that are not optional

- A run blocked by the harness, adapter, config or machine is **void**, not a model result.
- The model's report is not evidence. Judge the tree.
- One benchmark at a time; the bench lock enforces it.
- Never `pgrep -f` for a string your own command line contains, and never pipe a long command to
  `tail` and read `$?`. Both have caused real errors here.
- Do not commit or push unless asked.
