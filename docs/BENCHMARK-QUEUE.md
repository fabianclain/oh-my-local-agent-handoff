# The benchmark queue

What is queued, why, and what each round would settle. Kept in the repository because the reasoning
for *not* running something is as useful as the result of running it.

## Running a queue

Rounds run in sequence against **one harness commit**, synced once at the start:

```bash
tools/sync-bench-clone "$CLONE"          # once — see below for why
cd "$CLONE"
BENCH_TIMEOUT_SECONDS=1800 BENCH_MAX_ATTEMPTS=3 \
  ./bench/run --plan wide --providers lcgptossl --repeat 20 --force
```

**Sync once, not between rounds.** Round 10's comparison carried a confound — control on harness
`cf66901`, treatment on `5ff3ad6` — because the clone was updated between them. Arms measured
against different harnesses are not comparable, and nothing in the output warns you.

**`--force` deletes the provider directory it is about to write.** Archive any arm that is a
control for published results before re-running its label, or the baseline is gone with no way back.

## Queued

| Round | Arm | n | What it settles | Est. |
| --- | --- | ---: | --- | ---: |
| 11 | `lcgptossl` — message channel | 20 | A clean control under the current harness, and whether the litter rule changed anything (round 6: 1/15) | ~2h |
| 12 | `lcgptossltool` — report as a tool call | 20 | 8% against 27% missing reports, at enough power to separate them | ~2.3h |
| 13 | `semantic` plan, `lcgptossl` | 12 | **A different axis**: does a plausible-wrong answer survive the gates? Never run against a model | ~1h |
| 14 | `lcgptossl96` — 96k context | 15 | 64k is measurably at its edge; two runs have filled it and silently lost history | ~1.5h |

Round 14 is last because it restarts the serving stack. Everything above it shares one server, so
a restart cannot affect results already recorded, and conformance is re-probed afterwards — context
size is part of the stack, and a stack that stops emitting usable tool calls must never be
attributed to the model.

## Queued from real use — the editing-failure batch

Seven rounds on a greenfield Laravel task produced 0 accepted, against documented figures of 78%
first-attempt. **File corruption ended the two most promising rounds** — a docblock running into a
method body, parse error, both times on files over 150 lines being edited a second time. That is an
editing failure, not a reasoning failure, and nothing in the harness targets it.

Rounds 6 and 7 of that feature added a second failure with nothing behind it either: **intermittent
tool-call corruption**, reported by the adapter as `peg-native format`, three occurrences in each
round. Round 7 recovered and wrote both files. Round 6 never did — 44 tool calls, every one a
`read_files` or `search_codebase`, not a single `apply_patch` or `run_commands`, over in 35 seconds
and 1336 output tokens, empty diff, and a report claiming partial success. An entire round bought
nothing, and the harness recorded it as a model failure because it has no way to tell the two
apart.

| Round | Arm | n | What it settles | Est. |
| --- | --- | ---: | --- | ---: |
| 15 | `lcgptosslwhole` — whole-file writes under ~400 lines | 15 | Does rewriting the file wholesale eliminate mis-anchored partial edits? Targets the #1 observed failure | ~1.5h |
| 16 | `lcgptosslsyntax` — linter as a post-write hook | 15 | Does feeding a parse error back immediately let the model repair a truncation, instead of building on a broken file for the rest of its budget? | ~1.5h |
| 17 | `peg-native` repro, not a benchmark | — | Is the tool-call corruption reproducible outside Cline? Extend `tools/engine-conformance` with the call shapes round 6 died on, alongside `tools/repro-ollama-toolcall-500.py` | ~1h |

Round 17 is diagnostic rather than comparative, and it should run **before** 15 and 16: a round
that emits no writes at all is scored as a failure, so an intermittent adapter fault silently
depresses every arm it touches. Two of seven real rounds hit it. If that rate holds inside the
benchmark, it is larger than most of the effects being measured.

Both are measurable against `wide` with round 11's arm as control, and both should be run before
anyone trusts a read of five rounds — including the read that produced them.

**A conflict to resolve before round 15.** The patch-only gate exists because a 421-line service
came back as an 11-line fragment; whole-file writes are exactly what it was built to catch. It is
now advisory rather than verdict-bearing, so it will not reject the arm, but the tension is real:
truncation is the shared failure mode of both approaches, and what actually distinguishes them is
whether a syntax check runs before the round is spent. Round 16 may matter more than round 15.

## Considered and not queued, with the reason

| Not running | Why not |
| --- | --- |
| More reasoning levels | Settled. `low` against `off`, 15 each: quality indistinguishable (p ≥ 0.70), cost inside noise. Resolving the 26% point estimate needs ~35 runs per arm for a setting with no quality consequence |
| Sampling temperature again | Settled, and in the wrong direction. Deterministic sampling made spread **wider** (CV 61% → 76%). Token-level determinism does not survive a loop whose first tool call it does not control |
| The feedback A/B, as designed | Only runs that fail once exercise it — 4 of 12 did, so twelve runs bought six informative points. Needs a plan the model *reliably* fails first |
| A second model (gemma via llama.cpp) | Genuinely open and the biggest unknown, but needs an 8 GB download and a fresh conformance probe. Worth a queue of its own |
| Cline `--compaction` | Untouched and plausibly relevant to the context limit, but it interacts with round 14. Sequence it after |

## Reading a round when it lands

```bash
bench/summary                                        # cost per usable patch
bench/compare wide <control> <arm> [--acts-on first-attempt]
tools/final-turn-shape bench/results/wide            # why reports go missing
```

`bench/compare` scores attempt 1 separately, where the arms are identical by construction for any
variable that only acts on repair. Pass `--acts-on first-attempt` when the variable acts earlier —
a reasoning level, a sampling change, a report channel — because then attempt 1 is a result rather
than a control, and the tool must not pretend otherwise.

Expect `chance`. At n≈15 this plan's noise floor is roughly 20 percentage points, measured from two
arms that were identical by construction and still differed by that much.
