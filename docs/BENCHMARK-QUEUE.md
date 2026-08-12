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

### Round 13 — REVISED. The wrong answer does get produced, and the gates passed it

Six runs of `semantic` against `lcgptossl`: 5/6 usable, 3/6 accepted. The question the plan exists
to ask is not answered by those numbers, though — it asks whether an implementation that satisfies
six hand-picked examples agrees with the specification *everywhere else*.

All five surviving implementations were extracted and fuzzed against a reference built from the
plan's own words: 4000 random trials each, varying period length, line count, fees and active days.
**Zero disagreements, in all five.** Every one implements largest-remainder correctly, including
the tie-break by insertion order, and every one gets the odd-`D` half-up case right — `intdiv($sum
+ intdiv($D,2), $D)` differs from `floor(sum/D + 1/2)` only when `sum/D` has fractional part
exactly one half, which requires `D` even, where the two coincide.

The fuzzer was mutation-tested against the wrong answer the plan warns about — rounding each line
and adding the results — which it flags on 920 of 4000 trials. And that wrong answer would not have
reached the gates anyway: acceptance criterion 2 requires a subtotal of 1000 on three lines of
1000 cents over ten of thirty days, and rounding per line gives 999.

**That conclusion was wrong, and four more runs overturned it the same day.** The same plan through
the native provider produced 4/4 accepted, 8/8 criteria — and one of the four disagrees with the
specification on **2,283 of 4,000 fuzzed trials**.

The amounts are right every time; the *order* is not. The plan requires the allocation "keyed by
line name, in the order the lines were added". That implementation sorts entries by remainder to
distribute the leftover cents — correct — and then builds the returned array in the sorted order
instead of restoring insertion order.

**It passes the plan's own ordering criterion**, because the worked example uses three identical
lines: every remainder ties, the tie-break by index preserves the original order, and the check
goes green. Give the lines unequal remainders and it is wrong more than half the time.

The lesson is narrower and more useful than "hand-computed examples suffice":

> A worked example that is symmetric in the thing it tests cannot test it. Three identical lines
> cannot detect an ordering bug, because every order is the same order.

The criteria now carry a case with unequal remainders — D=11, fees 2663/2909/693 over 3/8/8 days —
taken from an observed failure rather than invented. The first replacement WAS invented, used three
full-period lines, and discriminated nothing: with every line active the whole period the division
is exact, no cents are distributed, and the sort never runs. The one now in the plan is verified to
fail the bad implementation and pass the other three.

Corrected tallies: **native is 3/4 correct on semantic, not 4/4**, and across both providers the
plausible-wrong answer appears in 1 of 9 implementations rather than 0 of 5.

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

~~**Round 12 (report as a tool call) is measuring the wrong thing.**~~ **Reinstated as the top
priority, and the dismissal above was wrong.** It was written on the reasoning that a parser which
cannot map the model's output will not be helped by changing the channel the harness asks for. The
chat template says otherwise — see below. A tool call is the one place `<|constrain|>json` is
legal, so routing the report there puts the model's own instinct onto a parseable path, which is a
*mechanism* the arm previously lacked.

Round 10 already measured it at low power: **no report 1/12 (8%) against 4/15 (27%)**, turns ending
with no text block 17% against 33%, p = 0.34. Round 12 exists to give that enough power to
separate. `~/.cline-llamacpp-mcp` is already configured, so it can run as-is.

### The chat template and the model disagree about harmony, and that explains both faults

Read back from the running server, `GET /props` → `chat_template`, 16,616 characters. Two
observations, both directly checkable:

| | The GGUF's template renders | The model emits |
| --- | --- | --- |
| a tool call | `<\|start\|>assistant to=functions.NAME<\|channel\|>commentary json<\|message\|>` | `<\|channel\|>functions.run_commands<\|channel\|>commentary to=assistant<\|constrain\|>json<\|message\|>` |
| a structured final | `<\|start\|>assistant<\|channel\|>final<\|message\|>` | `<\|channel\|>final <\|constrain\|>JSON<\|message\|>` |

The template puts `to=` **before** the channel token and marks the content type with a bare word.
The string `<|constrain|>` does not occur anywhere in its 16,616 characters. The model puts the
channel first and marks content type with a `<|constrain|>` token — which is the ordering and the
tag used by OpenAI's published harmony format. *(Stated from the harmony documentation rather than
re-derived here; worth confirming before it is quoted anywhere load-bearing.)*

So the model was trained on one dialect and is being prompted in another, and both observed faults
are what that produces: a header assembled from halves of each convention, and a `<|constrain|>`
tag applied to a `final` message because the model wants to signal "this is JSON" and the harness
has asked for JSON in the final message.

**This weakens the case that it is a llama.cpp defect.** Putting a tool-call construct on a final
message is not canonical harmony, so a parser rejecting it is defensible. The narrow upstream
request that survives is leniency — recover the message body instead of discarding it — and that is
a much smaller ask than a bug. The larger question, whether this GGUF's template matches what
gpt-oss was trained on, belongs to whoever published the GGUF.

**The workaround is on this side and already built.** Ask for the report where `<|constrain|>json`
is legal: as a tool call.

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
### The window is not the variable. Conversation depth is.

`llamacpp-serve start` truncates the server log, so each session's parse-failure rate is measured
in isolation rather than cumulatively:

| Session | n_ctx | Completions | Discarded | Rate |
| --- | ---: | ---: | ---: | ---: |
| earlier era | 32k / 64k | 1011 | 7 | 0.69% |
| overnight | 131072 | 1743 | 23 | 1.32% |
| morning wave | 98304 | 359 | 4 | 1.11% |

Pulling the window back from 128k to 96k did not move the rate — 4 observed against 4.7 expected if
nothing had changed. The queue file said in advance that eight repetitions could not settle this,
and it could not.

But the depth table did not change either, and that is the finding. At 96k: **0 failures in 99
completions below 16k, and 2 in 33 above 48k (6.06%).** The fault tracks how deep the conversation
has gone, not how large the window is — which is exactly why shrinking the window achieved nothing.
A conversation that reaches 50k fails at the same rate whether the ceiling is 96k or 128k.

**So the lever is step size, not `n_ctx`.** Keep the window large enough that nothing overflows, and
keep steps small enough that conversations stay shallow. Those are not in tension.

### The missing reports are a serving-stack defect, and the retries are wasted

`tools/final-turn-shape` gives every `patch-ok-no-report` round the same signature:

    att 1   finish=error       text? NO    last blocks: reasoning,tool,reasoning
    att 2   finish=completed   text? yes

The model emits the report, the harmony parser rejects it, Cline reports an error with no text
block, and the harness records "no report". Across 48 runs, 24 provider calls ended that way.

**Read that `att` column carefully — it is provider calls, not benchmark attempts.** The first
version of this section said 22 of 48 runs "spent a second attempt" and paid double. That was a
misreading of `tools/final-turn-shape`, whose `att` counts `run_result` events, and the harness's
own report re-ask is one of them. Checked against the metrics, every one of those runs recorded
`attempts=1`: the acceptance criteria had already passed, so `bench/run` broke out of its loop
correctly and **no round was re-implemented.**

Measured cost of the re-ask, over six runs: **7.2% of output tokens and 4.9% of wall clock.** It
fails the same way the original did — 700–1300 tokens generated, `{"tool_calls":[],"final":""}`
returned. So it is waste, not damage, and suppressing it would save about 1.2% overall. Not worth
the change.

What follows instead:

1. **`llama-server` is pinned at `b10331`, and upgrading is not the fix.** The 26 commits between
   `b10331` and `b10357` touch `common/chat.cpp` only for an unrelated chat template. Reverting is
   worse: the PEG chat parser landed in #17136 on 2025-12-03, so escaping it means going back eight
   months. Neither direction helps, which leaves reporting it upstream.
2. **`tools/engine-conformance` cannot detect a fix for this.** It passed 21/21 on the broken build,
   twice. It exercises tool calls; this fault is a `final`-channel message. Any test of a candidate
   build has to measure the no-report rate per round over a wave, not conformance.
3. ~~**The untested lever is sampling.**~~ **Tested, and it is not the cause.** Eight runs at
   `--temp 0 --top-p 1 --top-k 0 --seed 42`, same plan and same 98304 window as the control:

   | | temp 0.8 | temp 0 |
   | --- | ---: | ---: |
   | no-report rounds | 5/8 | 3/8 (p = 0.62) |
   | completions discarded | 1.11% | 1.17% |
   | usable tree | 8/8 | 8/8 |

   Against the 33% no-report baseline over 48 runs, 3/8 is 37.5% — not an improvement, and the
   queue file said in advance that 3/8 reads as "no effect at this n" rather than as a small gain.

   **The consequence matters more than the null result.** At temperature 0, top_k 0 and a fixed
   seed, the model still emits `<|channel|>final <|constrain|>JSON<|message|>` for its report, and
   still transposes `run_commands` headers — one of them with three `<|channel|>` tokens in a row.
   These are not sampling noise. They are what greedy decoding produces, which means no sampler
   setting can avoid them, and equally that the fault is **deterministic and therefore
   reproducible**. That is what makes it worth reporting upstream rather than working around.

   Before filing, check the GGUF's own chat template. If it renders prior turns in non-canonical
   harmony the model would be imitating it, and the defect would be on this side of the line.

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

### Round 15, first look: the failure is not truncation. It is diff syntax

`nativewhole` finally made round 15 runnable — one flag rather than a client that offers a
different tool set. The feared trade-off did not appear. Whole-file writes truncated **nothing**:
every file came back complete, with the right additions. What broke a round instead:

    -}
    ++
    ++    /**
    ++     * Render the total in the requested currency.
    ++     */
    ++    public function summaryIn(...): string
    + }

Read past the diff's own `+` column. The file on disk contains a literal `+` on every added line
and a literal leading space on the unchanged closing brace. Told to write the file whole, the model
wrote a **patch** into the `.php`. Its parse error at line 67 failed all nine functional criteria —
each of them loads the file first — for 2 of 11, through two attempts, 394 seconds, 71 requests.

Rare across the archive: 2 runs of 73 show diff-prefixed lines, and only 2 of 73 end with a PHP
parse error at all. So round 16's premise is weakly supported *on this fixture*; the greenfield
Laravel rounds that motivated it broke far more often, and `wide` is not where its value shows up.

`write_file` and `replace_in_file` now run the language's parse check as a postcondition and hand
the error back on the turn the file is written. That is round 16's idea as a **mechanism** rather
than the instruction that was measured at no effect (n=20 per arm, damage identical at 5/20).

**The first run of this arm is void and so is any reading of it**: it ran against a 32768 server
while every document said 98304, and stopped on the context budget in 3 of 3 provider calls at
~28.8k. Whole-file writes do consume context faster — each write puts a whole file in the history —
but "they exhaust the window" cannot be concluded from a window a third of the stated size.

### Queued from tonight, not yet run

| Question | Why it is worth an arm |
| --- | --- |
| Does `--max-turns 40` bind? | One `wide` round ended at the limit with 11 of 11 criteria met and no report — the tree was finished and there was no turn left to say so. At 98304 there is room for more turns, but more turns means deeper context, and depth is what correlates with discarded output. Measure the turn-limit rate before changing it |
| Is the 17% re-read rate worth attacking? | `tools/turn-economy` puts 1 in 6 reads and 1 in 5 searches at redundant — a file read again with no edit to it in between. A tool result could say "you read this at turn N and it has not changed", which is information rather than instruction. Unproven, and the register is full of prompt-layer changes that moved nothing |
| Does the report re-ask actually recover rounds? | Landed tonight and measured only on fixtures. The population that would size it — the 20-run Cline control — was deleted by `--force` before it could be used |

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

### Round 15 at the right window, and a claim of mine that lasted three runs

Re-run at 98304 after the 32768 episode, same harness commit.

**What held.** The context-budget stops were the window. They were 3 of 3 provider calls at 32768
and are 0 of 8 at 98304. Nothing about whole-file writes exhausted the context.

**What did not hold.** At n=3 per arm `nativewhole` hit the 40-turn limit in 2 of 3 rounds and
`native` in none, and this file said whole-file writes "cost turns, not correctness". Three more
runs per arm erased the difference:

| finish reason, per provider call | `native` | `nativewhole` |
| --- | ---: | ---: |
| turn-limit | 3 | 3 |
| completed | 3 | 3 |
| error | 1 | 2 |
| recovered-report | 1 | 0 |

The turn limit binds **both** arms, in roughly 3 of 8 provider calls. That is a fact about
`--max-turns 40`, not about editing style, and the editing-style reading came from a three-run
split that the queue file's own noise-floor note predicts: at this n the plan's floor is about 20
percentage points.

Kept as written rather than quietly replaced, because the failure mode is the one this document
exists to record — a mechanism inferred from a difference that was not there.

**What is still true of the arm at n=6:** 11 of 11 criteria in every single round, both arms.
`native` 6/6 accepted, `nativewhole` 5/6 with one round losing its report. Whole-file writing does
not produce worse code on this plan. Whether it produces worse code on a *large* file — the 421-line
service that motivated the patch-only gate — this plan cannot say, and that is the version of round
15 still worth running.

**The real finding is the turn budget.** Over a third of provider calls end at the limit, and at
least one of them had already met every criterion and had no turn left to report in. Raising
`--max-turns` trades against depth, which is what correlates with discarded output, so it needs an
arm rather than a guess.

### The post-write syntax check: a good predictor, an unproven remedy

Landed tonight, and measured over 36 native-family rounds on `wide`. It fires often — 17 of 36
rounds wrote at least one file that did not parse — and the count separates cleanly:

| post-write warnings in a round | accepted | not accepted |
| --- | ---: | ---: |
| 1 or 2 | 14 | 0 |
| 3 or more | 1 | **2** |

Both failures are `nativewhole`, at 4 and 6 warnings, and the worse one ended with a parse error
still in the tree at 2 of 11 criteria. So writing an unparseable file once or twice is ordinary and
recovered; doing it repeatedly is a round already lost, and the count is visible long before the
verification runs.

**What this does not show, and must not be read as showing.** There is no arm without the check.
Fourteen rounds warned and then passed, and nothing here says the warning is why — the model may
have re-read and fixed those files anyway, as it did before this existed. The honest comparison is
the damage rate, and it has not obviously moved: 2 of 73 archived runs reached final verification
with a PHP parse error; tonight it is 1 of 36. Same order, no separation at this n.

The check earns its place as a *signal* on that evidence, not as a fix. What it argues for is the
arm that would settle it, and an escalation: three warnings in one round is a better abort
condition than the turn limit, because it identifies a round that is going to fail while there is
still budget to do something about it.

### Round 15 at n=12: whole-file writes do damage, at a rate this n cannot separate

| | `native` | `nativewhole` |
| --- | ---: | ---: |
| accepted | 12/12 | 9/12 |
| `patch-damaged` | 0/12 | **2/12** |
| lost report | 0/12 | 1/12 |

Fisher on the damage counts is p = 0.48 — chance. The direction matches the reason the patch-only
gate exists, and the mechanism is visible in both failures (repeated unparseable writes), but 12
rounds cannot separate 0 from 2. The earlier reading in this file, that whole-file writes cost
turns rather than correctness, is now wrong in both halves: the turn limit binds both arms equally,
and the damage does not.
