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
| 13 | `semantic` plan, `lcgptossl` | 12 | **A different axis**: does a plausible-wrong answer survive the gates? Never run against a model | ~1h |

### 12 and 14 are closed without being run

**Round 14 (96k context) was the wrong shape of question.** Whether a context size fits is a
property of this card and these weights, and `tools/llamacpp-serve calibrate` answers it in four
minutes by ascending through candidate sizes and keeping the largest that stays fully GPU-resident.
Measured on the RTX 5060 Ti, 16 GB: **131072 tokens, all layers resident, 948 MiB free.** KV costs
roughly 200 MiB per 16k at `q8_0`, so 64k was never near the edge — the earlier OOM was a spill
caused by something else holding the card.

The margin at 131072 is thin for a GPU that also drives a display. `CALIBRATE_MARGIN_MIB=1500`
selects 98304 instead, which is the setting to prefer when the machine is in use.

This is not entirely good news, and the next queue should watch for it: the two
`header-transposition` faults found by `tools/peg-audit` both occurred at 47–49k tokens. Raising
the window to 128k means conversations can now *reach* depths where that fault has been observed.
More context may buy more of the failure class that costs a whole round.

**Round 12 (report as a tool call) is measuring the wrong thing.** It was queued to separate an 8%
missing-report rate from a 27% one. `tools/peg-audit` shows the reports are not missing: they are
generated in full, addressed to the `final` channel with a `<|constrain|>JSON` tag rather than
emitted as a tool call, and discarded by llama.cpp's harmony parser with a warning. Changing the
channel the harness *asks* for does not address a parser that cannot map what the model produced.

Two consecutive smoke runs on `surgical` came back `report-unparseable`, so the per-round rate is
high even though the per-completion rate is 0.4% — a report is emitted once per round, and the
denominator in the audit is completions.

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
### Round 17 — answered from the server's own log, in seconds

It did not need an hour of GPU time. `llama-server` has been writing the evidence the whole time,
under a warning nobody was reading:

    W common_chat_peg_parse: unparsed peg-native output: <|channel|>...

`tools/peg-audit` classifies every occurrence and reports the rate against completions in the same
log. Over 1011 completions, 7 parse failures — 0.69% — and they are **two different faults with two
different fixes**, cleanly separated by context depth:

| Class | n | Where | What it is |
| --- | ---: | --- | --- |
| `report-in-final-channel` | 4 | 0–8k, 3.42% of that bucket | The completion report, complete and well formed, addressed to `final` with `<\|constrain\|>JSON` instead of emitted as a tool call. Discarded. |
| `header-transposition` | 2 | 47.6k–49k | The harmony header itself scrambled — `<\|channel\|>functions.run_commands<\|channel\|>commentary to=assistant`. Observed only on `run_commands`. This is the fault that spends a whole round reading files and never writing one. |
| `empty-final` | 1 | 3.8k | `{"final":""}` |

The 8k–32k middle is completely clean: 485 completions, zero failures.

**Do not read the 0.69% as the impact.** The denominator is completions, and a report is emitted
once per *round* — so per-completion understates report loss by roughly the number of completions
in a round. Four losses across ~117 completions in the shallow bucket is on the order of a dozen
rounds, which lands close to the observed ~27% missing-report rate.

What this removes: the theory that an intermittent adapter fault was depressing every arm uniformly.
It is not uniform, it is depth-dependent, and in the range most rounds actually occupy it is zero.

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
