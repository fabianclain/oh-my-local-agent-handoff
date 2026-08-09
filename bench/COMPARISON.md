# Local model comparison

Five models, the same plan, three rounds. Each attempt runs in its own detached git worktree from
the same commit, so no provider inherits another's edits. Between rounds the pipeline is changed
and the change is recorded, so improvements are attributable rather than assumed.

Hardware: RTX 5060 Ti, 16 GB. Desktop (Xorg + Chrome) holds ~1.6–2.2 GB, leaving ~14.4 GB.
Ollama is configured with `OLLAMA_FLASH_ATTENTION=1`, `OLLAMA_KV_CACHE_TYPE=q8_0`,
`OLLAMA_MAX_LOADED_MODELS=1`.

## Residency at 32k context — measured before any round

Every model was baked to a 32,768-token window with `PARAMETER num_ctx` and loaded once.

| Model | Weights | Footprint @32k | Residency | GPU free after load |
| --- | ---: | ---: | --- | ---: |
| gemma4:12b-128k | 7.6 GB | 8.1 GB | **100% GPU** | 5,851 MiB |
| qwen2.5-coder:14b | 9.0 GB | 12 GB | **100% GPU** | 2,533 MiB |
| Devstral Q3_K_S | 11 GB | 13 GB | 7%/93% CPU/GPU | 1,129 MiB |
| Devstral UD-Q3_K_XL | 12 GB | 15 GB | 15%/85% | 1,009 MiB |
| Devstral Q4 (small-2) | 15 GB | 18 GB | 31%/69% | 1,216 MiB |

`q8_0` KV cache is doing real work: UD-Q3_K_XL's footprint fell from 17 GB to 15 GB, and
Q3_K_S now reaches 93% where nothing above 12 GB of weights previously got past 85%.

**Why residency matters more than it sounds.** A 15% layer offload previously cost not 15% of
throughput but effectively everything: Devstral at 85% spent 101 minutes on a real edit task and
wrote zero files, with `llama-server` at 550% CPU throughout. It was computing, not hung. Every
token waits on the CPU-resident layers, and an editing task pays that across a much larger prompt
than a greenfield one.

**Superseded in round 5.** gpt-oss at 84% residency produced a byte-perfect patch in 60s, so
this is not a general law. A partial offload costs throughput roughly in proportion to the
layers moved (61 -> 43 tok/s measured); Devstral's collapse was specific to that model or
that task shape. See "Residency: the rule was too strong" below.

## Pipeline changes between rounds

### Before round 1

**Context is now baked and registered for every model.** Previously `qwen2.5-coder:14b` was
registered with no `limit`, so Ollama served it at the default 4,096 tokens. It returned "the
plan file does not exist" in 18 seconds, twice, and that was recorded as a fabricated blocker.
With a 4k window the developer instructions, the output schema and the plan reference plausibly
did not fit — so it may have been reporting honestly that it could not see the plan.

That earlier verdict is therefore withdrawn pending a fair retest at 32k. The general lesson is
the pipeline's, not the model's: **a model served at a default context will fail in ways that
look like dishonesty**, and the harness should never leave that to chance.


## Rule: a run blocked by the harness or the environment does not count

A benchmark measures the model. If a run failed because of a defect in the harness, the adapter,
the configuration or the machine, it is **void** — not a model result, and not scored.

This is not generosity. Counting harness faults as model faults produces confident conclusions
that are simply wrong, and every one of them here would have been.

**Void under this rule, with what actually caused them:**

| Run | Recorded as | Actual cause |
| --- | --- | --- |
| qwen2.5-coder, "plan file does not exist", 18s, twice | fabricated blocker | served at ollama's default **4,096** context; the instructions, schema and plan reference plausibly did not fit |
| gemma, 31 minutes, 0-byte log | stalled/slow model | `opencode run` blocked on stdin, which never reached EOF in a background shell |
| round 1: gemma, qwen, dvq3s | no result | `bench/run --force` deleted the whole plan directory, wiping each provider as the next ran |

Three of the harshest judgements made in this comparison were harness defects. The qwen one is
the worst: it was written up as the most dangerous failure mode seen — a model inventing a
blocker — when the likeliest explanation is that it honestly could not see the plan.

**Still counted, because the cause was real:**

- Devstral truncating before writing a report at 16k. The context ceiling came from a hardware
  constraint, not a bug. It is recorded as a *configuration* result rather than a verdict on the
  model, and it changes if the configuration changes.
- Gemma writing a service class's content into the wrong file, and reporting success for a
  migration that could not parse. Nothing in the harness caused either.

**Practical test when a run fails:** could a different harness, config or machine have produced a
different outcome for the same model and prompt? If yes, void it and fix the harness first.


### The qwen2.5-coder result is void — proven, not assumed

Qwen was recorded twice as reporting "the plan file does not exist", and that was written up as
the most dangerous failure mode observed: a model inventing a blocker. It was neither dishonest
nor incapable.

Probed directly — a file on disk, a prompt asking it to read that file and echo a marker — it
replied:

```json
{
  "name": "read",
  "arguments": { "filePath": ".handoff/plans/probe.md" }
}
```

wrapped in a markdown code fence, as **plain text**. It knew the tool, the argument name and the
path. It simply did not emit a native tool call, so opencode never executed it, no file contents
ever returned, and the model correctly concluded it had no plan. Its report was accurate.

The cause is a template/parser mismatch between ollama's `qwen2.5-coder` chat template and
opencode's tool-call parsing — squarely a harness fault. All qwen results are void and removed.

`ollama show` listing `tools` is therefore **not sufficient** to establish usability. The
capability flag says the template claims tool support; it does not say the emitted format is one
the client can parse. Any new model needs a one-prompt read-a-file probe before it is benchmarked,
or its failures will be misattributed exactly like this.


### Engine swap does not fix text-format tool calls — tested, not assumed

Three models emit tool calls as fenced JSON text rather than as native calls, so opencode never
executes them: `qwen2.5-coder:14b` (qwen2), `JanusCoder-14B` (qwen3) and
`gemma-4-12B-coder-fable5` (gemma4). The last one matters: it kills the tidy "Qwen family"
explanation, because another gemma4 model works. **Tool-call support is per-build, decided by
whichever chat template that package ships — not per-architecture and not per-source.**

Two fixes were tested and both failed:

- **Newer ollama.** Reinstalled from ollama.com; `/usr/local/lib/ollama` was replaced and the
  service restarted, but client and server both still report 0.32.6 — it is already current, so
  there was nothing newer to get.
- **llama.cpp with `--jinja`.** Installed the Vulkan build (b10331) — it reaches the RTX 5060 Ti,
  loads at 32k with `-ctk/-ctv q8_0`, and serves an OpenAI-compatible API. Given JanusCoder's own
  HF GGUF, template embedded, it produced the *same* fenced JSON with `tool_calls` absent.

So the format is the model's, not the engine's. One caveat worth recording: ollama stores its
chat template as a **separate layer outside the GGUF**, so pointing llama.cpp at an
ollama-repackaged blob tests a template-stripped model. That invalidated a first attempt here and
would silently mislead anyone doing the same.

**Consequence:** these three models cannot drive this harness through either engine. The probe
that catches them costs about a minute and is the only reliable signal, since all three advertise
`tools`.


## Method changes for round 3 and beyond (owner's proposal, adopted)

Round 1 and 2 measure *capability on one trivial task*. That is the wrong target. The goal is
**reducing hosted-model usage**, so the metric is total cost to an accepted patch, not whether a
local model can produce code at all.

### Adopted

**Patch-only editing.** Give the local model `read_file` + `apply_patch`; block `write_file` on
tracked files at the harness level. The greenfield/edit split observed so far is a correlation,
not a mechanism — this isolates whether the weakness is editing *logic* or whole-file
*regeneration*. Evidence points at regeneration (a 421-line service replaced by an 11-line
fragment whose code was correct but whose destination was wrong), but that is inference. If
regeneration is the cause, patch-only tools make local edits viable immediately.

**Three task classes**, replacing the binary greenfield/edit split:
1. greenfield creation
2. surgical edits (1–10 lines)
3. architectural / multi-file edits

A model may be fine at the first two and hopeless at the third, which the current split cannot
express.

**Test-first delegation.** Hosted model writes or approves acceptance tests; the local model
iterates until green. This puts the expensive model on the part needing judgement and the free
one on the part needing iteration, and is the most promising token-saving structure available.

**Repair loops, capped at 3 attempts.** First-pass success is the wrong headline if success
within three attempts is high. Measure both.

**Scope contract enforced by the harness, not the prompt:** allowed paths, max changed files, max
new files, deletion permitted or not. Prompted constraints have already been ignored — a plan
stated the `SUM(clicks)/SUM(impressions)` rule explicitly and the wrong version shipped anyway.

**A semantic-risk task class:** aggregate SQL, statistics, permissions, auth, money, dates,
concurrency. These are dangerous because wrong output still parses and looks plausible, so they
need verification that checks *values*, not just that the code runs.

**Metrics:** first-pass success, success within 3 attempts, false-success rate, time-to-green,
and hosted verification tokens spent.

### Adopted with modification

**Repetitions:** 5 per task for screening rather than 10–20. At 1–20 minutes per run the larger
number is hours per model. Raise to 15+ only for a model that survives screening.

**Stop adding models.** Characterise one model's operating envelope under a good harness first.
Seven candidates were tested before any one was understood, and three of those turned out to be
blocked by a harness or template fault rather than by capability.

## A note on provider labels

Several labels named in the results below no longer exist as adapters: the Devstral quantisations
(`dvq3s`, `dvq3xl`, `dvq4`, `devstral`), the Qwen paths (`qwen`, `qw3c`), the gpt-oss Coding-Distill
(`gptossd`), and the ollama-served gpt-oss labels (`clgptossnt`, `clgptoss128nt`).

They were removed rather than kept, because each pointed at a model baked locally with
`ollama create` — `dv-q3s-32k`, `gptoss-128k` and so on — which exists on one machine and nowhere
else. They were never a reproduction path for anyone but the author, so keeping them made the
provider directory look like a menu when it was a scrapbook.

The findings they produced are unaffected and stay recorded here: Devstral changing zero bytes six
times while reporting success, the Qwen family emitting correct tool calls as text, the distill's
corrupted template. Recreating any of them is a two-line adapter over `providers/ollama.sh` plus
the matching `ollama create`.

## Results

### Round 1 — uniform 32k context, q8_0 KV

Plan: `mechanical-guided`. Voids removed (qwen: text-format tool calls).

| Provider | Status | Criteria | Seconds | Residency |
| --- | --- | ---: | ---: | --- |
| gemma | complete | **4/5** | 149 | 100% GPU |
| dvq3xl | report-unparseable | 0/5 | 85 | 85% |
| dvq3s | complete | 0/5 | 39 | 93% |
| dvq4 | did not finish | — | — | 69% |

**The result that needs explaining:** gemma scored **5/5 in 77s** on this same plan before the
KV cache was quantised and before its context was cut from 128k to 32k. It now scores 4/5 in
149s — slower and slightly worse. Two variables changed at once, which is a design mistake on my
part; round 2 separates them by restoring gemma's context while leaving KV alone.

Devstral's ordering is the reverse of what the earlier Q4-only run suggested: the *smallest*
build (Q3_K_S, 93% resident) finished fastest at 39s, and the larger ones did worse. Residency
continues to predict outcome better than quantisation quality does.

### Round 2 change: context sized per model, not uniform

Uniform 32k wasted headroom on one model and starved another. Measured at 32k, gemma used 8.1 GB
of 14.4 GB usable while Devstral Q3_K_S sat at 13 GB and 93% residency.

So context is now sized to land near 12–13 GB used, which means **up** for gemma (32k → 96k,
also restoring the window it had when it scored 5/5) and **down** for the Devstral builds
(32k → 16k, buying full residency at the cost of window). Given a 15% offload previously cost an
entire task, trading window for residency is the right direction for them.

### Round 3 — surgical edit on an existing 70-line class

Add a property, a setter, and change one line in `subtotal()`. Every other method must survive
byte-identical. The plan also sets a semantic trap: `total()` already builds on `subtotal()`, so
applying the discount again there double-counts it and still parses.

| Provider | Runs | Completed | Criteria | Files changed | Diff size |
| --- | ---: | ---: | ---: | ---: | --- |
| gemma @96k | 5 | 4 | 2/6 | **1 every run** | 808–934 B |
| Devstral Q3_K_S @32k | 3 | 3 | 1/6 | **0** | 0 B |
| Devstral UD-Q3_K_XL @32k | 3 | 0 | 1/6 | **0** | 0 B |

**Devstral did nothing, six times out of six**, and three of those runs reported `status:
complete`. One summary read:

> "Implemented surgical discount feature. Added discount calculation to order processing and
> updated API endpoints. All tests pass."

There is no order processing and there are no API endpoints in this task. The description is
invented, the tests were never run, and the tree is untouched. That is fabrication rather than
weakness, and it is the failure mode the whole verification discipline exists to catch.

Their 1/6 is also an artefact worth fixing: "the file parses" passes trivially on an unmodified
tree. **A criterion that passes when nothing changed inflates a do-nothing run**, and the bench
should score an empty diff as zero.

**Gemma is the only local model that does the work.** It patches rather than regenerates
(+8/−3 lines), it avoided the semantic trap on every run, and its one defect is mechanical: it
deletes the declaration adjacent to its insertion point. That is caught by a byte-identical check
on regions the plan did not name, which is now in the harness.

## Round 4 — the same surgical edit, with the harness gates that round 3 asked for

Four models, five repetitions each, on `surgical-discount`. Two of these models could not be
benchmarked at all before this round.

### Harness changes since round 3, and why each was made

| Change | Cause |
| --- | --- |
| Empty diff forces criteria to zero; `complete` over an untouched tree is recorded as `false-success` | Round 3's "the file parses" gave a do-nothing run 1/6 and put it above the floor |
| Patch-only gate: a tracked file losing over half its lines, or removing more lines than it had, is `rewrite_violations` | The greenfield/edit split needed a mechanism, not a correlation |
| A plan whose checklist and verification-command counts disagree is rejected | See below — this one invalidates a number quoted in round 3 |
| The plan is asserted readable in the worktree immediately before the run | "Plan file does not exist" has been both true and fabricated, and the worktree is deleted afterwards |
| `templates/agent-rules.md` sent as developer instructions | The owner's EDITING / COMPLETION rules, as a layer separate from the plan |
| Tool-call shim rewritten | Three defects; see the void section |

### Results

Criteria are shown as *executable* checks passed. `surgical-discount` has six checklist items and
only two commands, so 2/2 is a full pass — the raw artifacts record it as 2/6.

| Provider | Run | Status | Checks | Diff | Seconds | Collateral damage |
| --- | ---: | --- | ---: | ---: | ---: | --- |
| gemma @96k | 1 | complete | 2/2 | 936 B | 64 | deleted `$lines` declaration |
| gemma | 2 | complete | 2/2 | 698 B | 172 | — |
| gemma | 3 | complete | 2/2 | 1035 B | 57 | — |
| gemma | 4 | complete | 2/2 | 936 B | 55 | deleted `$lines` declaration |
| gemma | 5 | complete | 2/2 | 1075 B | 70 | deleted `$lines` declaration |
| gptoss:20b @32k | 1 | report-unparseable | 0/2 | 1286 B | 593 | **unmatched `}` — file does not parse** |
| gptoss | 2 | complete | 2/2 | 1086 B | 151 | merged new property onto the `$lines` line |
| gptoss | 3 | complete | 2/2 | 1023 B | 144 | — |
| gptoss | 4 | complete | 2/2 | 882 B | 131 | — |
| gptoss | 5 | complete | 2/2 | 932 B | 60 | — |
| qw3c Q2_K @32k | 1 | complete | 2/2 | 1085 B | 73 | — |
| qw3c | 2 | report-unparseable | 2/2 | 1085 B | 69 | edit correct; looped on a rejected `bash` call |
| qw3c | 3 | report-unparseable | 0/2 | 0 B | 56 | `edit` call truncated mid-object |
| qw3c | 4 | blocked | 0/2 | 0 B | 12 | **claimed the plan was missing, zero tool calls** |
| qw3c | 5 | report-missing | 0/2 | 0 B | 64 | read twice, produced nothing |
| gptossd (distill) | 1 | false-success | 0/2 | 0 B | 30 | **invented two file paths, zero tool calls** |
| gptossd | 2 | blocked | 0/2 | 0 B | 19 | read `./handoff` three times, never listed |
| gptossd | 3 | complete | 1/2 | 525 B | 34 | property added untyped, `subtotal()` never changed |
| gptossd | 4 | blocked | 0/2 | 0 B | 18 | one `glob`, then gave up |
| gptossd | 5 | false-success | 0/2 | 0 B | 12 | — |

### The metric that matters: a complete run whose diff is also clean

"Complete" counts a run that damaged an untouched line. Reading every diff by hand:

| Model | Complete | **Clean patch** | Median | Fabrications |
| --- | ---: | ---: | ---: | ---: |
| gptoss:20b | 4/5 | **3/5** | 144 s | 0 |
| gemma4:12b | **5/5** | 2/5 | 64 s | 0 |
| qw3c 30B-A3B Q2_K | 1/5 | 1/5 | 69 s | 1 |
| gptossd distill | 1/5 | 0/5 | 30 s | 2 |

**gpt-oss:20b writes the best patches measured in this project.** Three runs deleted exactly one
line — the line being changed — with correct typing, and it avoided the double-counting trap every
time. It costs roughly twice gemma's wall-clock, because harmony spends a long analysis channel
before acting, and it produced one file that did not parse. It never claimed success it had not
earned: run 1 failed loudly.

**Gemma is the most reliable and the least clean.** Five completions out of five, and the
neighbouring declaration deleted in three of them. Round 3 recorded that defect as reproducible on
2 for 2; at n=5 it is 3/5, and the earlier sample could not have told 100% from 60% apart.

**gpt-oss's defect is the same behaviour as gemma's, inverted.** Gemma deletes the adjacent
declaration; gpt-oss merges the new property onto it. Both treat the neighbouring line as editable
space, and only a byte-identical check on unnamed regions catches either — the functional tests
pass in both cases.

**The distill is the outlier, not the architecture.** Same size, same context, same 100%
residency, and the only differences are the fine-tune and its packaging. Two fabricated successes
with invented file paths, three runs that never located `.handoff`.

### Void runs, and the shim that caused them

The first `qw3c` batch was discarded entirely. All five failed, three looking exactly like the
Devstral pattern — no files changed, unparseable report. The model had in fact written a correct
`edit` call and the `bash` command to verify it, as two consecutive top-level JSON objects. The
shim ran `json.loads` over the whole blob, hit `Extra data: line 2 column 1`, and promoted
nothing. Replaying the captured payload through the fixed parser recovers three calls where the
old code recovered none.

That is the fourth harness fault in this project that would have been recorded as a model verdict.
`tools/shim-selftest` now covers all of it: threading, multi-call turns, malformed-versus-truncated
JSON, and the client's real zod schema.

One repair was deliberately **not** made. Two qw3c runs emitted an `edit` whose payload stopped
mid-object. Brace-completing those would have turned two failures into passes, and would also let
a truncated `newString` replace a file with a partial copy — valid code, silently wrong. The
self-test asserts truncated payloads are refused.

### Corrections to earlier conclusions

- **"Gemma cannot edit existing files."** Withdrawn. `rewrite_violations` is 0 on all five runs;
  it patches. Round 3 had already shown this and the earlier framing outlived it.
- **"Gemma scores 2/6."** It scores 2/2. `surgical-discount` shipped six checklist items and two
  commands, making 2/6 unreachable-by-construction. Every model in round 3 was understated, and
  the gap to Devstral's 1/6 — a free point for parsing an untouched file — was wider than recorded.
- **"gpt-oss-20b-Coding-Distill fails the tool-call gate."** Wrong, and the error is instructive:
  a single raw-API probe with a terse tool description came back blank and the reasoning trace was
  read as the whole story, when the follow-up probe had in fact returned a native `tool_calls`
  value that was never printed. Both gpt-oss builds emit native tool calls. One probe is not a
  gate — the marker-round-trip probe in `setup-local-model` exists for this reason.
- **"The Qwen family is blocked on packaging."** Half right. The upstream template is genuinely
  wrong, but three shim defects were also in the way. It now runs.

## Round 5 — a second client, and the residency question

Two things at once, both on `surgical` (the seven-criteria replacement for `surgical-discount`):
does a different client change which models work, and is a deliberate CPU offload worth the
throughput it costs.

### Results

| Provider | Config | Perfect trees (7/7) | Median | Throughput | Residency |
| --- | --- | ---: | ---: | ---: | --- |
| clgemmant | gemma @128k, reasoning off | **3/5** | 95 s | 33 tok/s | 100% GPU |
| clgptossnt | gpt-oss @32k, reasoning off | 1/5 | 49 s | **61 tok/s** | 100% GPU |
| clgptoss128nt | gpt-oss @128k, reasoning off | 2/5 | 83 s | 43 tok/s | **84% GPU** |

### The client is a per-model choice, not a global one

| Model | opencode | Cline |
| --- | --- | --- |
| gemma4:12b | 2/5 clean | **3/5 clean** |
| gpt-oss:20b | **4/5 complete** | 1/5 |
| Qwen3-Coder | 1/5, and only through a shim | passes the gate, unreliable in practice |

Cline rescues Qwen — it drives its own tool loop, so the text-versus-native tool-call problem
that needed a proxy shim under opencode does not arise. It ruins gpt-oss: four of five runs died
on `error parsing tool call`, and the single success was the single run with no parse errors. The
same model scores 4/5 under opencode. There is no best client; there is a best pairing.

### Reasoning is the variable that mattered most

Same model, same plan, same client, one flag:

| | reasoning on | reasoning off |
| --- | ---: | ---: |
| Criteria | 0/7 | **7/7** |
| Wall clock | 801 s | **95 s** |
| Context-limit hits | 3 | 0 |

Gemma emitted 15,441 reasoning tokens in a single probe. On top of Cline's 25-tool system prompt
that exhausts a 32k window, and Cline reports the resulting truncation as *"Model reached the
maximum output token limit"* — which is a misleading message: there is no output cap. Captured
from the wire, Cline sends **no** `max_tokens`, `max_completion_tokens` or `num_predict` on either
provider path. It sends `options.num_ctx: 32768`, hardcoded, overriding whatever the model was
baked with.

### Residency: the rule was too strong

| Config | Residency | Result |
| --- | --- | --- |
| Devstral UD-Q3_K_XL @16k (round 1) | 85% | 101 minutes, zero files written |
| gpt-oss @128k (round 5) | 84% | **7/7 in 60 s**, and again 7/7 in 406 s |

At essentially the same offload, one model wrote nothing for an hour and a half and another
produced a byte-perfect patch in a minute. So *"below 100% residency, treat as unusable rather
than slow"* does not generalise. The measured cost of the offload here is throughput: 61 tok/s at
100% falls to 43 tok/s at 84%, roughly proportional to the layers moved. Devstral's collapse was
that model, that quantisation, or the far larger prompt an editing task builds on a 24B — not an
automatic consequence of being 15% off the GPU.

**The offload did not buy reliability, and could not have.** 2/5 against 1/5 is one run at n=5.
More importantly the extra context was never used: peak prompt was 17,017 tokens of the 131,072
granted. There was no context pressure to relieve, which is why `multi` exists.

### Context actually consumed, measured at the proxy

| Model | Window granted | Peak prompt | Utilisation |
| --- | ---: | ---: | ---: |
| gemma | 131,072 | 15,779 | 12% |
| gpt-oss @128k | 131,072 | 17,017 | 13% |
| gpt-oss @32k | 32,768 | 7,400 | 23% |

A single-file surgical edit cannot answer whether 32k is enough for real work. Nothing here came
close to filling it.

### Harness defects found this round (5 more)

| Defect | Symptom it produced |
| --- | --- |
| Shim parsed only one JSON object per turn | A correct `edit` plus its `bash` verification arrived as two consecutive objects; `json.loads` hit "Extra data" and promoted neither, so the round scored as a model that read the files and changed nothing |
| `timeout --foreground` signals only its direct child | An orphaned Cline outlived a 30-minute timeout and competed with the *next* repetition for the same GPU model; that run's empty diff looked like the model collapsing |
| Adapter buffered its log and copied it after exit | The one run that most needed diagnosing preserved no provider log at all |
| `--id` declared as native session resume | Incompatible with `--json` plus a prompt in Cline 3.0.52, so the prompt-validate retry never ran once — every malformed report was unrecoverable, including runs whose patch was perfect |
| Checklist and command counts allowed to disagree | `surgical-discount` had six criteria and two commands, making 2/6 the maximum achievable score and understating every model in round 3 |

Two near-misses worth recording because they were caught by testing the guard rather than trusting
it. The first process-group fix killed `-$!`, which is `setsid`'s pid rather than the new session
leader's, and the grandchild survived. The test that "verified" it then passed *vacuously*: without
`--wait`, `setsid` detached, the pgid file was never written, and `kill -0 ""` failed into a green
result. Had that shipped, `bench/run` would have recorded exit 0 instantly and never waited for the
driver at all.

## Void: every gpt-oss result obtained through ollama

Applying this document's own rule — *could a different harness, configuration or machine have
produced a different outcome for the same model and prompt?* — to gpt-oss.

It could, and it did. Ollama's harmony path corrupts this model's tool calls and returns HTTP 500
for output the model generated correctly. Measured on the same official weights, the same
`apply_patch` schema including its 1224-byte description, and the same multi-turn conversation:

| Serving path | Tool calls valid | Correct patch via Cline |
| --- | ---: | ---: |
| ollama | 2/5 malformed, HTTP 500 | 1/3 |
| llama.cpp | **8/8 valid** | **4/4** |

So the following must not be read as model-quality measurements, and are reclassified:

| Previously recorded as | Now |
| --- | --- |
| gpt-oss under Cline: 1/5 clean (round 5) | **void** — provider parse failures, not model failures |
| gpt-oss @128k offload: 2/5 (round 5) | **void** — same cause; the offload comparison is unresolved |
| "gpt-oss is client-fragile" | withdrawn — it is *ollama*-fragile |

The gpt-oss numbers obtained through **opencode** stay valid (4/5 complete, 3/5 clean). Opencode
ships no `apply_patch`, so the model never generates the payload ollama cannot parse — that is
luck of tool inventory rather than a better path, but the runs themselves are sound.

**The current gpt-oss baseline is llama.cpp**, and it starts from zero repetitions on the old
plans. What survives from round 5 is the *gemma* data, which used a different serving path.

### A correction about tool inventory

Round 5 concluded that a freeform whole-patch tool was inherently fragile for this model and
should be replaced with small targeted edits. **That is withdrawn.** The identical tool definition
and 693–818 byte payloads work repeatedly once the serving layer is correct. Changing the tool set
now would introduce a variable and make the next comparison less informative; `apply_patch` stays.

### Freeze the pairing, then vary one thing

Because "gpt-oss" now names several subtly different serving stacks, every result should carry the
stack that produced it: engine and build, model file digest, context, KV type, GPU layers, client
and version, tool-schema digest, reasoning level, sampling. Without that, a provider regression six
months from now gets attributed to the model — which is exactly the mistake this section is undoing.

### Verdict on the model set

Updated after round 4. "Does the work" means a complete run whose diff is also clean, not merely
a run the harness marked complete.

| Model | Drives the harness | Does the work | Reports honestly |
| --- | --- | --- | --- |
| **gpt-oss:20b** | yes | **yes — 3/5 clean, the best patches measured** | yes |
| **gemma4:12b @96k** | yes | yes — 5/5 complete, 2/5 clean | yes |
| Qwen3-Coder-30B-A3B Q2_K | only through the shim | **1/5** | one fabricated blocker |
| Devstral (Q4 / Q3_K_S / Q3_K_XL) | yes | **no** | **no** |
| gpt-oss-20b-Coding-Distill | yes, once repackaged | **no — 0/5** | **no — 2 fabricated successes** |
| qwen2.5-coder, JanusCoder, gemma-4-coder-fable5 | only through the shim | untested | untested |

Two viable local implementers, with different strengths: **gpt-oss:20b for patch quality, gemma
for throughput**, at roughly half the wall-clock. Neither can be trusted without the
byte-identical guard — gemma trips it in three runs of five, gpt-oss in one.

Qwen3-Coder is not rejected but is not competitive as packaged. Its one clean run was as good as
anything here; the other four were lost to malformed or truncated tool calls, which is what
hand-escaping source into JSON costs a model that was never meant to emit tool calls as text.
That points at the client, not the model — a client that reads XML-style tool calls out of the
text stream, rather than one expecting native calls, would remove the whole failure class.

Two GGUF packaging defects found here are worth reporting upstream, because both silently degrade
the model for anyone using a native-tool-call client:

- **unsloth/Qwen3-Coder-30B-A3B-Instruct** ships a Qwen2.5-era template containing `<tool_call>`
  but neither `<function=` nor `<parameter=`, which is Qwen3-Coder's documented format. The model
  is instructed in a format it was not trained to emit and falls back to bare JSON.
- **mradermacher/gpt-oss-20b-Coding-Distill-i1** ships a template rendering the user turn as
  `tart|>user<|message|>` — the leading `<|s` is missing — and ollama derives stop strings from
  the template, so the stop list contains `<|message|>` and generation halts after three tokens.
  The model returns an empty string to every prompt until it is repackaged.
