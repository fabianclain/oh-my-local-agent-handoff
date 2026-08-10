# Queued work

Things worth building, with enough reasoning to pick them up cold. Ordered by expected value per
hour, not by how interesting they are.

Landed work is recorded in `docs/local-models.md` §9; this file is only what is still open.

---

## 1. ~~Give the repair loop the diff~~ — built, still unmeasured

**Built.** `tools/render-feedback` renders the repair message, and `BENCH_FEEDBACK_DETAIL` selects
how much of it a retry gets:

- `commands` (default) — the failing command lines only. This is the baseline every measurement in
  `bench/COMPARISON.md` was taken under, and it stays the default so those numbers remain
  comparable.
- `full` — additionally the harness's captured output for each failing command (capped, with the
  dropped line count stated) and the diff of what the previous attempts actually changed (capped
  at 24 KB, cut on a line boundary, truncation declared).

The model's own previous report is still never included. It remains the least reliable artifact in
a run, and quoting it back invites the model to believe its earlier claims.

Guards are in `tools/feedback-selftest`, and each was mutation-tested: removing the guard makes its
own check fail and no other. `tools/harness-selftest` then checks that `bench/run` actually wires
the renderer up, using a stub provider that runs no model.

**Measured in round 7, and the answer is inconclusive — for a design reason worth fixing before
anyone repeats it.** Twelve runs of `full` against round 6's fifteen of `commands`:

- Final outcomes look dramatic — usable tree 8/12 against 14/15 — and that reading is wrong.
- **The divergence is already present in attempt 1**, where the feedback does not yet exist:
  attempt-1 green was 13/15 for `commands` and 8/12 for `full` (p = 0.36). Two arms that are
  byte-identical at that point differ by most of the headline gap. That number is the plan's
  noise floor, and it is large.
- Where the variable *can* act, `full` looks worse and the sample is tiny: of runs reaching a
  second attempt, `commands` recovered to 11/11 in 2 of 2, `full` in 0 of 4 (p = 0.07).

**The design is the problem.** Only runs that fail their first attempt exercise the feature, and
just 4 of 12 did — twelve runs bought six informative data points. A real test needs a plan the
model *reliably* fails once, so every repetition exercises the repair path. Building that plan is
the prerequisite, not more repetitions of this one.

Ruled out as causes: context pressure (`truncated_requests=0` on all twelve, so the extra ~6 KB of
diff never reached the window) and a malformed prompt (re-rendering the worst run's feedback from
preserved artifacts gives 12,630 well-formed bytes with balanced fences and a 6 KB diff body).

**Watch the context when measuring it.** Peak prompt use was ~36k of a 64k window on the four-file
task. A `wide` repair attempt under `full` adds the captured output plus up to 24 KB of diff, which
is roughly 6k more tokens, and a third attempt carries a diff of everything two attempts did. If
the A/B shows `full` doing worse, rule out context pressure before concluding the model was
distracted — those two produce the same symptom and have opposite fixes.

**The reviewer's reading is deliberately not built.** A hosted model diagnosing each failure puts
hosted cost back into every attempt, which is the cost the local implementer exists to avoid. If it
is ever added, it belongs on the final attempt only.

---

## 1b. Original reasoning, kept for the design constraints

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

## 0. Ask for the report through the channel that works — built, not yet measured

**The observation.** This model emits tool calls reliably and final text unreliably. At the engine
level, 14 of 14 tool calls were well formed, including a ~1 KB freeform payload after a 20 KB tool
result. Meanwhile 33–40% of first attempts end with a reasoning block, a tool call, and no text
block at all — the largest non-success outcome measured here, and every instance is a correct patch
thrown away for want of an envelope.

**The change.** `providers/lcgptosslrf.sh` asks the model to write its completion report to a file
with its ordinary file tool instead of returning it as the final message. The path is under
`.handoff/runs`, which every scope and litter gate already excludes, so writing it cannot be scored
as littering.

Behaviour, tested against a fake client that reproduces Cline's real event shape:

| Case | Result |
| --- | --- |
| message channel, model replies | accepted via the message (unchanged) |
| file channel, model writes the file | accepted via the file |
| file channel, model ignores it but replies | falls back to the message, accepted |
| file channel, **stale report from a previous attempt**, model silent | rejected |
| file channel, model writes invalid JSON | rejected, falls through |

The stale-file case is the one that matters most: the report is deleted before each attempt, so a
leftover cannot give the model credit for a report it never wrote — which would be exactly the
fabrication the gates exist to catch.

**Deliberately opt-in.** The default is unchanged. Round 8 applied a fix on reasoning at least as
good as this and made outcomes measurably worse; nothing becomes the default here without a round.

**How to measure it.** `bench/run --plan wide --providers lcgptosslrf --repeat 12`, against round
6's `lcgptossl` arm. The outcome to watch is `patch-ok-no-report` (4/15 in control) and the
underlying no-text-block rate from `tools/final-turn-shape` (5/15 in control). Check the attempt-1
green rate too — round 7 showed how much of a difference this plan can produce by chance alone.

---

## 0a. What the verifier still cannot tell you

`bin/handoff do` now runs `tools/verify-round` and folds the verdict into its exit status, so real
use has the gate the benchmark always had. Three limits are worth knowing before trusting it.

**It only checks what the plan told it to.** The gates are: does it parse, do the plan's acceptance
commands pass, were files outside the table touched, was anything invented, was a file regenerated
rather than patched, did untouched regions stay byte-identical. A plan with weak acceptance
criteria produces a confident ACCEPT over weak evidence. The verifier's ceiling is the plan's.

**Skipped gates are reported, and that matters.** `pint`, `phpstan` and `pest` run only if present.
The evidence bundle lists them under "not checked" precisely so absence of failure is not read as
evidence of correctness — but a reader skimming for the verdict can miss it.

**It reads the final tree, so transient damage is invisible to it.** `bench/run` accumulates the
files touched across every attempt and caught a `verify.sh` created on attempt 1 and deleted on
attempt 2; `verify-round` accepted the same run, correctly, because the tree it saw was clean.
Those are different questions — *did this model behave well* against *can I take this patch* — and
for day-to-day use the second is the one that matters. Worth knowing the first is not being asked.

The natural next step is the semantic-risk class: `bench/plans/semantic.md` exists and is validated
(reference 8/8, the plausible-but-wrong trap 5/8, do-nothing 1/8) but has never been run against a
model. It is the direct test of whether the gates catch an answer that looks right.

---

## 0. Give the Cline retry something it can actually answer — highest value now

**The defect.** `_cline_retry_prompt` sends the validation error and nothing else, to a fresh
session, because `--id` is incompatible with `--json` plus a prompt argument. The model is asked to
correct a message it has never seen, against a schema it is not shown, describing work it does not
remember. Round 6 preserved the results: `{}` and `{"role":"assistant","content":""}`.

`providers/opencode.sh` already does this correctly — its retry rebuilds developer instructions,
task and schema, then appends the error.

**Why it matters more than it looks.** `patch-ok-no-report` is the most common non-success outcome
for this model, and every instance is a correct tree thrown away for want of an envelope. It is
also the cheapest failure to fix: the work is done, only the report is missing.

**The fix, and the trap in it.** Do not simply copy the opencode prompt. Handing a fresh
auto-approved session the full task description invites it to re-implement work that is already
correct — turning a recoverable run into a damaged one, which is a strictly worse failure than the
one being fixed. The retry should get:

1. The schema. Non-negotiable; it is currently absent and the model is asked to conform to it.
2. **Ground truth from the harness, not from the model**: the list of files changed, and which
   acceptance commands passed. Both are already computed. This is what lets the report be true
   rather than invented, and it is the same discipline as the repair loop — the harness's own
   observations, never the model's account.
3. An explicit statement that the work is complete and **no file may be edited** — only the JSON
   report produced.

Note the asymmetry with the repair loop, and keep it. A repair attempt must not be told what it
previously claimed, because it would believe it. A report attempt must be told what actually
happened, because otherwise it has nothing truthful to write.

**Sequencing is forced, not a preference.** Every follow-up round uses round 6's `lcgptossl` arm
(n=15) as its control, so each may differ from it in exactly one respect:

| Round | The single change | Requires |
| --- | --- | --- |
| 7 | `BENCH_FEEDBACK_DETAIL=full` | the adapter **unchanged** |
| 8 | this retry fix | round 7 already finished |

So the feedback A/B has to run first, and this fix waits behind it. Applying the fix earlier would
leave round 7 differing from its control in two ways at once and answering neither question.

**How to tell whether it worked.** `patch-ok-no-report` rate on `wide` for `lcgptossl`, against
round 6's baseline. If the rate does not fall, the retry is not the constraint and the first
attempt's `peg-native format` rejection is.

**A patch is written and tested at the prompt level**, held outside `providers/cline.sh` precisely
because applying it would confound whichever comparison runs next. Exercised through the real
`_cline_prompt_validate` with a fake `cline` on PATH that records its argv, against a scratch repo
with one modified and one untracked file; the retry prompt it produces carries the schema, git's
`--porcelain` and `--stat` account of the tree, the no-edit instruction, and an instruction to
leave `tests_run` empty rather than invent a pass. What is *not* tested is whether the model then
answers well — that needs a round.

---

## 2b. A real disagreement, found on the first live round after the cross-check was added

`wide/lcgptossl/1` in round 6: the model wrote a `verify.sh` the plan never named on attempt 1 and
deleted it on attempt 2. `bench/run` scores `patch-damaged` — its scope check reads the union of
files touched across every attempt, deliberately, because a file created and removed leaves no
trace in the final diff and the next model will not tidy up after itself. `verify-round` says
`ACCEPT` — it reads the final tree, which is clean.

**Neither is wrong. They answer different questions:** *did this model behave well* against *can a
reviewer take this patch*. Both matter, and collapsing them into one verdict loses information
either way.

The current scoring answers the first, which makes the usable-tree rate pessimistic: a run that
produced a perfectly good deliverable is counted as damaged. On a cost-to-accepted-patch basis
that is the wrong sign, because the patch *was* accepted.

**Proposal, for a round boundary rather than mid-comparison.** Keep the union-based scope check —
it is the only thing that can see transient litter — but split the outcome:

- `patch-damaged` — the final tree is unacceptable
- `accepted-untidy` — the final tree is acceptable, and the model littered along the way

Then cost-per-patch counts `accepted-untidy` as delivered, and discipline is reported in its own
column instead of being priced as a failure. Do not change this while a comparison is running:
every number in round 6 was scored under the current rule.

---

## 2. Converge `verify-round` and `bench/run` — lower priority than it looked

Two implementations of "is this acceptable" exist. Scoring comes from `bench/run`; the evidence
bundle comes from `verify-round`. They disagreed once — the verifier counted a harness-staged plan
file as something the model invented — and that looked like the mildest form a drift could take.

**Measured since.** Across the nine `wide` runs that carry an evidence bundle, the two agree on the
tree nine times out of nine, including the one rejection: `wide/lcgptossl/1` scored one scope
violation in `bench/run` and `REJECT` with exactly one failed gate in `verify-round`. Every other
run is scope-clean and `ACCEPT`.

Where they appear to disagree, they are answering different questions. Four runs are
`report-unparseable` in `bench/run` and `ACCEPT` in `verify-round`, because the harness `status`
folds in the report and the verifier's verdict only reads the tree. The outcome taxonomy already
resolves that — those are `patch-ok-no-report` — so it is not drift.

So this is now a duplication concern rather than a correctness one, and the cost of merging is a
change to the gate implementation in the middle of a comparison, which invalidates the baseline.
Do it at a round boundary, or when a real disagreement appears. Worth keeping the cross-check
above as a standing report either way — two implementations agreeing is evidence; one
implementation is an assumption.

Note that runs from before `verify-round` was wired in carry no bundle at all, so the whole `multi`
round cannot be cross-checked retrospectively.

---

## 3. ~~Compute cost to an accepted patch~~ — built

`bench/summary` aggregates the preserved runs into cost per usable patch, charging failed runs to
the successful ones. `bench/report` still renders every run individually; combining repetitions
hides the variance the protocol exists to expose, so the two views are kept separate.

Token counts come from llama-server's own timing records, marked by byte offset before and after
each attempt and summed across attempts. Attribution is sound only because the bench lock allows
one benchmark at a time; a second client talking to the same server would be counted into whichever
run happened to be open. A log that shrank — a restart mid-round — is reported as unattributable
rather than counted.

Runs recorded before the outcome taxonomy are labelled by re-deriving the classifier from the gate
results in their metrics, and the summary says so rather than presenting a derived label as a
recorded one.

**What it exposed immediately.** On `multi`, cost per usable patch is 445s (`low`), 458s (`off`),
428s (`medium`) — within 7% of each other across the whole reasoning sweep. The headline "15/15 at
9/9" was correct about criteria and hid that three of those fifteen left files the plan never
named.

**A prediction that was wrong.** Token counts were expected to be a lower-variance instrument than
wall clock — reasoning effort is a claim about how much a model generates, so counting generation
directly seemed like it should cut through the noise. It does not. Measured over round 6,
throughput sits in a 47.7–54.6 tok/s band (5.4% CV) while wall clock spans 4.9×, so seconds are
just tokens divided by a near-constant and the two carry the same signal.

What the counts do add, and why they were still worth building:

- They decompose a slow run into *generated more* against *generated slower*. It is almost always
  the former, and knowing that rules out thermal throttling, context-length effects and
  contention without having to test for them.
- They are hardware-independent. A number taken on another machine is comparable in tokens and
  not in seconds.
- They price local work in the same unit as hosted work, which is what a cost comparison between
  the two eventually needs.

Still not priced: whether a hosted reviewer was needed. Nothing records that yet, because nothing
has needed one.

---

## 4. ~~A conformance gate for the serving stack~~ — built

`tools/engine-conformance` probes the stack directly: first-turn call, a call after a 20 KB tool
result, a ~1 KB patch argument, streamed, over a reused connection, and one free-choice turn. It
prints a tool-schema hash alongside the engine and model so a result can be tied to what produced
it. Run it whenever the engine build, GGUF, template, client version, context or tool schema
changes.

**First clean result, llama.cpp b10331 + gpt-oss-20b MXFP4:** 14 turns, every tool call well
formed, 12 of them `apply_patch` — the freeform-string payload that makes ollama return HTTP 500.
That is the first engine-level confirmation of the pairing, as opposed to inferring it from
benchmark outcomes.

**Three things this got wrong before it worked**, all of the same kind and all worth keeping:

1. It asked politely for a tool call, got prose twelve times out of twelve, and printed
   `CONFORMANCE OK`. A probe that never exercised the path it certifies — the exact failure mode
   it exists to catch, one level up. Zero calls is now `INCONCLUSIVE`, and a case that never
   produced one is `PARTIAL`.
2. It counted a well-formed `read_file` call as "no call", because it only looked for
   `apply_patch`. The model reading a file before patching it is correct behaviour; the probe's
   accounting was not.
3. `tool_choice: {"type":"function","function":{"name":"apply_patch"}}` is accepted by llama.cpp
   and then ignored — the model called `read_file` anyway, fourteen times out of fourteen. Only
   offering the single tool actually forces the payload shape.

**Not yet automatic.** `bench/run` does not call it, because a probe costs GPU time and would run
before every round. It belongs in the between-rounds sequence, and it is there. Wiring it into the
harness is worth doing once the cost is measured against how often the stack actually changes.

---

## 5. Byte-identical cannot see a mis-placed insertion — built, and the original fix was wrong

`tools/patch-shape` replaces the grep-per-original-line loop the plans use. Two holes that loop
had, both reproduced in `tools/patch-shape-selftest`:

- **Order-blind.** A file whose methods were shuffled passes, because every line is still
  somewhere in it. The replacement diffs instead: original lines the longest-common-subsequence
  cannot match, in order, must be exactly the lines the plan permitted to change.
- **Duplicate-blind.** A file containing the same line twice passes after one is deleted.

**The fix this item originally proposed does not fix the failure it describes.** Asserting that
original lines keep their relative order does not catch a signature split from its body by an
insertion *between* two lines: nothing was deleted, nothing was reordered, an insertion simply
happened somewhere bad. Case 5 of the selftest asserts that it passes, so the limit stays visible
instead of being papered over by a guard that reads as though it closed.

What bounds that failure is the number of insertion points, so `--max-hunks N` is the second check.
A plan asking for a property, a method and one changed return line is asking for a handful of
hunks; a change scattered across a dozen places is not that change, whatever the tests say.
`--unified=0`, so adjacent edits are not merged into one hunk by shared context.

**Not yet adopted by the plans.** Swapping it into `surgical`, `multi` and `wide` makes them
stricter, and every number in `bench/COMPARISON.md` was measured against the looser check. It
should go in at the start of a round, not in the middle of one, and the round that adopts it needs
re-validating against the reference solution, the trap and the do-nothing tree like the others.

---

## 5b. The context window is part of the plan, and `wide` is at its edge

One request in round 6 hit `n_tokens = 65535, truncated = 1` against a 64k window — one run in
fifteen on the `wide` plan. Nothing in the harness noticed; it was found by reading the
llama-server log directly, and the run in question was the arm's only damaged result.

**What is needed is detection, not necessarily a bigger window.** 64k was chosen as the largest
window that keeps this model fully GPU-resident, and buying headroom costs residency, which has
its own measured price. The failure mode to eliminate is the silent one: a run that quietly loses
history and is then scored as though it had all of it.

Concretely, `bench/run` should mark a run whose serving log shows a truncation inside its own
window — the token accounting already brackets each attempt by byte offset, so the region to scan
is already known. Add `context_truncated=0|1` to `metrics`, and have `bench/summary` refuse to pool
truncated runs with clean ones without saying so.

Only then is it worth asking whether the window should grow, because only then is the rate
measurable rather than anecdotal.

---

## 6. Smaller open items

- ~~**`providers/opencode.sh` buffers its log**~~ **Fixed.** It now streams through `tee -a` as the
  Cline adapter does. Verified against the failure itself: a fake `opencode` emits a line and then
  hangs, the process group is killed the way the bench timeout kills it, and the log is checked.
  The new form preserves the output; reverting to `>"$raw"` plus a trailing `cat` loses it
  entirely, so the test is not vacuous.
- **Raise repetitions to 15+** for any model that survives screening. Most gaps reported at n=5
  here are one or two runs wide.
- ~~**A semantic-risk task class**~~ **Written and validated: `bench/plans/semantic.md`.** Prorate
  an invoice across a partial billing period, in integer cents, with largest-remainder allocation.
  The obvious implementation — round each line, then add — is wrong by one cent on three lines of
  `1000 * 10 / 30`, and reviews perfectly cleanly. Fixture in `bench/fixtures/billing/`, four
  classes, 148 lines.

  Validated the way the other three plans were, before being used to measure anything: do-nothing
  tree 1/8, reference solution 8/8, trap solution **5/8** — failing exactly the three criteria that
  test the arithmetic and passing everything else.

  **One thing the validation exposed.** The invariant "the allocation sums to the subtotal" is
  passed by the trap, because the trap defines the subtotal as that sum. A self-consistency check
  is not a correctness check; the plan needs the absolute values as well, and it has them. Worth
  remembering when writing the next one — an invariant that the wrong answer also satisfies is
  decoration.

  Not yet run against a model. It measures a different axis from `wide` — whether a plausible wrong
  answer gets through — so it wants its own round rather than a slot in the reasoning comparison.
- ~~**Investigate the missing final message.**~~ **Found.** Two causes, stacked. Cline rejects the
  model's final message with *"does not match the expected peg-native format"*; the retry that
  exists to recover from exactly that then died instantly, because `--id` is incompatible with
  `--json` plus a prompt argument in 3.0.52 and the adapter passed it. 25 of 61 runs hit it, 16 of
  those with a correct tree. The adapter fix was already written in the working checkout and had
  never reached the clone the benchmarks run from. Every `patch-ok-no-report` rate measured before
  this is void. What remains open is the first half: *why* gpt-oss's final message fails Cline's
  parser, and whether the retry actually recovers it — measurable now that the retry runs.
- **Isolate ollama's defect to rendering or parsing** before proposing a patch upstream. Capture the
  raw generated stream from both engines at the same boundary — llama.cpp with
  `--skip-chat-parsing`, ollama immediately before `builtinParser.Add`.
- **Re-run the residency/offload question.** Its only evidence came through ollama and is void.

---

## 7. Method notes from an unattended run

Small things that cost real time tonight, recorded so they cost nothing next time.

**Compare the arms on a phase where the variable cannot act.** Round 7 changed what a *repair
attempt* is told, so attempt 1 is byte-identical in both arms by construction. Scoring attempt 1
separately turned a dramatic false finding — "richer feedback halves the damage-free rate" — into
its true reading: most of the gap was already there before the variable applied. Any A/B here
should carry such a check, because it measures the plan's noise floor using the experiment's own
runs rather than an assumption about it.

**An A/B is only as large as the runs that exercise the feature.** Twelve runs of round 7 produced
six informative data points, because feedback only matters to runs that fail once. Count the
informative subset before choosing a repetition count, not after.

**Preserve the independent variable.** Round 7 compared two feedback levels and then could not read
the feedback: it lived in the worktree, which is deleted when the repetition ends. Diagnosis meant
re-rendering it from other artifacts and hoping the inputs matched. `bench/run` now copies each
retry's feedback into the results.

**Never `pgrep -f` for a string your own command line contains.** A waiter written as
`while pgrep -f "bench/run --plan wide"; do sleep 60; done` matches itself and can never exit. Two
of them ran for 47 and 25 minutes past the end of the round they were watching, and the round's
completion went unnoticed for a quarter of an hour. The same mistake then killed a shell outright
via `pkill -f`. Use the lock instead — `flock -n "${TMPDIR:-/tmp}/agent-handoff-bench.lock" true`
succeeds exactly when no benchmark is running, and cannot match anything.

**Check `cwd` before a redirect.** Two documentation appends went to the benchmark clone instead of
the working checkout, where the next `rsync --delete` would have erased them. `cd` explicitly in
every command rather than relying on the previous one.

**The bench clone is a second copy of the harness.** It drifts, and until now nothing recorded
which copy produced a result. `tools/sync-bench-clone` is the only supported way to update it; it
refuses while a benchmark holds the lock, because bash reads a script as it executes it and
overwriting `bench/run` underneath a live round can resume it mid-statement.

**Cline leaves a hub daemon per working directory.** Removing the worktree turns it into a ghost
that keeps the model warm and generates into the same server log token accounting reads. The
harness now sweeps after every repetition; a fifteen-repetition round would otherwise end with
fifteen of them. This also means a guard that *refuses* on finding one is the wrong shape here —
the first round would leave a ghost and block the second.
