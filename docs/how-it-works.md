# How it works

The shape of the system, why each boundary exists, and which parts are load-bearing. Written for
someone picking this up cold — including me in six months.

---

## The idea

A hosted model is good at deciding what to build and at judging whether it was built correctly. It
is expensive to use for typing. A local model is free to run and fast enough, but cannot be
trusted to report on its own work.

So the hosted model writes a specification and reviews evidence; a local model does the work; and
a harness — not the model — decides whether the result is acceptable.

```
  hosted model
      │  writes a plan: exact steps, scope contract, acceptance criteria
      ▼
  agent-handoff harness
      ├── isolated git worktree from a fixed commit
      ├── operational rules (short, task-independent)
      ├── client tool loop  ──► serving engine ──► local model
      ├── gates: syntax, scope, litter, patch-only, acceptance commands
      ├── repair loop, capped, fed the failing commands
      └── evidence bundle: every claim tied to a command and its exit code
      ▼
  hosted model
         reads evidence, accepts or rejects, owns the commit
```

The hosted model never sees the implementer's own report. It reads evidence the harness produced.

---

## The four layers, kept apart on purpose

1. **Benchmark findings** (`docs/local-models.md`, `bench/COMPARISON.md`) — for the maintainer.
   Never shown to a model under test. Telling a model which mistakes it is expected to make
   contaminates the measurement.
2. **Operational rules** (`templates/agent-rules.md`) — short, task-independent, sent as developer
   instructions. Only the rule headings travel; the rationale table stays behind.
3. **The plan** — the task, and only the task. Exact signatures, a scope contract, acceptance
   criteria that each map to one executable command.
4. **The evidence** — what comes back. Commands, exit codes, digests.

---

## Why the plan has that shape

A plan is executable data, not prose. Three sections are parsed:

| Section | Parsed into | Enforced as |
| --- | --- | --- |
| `## Files to touch` | allowed-path list | scope and litter gates |
| `## Acceptance criteria` | the score denominator | one checklist item per command |
| `## Verification` | the score numerator | commands run against the tree |

`bench/run` refuses a plan whose checklist and command counts disagree. That is not pedantry:
`surgical-discount` shipped with six criteria and two commands, making 2/6 unreachable by
construction, and every model measured on it was understated until someone noticed.

**Difficulty means more work, not more decisions.** The implementer executes a specification; it
does not design. A harder plan has more files and more tool calls, not more ambiguity.

---

## The gates, and the failure each one exists for

Every gate was added after something specific went wrong. None are speculative.

| Gate | The failure it caught |
| --- | --- |
| syntax | A migration written as one line of literal `\n` characters, reported as complete |
| empty diff scores zero | Two fabricated successes scoring a middling `complete 1/6` |
| `false-success` label | `status: complete` with invented file paths over an untouched tree |
| patch-only | A 421-line service replaced by an 11-line fragment whose code was correct and whose destination was not |
| scope | Files changed that the plan never named |
| litter | Files *invented* — including one created and deleted across attempts, invisible in the final diff |
| byte-identical regions | A correct patch that deleted the declaration next to its insertion point, passing every functional test |
| criteria/command parity | A plan that capped every model below its real score |

**The report is never an input.** Status, summary and `files_changed` are recorded as untrusted
metadata and scored separately.

Two further checks exist as tools the plans do not yet use, because adopting them mid-comparison
would change what every earlier number meant:

| Check | The hole it closes |
| --- | --- |
| `tools/patch-shape` order check | The grep-per-line version the plans use is order-blind and duplicate-blind: a file whose methods were shuffled passes, and so does one that lost one of two identical lines |
| `tools/patch-shape --max-hunks` | A change scattered across a dozen insertion points is not the contained change the plan asked for |

Order-preservation does **not** catch a signature split from its body by an insertion between two
lines — nothing is deleted and nothing is reordered. That was the failure the check was originally
proposed for, and case 5 of `tools/patch-shape-selftest` asserts that it still passes, so the limit
stays visible rather than hidden behind a guard that reads as closed. The hunk bound is what
constrains it.

---

## Who decides what "verified" means

The plan does, and the plan is written by the hosted model. The harness runs the checks and proves
it ran them; it does not hold opinions of its own about whether the work is good.

| | Decides the verdict | Reported, not decisive |
| --- | --- | --- |
| `verify-round` | the plan's acceptance commands, plus scope | syntax, patch-only, style, static analysis, test suite |

**That split is measured.** Across 68 preserved evidence bundles, the harness's own gates caught
exactly one thing the plan's commands had not already caught, and it was scope. `syntax` fired
three times and `patch-only` twice — never once alone, because the plans express both as acceptance
commands. `tree-changed` never fired at all. Gates that never decide anything were still deciding
whether a round was rejected.

Advisory findings are not noise; they are what a reviewer reads to decide whether an accepted patch
is one they actually want. They simply do not get a vote.

The reason to keep the harness thin is the record in `docs/local-models.md`: nearly every confident
wrong conclusion in this project came from harness behaviour nobody had measured. Every opinion the
verifier holds is another thing that can be wrong in a way that looks like a model result — and it
competes with the judgement of the model that wrote the plan and will review the diff.

**Two rounds tested the opposite direction and both failed.** Round 7 gave the implementer a richer
account of its failure; round 8 gave it ground truth about the tree so it could report honestly.
Neither improved anything and round 8 actively damaged trees — a retry told not to edit any file
edited files. The local model implements a specification well and does everything adjacent to
self-assessment badly. Give it less to judge, not better material for judging.

---

## Deciding whether a difference is real

`bench/compare <plan> <control> <arm>` runs the comparison and the check that matters more than
the comparison.

**The attempt-1 control.** For a variable that only acts on repair — feedback detail, retry
content — the two arms are byte-identical on their first attempt by construction. Any difference
there is the plan's noise floor, measured from the experiment's own runs. `bench/compare` prints
it in percentage points beside the headline gap and refuses to let the headline stand when the
noise accounts for most of it.

Round 7 is why. Its arms differed by 27 points on usable trees, and 20 of those points were
already present at attempt 1. Reported without the control, "richer feedback halves the
damage-free rate" would have gone into this document as a finding.

**Significance is the wrong test for the control**, and using it gave false reassurance the first
time. That 20-point gap sits at p = 0.36 — comfortably "not significant" — and was still three
quarters of the result. What matters is not whether the noise floor is statistically distinguishable
but whether it is large enough to account for the finding.

**`--acts-on first-attempt` when the variable acts earlier** — a reasoning level, a sampling
change, a model or engine swap, an adapter retry that fires inside the first attempt. Then attempt 1
is a result, not a control, and the tool says so instead of issuing a warning that does not apply.
It cannot infer this and deliberately does not guess.

Fisher exact for the proportions, Mann-Whitney with tie correction for seconds and tokens. Nothing
rests on a distributional assumption these sample sizes cannot support, and `chance` is printed to
mean *this data cannot distinguish the arms* — never *the arms are the same*.

---

## What a run costs

`bench/report` renders every run separately, on purpose: combining repetitions hides the variance
this protocol exists to expose. `bench/summary` is the other view — cost per usable patch, charging
the failed runs to the successful ones.

That division is the point. "5/5 correct" reads as uniform when one of the five cost 5.7× the
others, and a configuration that succeeds four times in five while burning three attempts each time
is not cheaper than one that succeeds three times in five on the first attempt.

Token counts come from llama-server's own timing records — marked by byte offset before and after
each attempt, summed across attempts. The attribution holds only because the bench lock allows one
benchmark at a time; a second client on the same server would be counted into whichever run was
open. A log that shrank mid-round is reported as unattributable rather than counted, because a
plausible wrong number is worse than an absent one.

---

## The repair loop

Up to three attempts. After each, the harness runs the acceptance commands and, on failure, hands
back **its own list of commands that exited non-zero** — not the model's opinion of what went
wrong.

It works: a run that broke the fixture on attempt 1 and littered on attempt 2 came out correct on
attempt 3. It is also expensive — that run cost 1048s and 180 tool calls against a 182s median.
Which is why first-pass rate and time-to-green are different numbers and both matter.

How much the retry is told is switchable, because it is a hypothesis rather than a known
improvement:

| `BENCH_FEEDBACK_DETAIL` | The retry receives |
| --- | --- |
| `commands` (default) | The failing command lines. Every measurement so far was taken this way |
| `full` | Also the captured output per failure, and the diff of what it actually changed |

The model's own previous report is never included under either setting. It is the least reliable
artifact in a run, and quoting it back invites the model to believe its earlier claims about work
it did not do. The diff is framed as evidence rather than instruction — *this is what you did, as
opposed to what you believe you did* — and explicitly does not have to be kept, so a model cannot
read it as a mandate to defend a broken approach.

An adapter can pin its own level with `provider_feedback_detail`, and the pin beats the
environment. That exists so an A/B arm named for a condition cannot quietly run under the other
one when someone forgets an environment variable — a label that can disagree with the behaviour it
names is worse than no label, because it gets believed.

The case for caution: reasoning at `medium` already made this model write its own verification
scripts instead of running the plan's, and a richer failure narrative pushes the same way. Until
attempts-to-green is measured for `full` against `commands`, the default stays where the evidence
is.

---

## The serving stack is part of the result

The engine is a gate, discovered late and the hard way.

The same official gpt-oss weights scored **1/3 through ollama** and **4/4 through llama.cpp**,
then 15/15 on a four-file architectural task. Ollama's harmony path returns HTTP 500 for tool calls
its own model generated (`tools/repro-ollama-toolcall-500.py`), and the error surfaces through the
client, so it reads as a client bug. It cost a long investigation in which four confident
explanations were measured and discarded.

Consequently every result records its stack in `manifest.json`: engine and build, model-file
digest, context, KV type, GPU layers, client and version, reasoning level. Without it, "gpt-oss"
names several stacks that behave differently and the next provider regression gets blamed on the
model.

**Known-good pairing today:**

```
gpt-oss-20b (ggml-org MXFP4)  →  llama.cpp b10331, --jinja, 64k, q8_0 KV, all layers
                              →  Cline, openai-compatible provider
                              →  agent-handoff worktree + gates + evidence
```

`tools/llamacpp-serve start|stop|status` pins it; the adapter refuses to run if the server is
serving a different model, because one card holds one model and a leftover server would silently
benchmark the wrong weights.

---

## The verificator

`tools/verify-round <worktree> <plan> <base-commit>` produces `evidence.json` and `evidence.md`:
every gate with its command, exit code, an output excerpt and a sha256 of the full log — plus an
explicit list of gates that **did not run**, under the heading that absence of a failure there is
not evidence of correctness. Silent non-coverage is how a verifier turns missing evidence into
apparent proof.

It runs the project's own tooling — pint, phpstan, the test suite — only when already present.
A verifier that installs things to verify them is not a verifier.

> **Open:** `verify-round` and `bench/run` both implement "is this acceptable". Scoring still comes
> from `bench/run`. Two implementations will drift — they already disagreed once, and the verifier
> was wrong, counting a harness-staged plan file as something the model invented.

---

## Running things

```bash
tools/llamacpp-serve start gpt-oss-20b 65536      # pin the serving stack
tools/engine-conformance --engine llamacpp        # is the stack emitting usable tool calls?
bench/run --plan wide --providers lcgptossl --repeat 5 --force
bench/report                                       # every run individually, no aggregate score
bench/summary                                      # cost per usable patch, failures included
tools/verify-round <worktree> <plan> <base>        # evidence bundle on demand
```

Run `tools/engine-conformance` whenever the engine build, GGUF, chat template, client version,
context size or tool schema changes. A benchmark cannot tell an engine regression from a model
regression; that probe can, and not having it is what made every ollama-served gpt-oss result void.

The harness has its own tests, none of which need a GPU:

```bash
tools/selftest-all            # all of the below, plus the plan-parser agreement check
tools/smoke-e2e               # the whole journey, and the state each step leaves behind
tools/harness-selftest        # bench/run end to end, against a provider that runs no model
tools/verifier-selftest       # verify-round and bin/handoff — what real use touches
tools/feedback-selftest       # what a repair attempt is told
tools/patch-shape-selftest    # the order and hunk-count checks
tools/shim-selftest           # the tool-call shim
```

The split is worth understanding, because it maps onto where the bugs actually were. The
`*-selftest` suites test units. `smoke-e2e` tests that the units are still connected to each
other — which is where three of the defects users hit lived: a verifier looked up under the user's
repo instead of the harness (so verification silently skipped for every real user while the
benchmark kept working), a `resume` that did not verify and exited 0 regardless, and a template
that taught a heading the parser does not read. None of those were visible from inside a unit.

Plan slugs are short, ideally one word: a long hyphenated slug was mis-transcribed with
underscores and reported as a missing file.

---

## The rule that matters most

**A run blocked by the harness, the adapter, the configuration or the machine is void.** Not a
model result, not scored, re-run after fixing the cause.

The test: *could a different harness, configuration or machine have produced a different outcome
for the same model and prompt?* If yes, void it.

Nine harness defects have been found here, and most of the confident conclusions in this project's
history turned out to be one of them. The rule is what keeps the record honest.
