# Changing the model

Everything measured on 2026-08-16, trying three local models against gpt-oss-20b and asking
whether fine-tuning is worth it. Hardware throughout: RTX 5060 Ti, 16 GB, ~14.4 GB usable after
the desktop. Engine throughout: llama.cpp b10331, **Vulkan** build.

The short version is that none of the three replaced gpt-oss, the reasons were rarely the ones
expected, and the most useful thing produced was a gate rather than a result.

---

## 1. The gate: `tools/capability-baseline`

Swapping or fine-tuning a model that works is a trade, and the thing most likely to be traded away
is not coding ability — it is the machinery around it. Four models have been rejected in this
project for emitting correct tool calls as **text** rather than as `tool_calls`, and one was
recorded twice as fabricating a blocker when it was telling the truth: nothing ever executed the
call it made. A change that costs gpt-oss its harmony channels or its `submit_report` discipline is
worthless here regardless of what it gained, and it presents as *"the model got worse at coding"*.

So capture before, capture after, diff. Eight probes, about two minutes:

| probe | what it catches |
| --- | --- |
| `native-tool-call` | a call arriving as text in `content`, where nothing will execute it |
| `call-after-result` | the second call, after ~19 KB of tool output — the case that broke ollama |
| `large-arguments` | ~1 KB of argument text truncated in transit |
| `report-json` | the no-tools fallback channel, which carries every round on the deepest plan |
| `report-tool` | the same report via `submit_report`; the two channels fail independently |
| `response-format` | a constrained model answering with **silence** — the grammar cannot emit junk |
| `stop-discipline` | a model that will not stop. LFM2.5 spent 11,625 tokens on a fifty-token question |
| `harmony-channels` | gpt-oss only: `<\|channel\|>` and a `final` message, which native-agent parses itself |

**The exit codes are the point.** `0` compared and nothing regressed, `1` compared and something
regressed, `2` **could not fully compare**. A probe that used to answer and now skips is a hole,
not a pass — returning `0` for it is exactly how a change that broke the harmony channel would ship
looking clean, because the probe that would have caught it merely stopped running.

The same reasoning caught a hole in the tool itself. It identified the model from `/props`, which
for an ollama-blob model is a sha256; the harmony probe keys on the name, so gpt-oss served from a
blob would have been unrecognisable, **skipped**, and read as benign. It now prefers the registered
name `llamacpp-serve` writes.

Baselines on disk: `gpt-oss-20b` **8/8**, `Qwen3.5-9B-Claude-Code` **7/8** with harmony correctly
skipped as not applicable.

---

## 2. Three models, and what actually decided each

### Speed is about ACTIVE parameters, not size

| model | total | active/token | quant | tok/s |
| --- | ---: | ---: | --- | ---: |
| gpt-oss-20b | 20B | **~3.6B** | MXFP4 | **72.2** |
| LFM2.5-8B-A1B | 8.3B | ~1.5B | Q8_0 | 114 |
| Qwen3.5-9B-Claude-Code | 9B | ~9B dense | Q8_0 | 20.5 |

gpt-oss is **3.5× faster than a model less than half its size**. Generation is memory-bandwidth
bound, so what matters is active parameters × bytes per weight. gpt-oss moves ~3.6B at 4 bits;
Qwen3.5 moves ~9B at 8 bits, roughly five times the traffic per token. Qwen numbers are n=1,813
samples from a real bench workload, gpt-oss measured on one prompt.

**A dense 9B is the wrong shape for this card.** Prefer MoE.

### LFM2.5-8B-A1B — fast, verbose, and it fabricated

Passed the format gate. Then, on `semantic` against a gpt-oss control of 4/4 accepted:

| | gpt-oss | LFM2.5 | Fisher p |
| --- | ---: | ---: | ---: |
| usable tree | 4/4 | **0/3** | 0.03 |
| seconds (median) | 153 | 290 | 0.032 |
| generated tokens | 9,546 | **29,109** | 0.034 |

Three times the tokens to produce nothing usable, and one round **reported success over a tree it
never touched** — the failure this harness treats as most dangerous, caught because the verdict
comes from the tree and never from the report.

One caveat kept open and unrun: LiquidAI ships **temperature 0.2** and the harness ran it at 0.8,
the value every gpt-oss number was measured at. A model that over-generates and fails to converge
is what an over-hot sampler produces. Matching sampling keeps the comparison to one variable at the
cost of running the model off its recommended profile, and a 0.2 arm is the honest follow-up.

> **This verdict is NOT SAFE, and the reason was found the same day.** llama-server's own log shows
> that during the LFM2.5 run it parsed and **discarded 3 of 189 completions (1.6%)** — and every
> one of the three was a WRITE:
>
> ```
> write_file(path='bench/fixtures/billing/Invoice.php', content='<?php\n\nnamespace Bench\ Fixture...')
> write_file(path='bench/fixtures/billing/Invoice.php', content='<?php\n\nnamespace Bench\ Fixture...')
> replace_in_file(path='bench/fixtures/billing/Proration.php', old='<?php ...')
> ```
>
> Python call syntax, not the format the parser admits, each carrying a multi-KB PHP file. Reads
> survived; the writes vanished. A model whose reads work and whose writes are silently dropped
> produces exactly the two signatures recorded above: rounds that explore extensively and change
> nothing, and one round that believed it had written the files and said so. **It was not lying.**
>
> This is the same fault family that had `qwen2.5-coder` recorded twice as fabricating a blocker to
> look diligent while it was telling the truth, and it was attributed to the model here before the
> log was read. 1.6% does not obviously account for every failure, so the honest statement is that
> the mechanism was invisible and the verdict cannot stand on the evidence gathered.
>
> `tools/capability-baseline` passed LFM2.5 on `large-arguments` because that probe sent 1.1 KB.
> It now sends ~4.7 KB, the weight of a real plan file, and every probe reports any completion the
> stack discarded while it ran — so "the model did not call the tool" and "the stack threw the call
> away" can no longer be confused.

### gemma-4-12B-agentic — passed the format gate its sibling fails, then ran out of room

`gemma-4-12B-coder-fable5` is one of the four models rejected here for text tool calls.
`gemma4:12b-128k` from the ollama library emits them natively. **This build emits them natively**,
in 46–53 tokens with terse on-task reasoning. Same architecture, same family, opposite answers:
per-build, not per-architecture, and not predictable from the model card.

It was then defeated by arithmetic. Q8_0 is 12.67 GB on a card with ~14.4 GB usable, leaving
~1.4 GB for KV and a **16,384** window. Two of three rounds overflowed it and lost history;
`bench/compare` correctly called them configuration results rather than model failures. The
comparison was also **CONFOUNDED** — the clone was synced between control and arm, so the two ran
under different harness trees — and was discarded for that reason.

Q6_K at 9.79 GB is the quant that fits with a usable window. That is a fit result, not a verdict.

### Qwen3.5-9B-Claude-Code — the format surprise

Its model card states it *"calls tools with XML-style `<tool_call>` blocks"*, the exact shape that
got four models rejected. **It passes**: native `tool_calls`, correct name and argument, 56 tokens.

The difference is the **engine, not the model**. Those four were probed at ollama's API; llama.cpp
with `--jinja` carries format-specific parsers and promotes the XML into `tool_calls`. That is gate
0 in [local-models.md](local-models.md) — *know which engine served it before concluding anything
about a local model* — and it means a card describing XML tool calls is not, by itself, a
rejection. **Those four earlier verdicts deserve re-testing on llama.cpp.**

It does real work: on one attempt, 69 insertions, created the file the plan named, ran 17
verification commands itself, and submitted a parseable report. It is also very slow — round 1 took
**2,244 s across three attempts** and ended `patch-incomplete`, against gpt-oss's 153 s median for
a full accepted round. Two of its three attempts wrote nothing at all, and the provider log shows
why it might not be the model's fault:

```
TimeoutError: timed out                                        x2 (one on the report turn)
tool-scope fault in read_files: /home/user_aeefbb67/...        hallucinated home directory
tool-scope fault in read_files: /home/fabbs/dev/agent-handoff-bench...   outside its worktree
```

It reaches for absolute paths outside its sandbox, one of them fabricated — plausible for something
fine-tuned on another environment's transcripts — and it hit the provider timeout twice, so some of
the no-op behaviour is the harness cutting it off rather than the model declining to write.

---

## 3. Fine-tuning: not yet, and the dataset is why

The idea was to fine-tune on our own repositories. `tools/build-trace-dataset` was written to see
what material exists. It produced **210 examples across 7 tasks**:

```
98 wide    45 semantic    30 site-dark    23 site    7 pre    4 ledger    3 surgical
```

217 accepted rounds looks like a dataset. It is seven problems solved thirty-odd times each. The
diversity is in the **sampling**, not in the problems, and no number of additional runs changes
that. A model trained on it learns those seven plans.

That reason is independent of which model is trained, and it is the strongest one. Three others:

- **What repeats across every trace is the loop discipline** — call a tool, read the result, edit,
  verify, report. That is task-independent and worth teaching a model that lacks it. gpt-oss scores
  **8/8** on it already, so there is nothing to gain and a working capability to risk.
- **gpt-oss-20b cannot be LoRA'd on this card.** It ships natively in MXFP4, which cannot be
  trained against directly; training needs the bf16 upcast, well beyond 16 GB. A borrowed second
  GPU does not fix this — training splits far worse across mismatched cards than inference does.
- **The feasible local target is 3.5× slower.** Fine-tuning Qwen3.5-9B means spending days to
  improve a model that starts slower and weaker than the one it would replace.

**What has actually paid**, all harness-side and all in hours rather than days: windowed
`read_files` turned three dead rounds into an accepted one; raising the turn cap from 40 to 80
mattered because the accepted steps peaked at iteration 67 and 41; the peg-fault retry recovered
the report in 22 of 29 affected runs; `symbols` gives declaration *extents*, which grep structurally
cannot.

**Ranked, what to do instead:** run the arms already built; move Vulkan → CUDA, which is free
throughput on the model actually in use; write more distinct plans, which improves the harness now
*and* is the only thing that would make a training set viable later; fine-tune last, on gpt-oss, on
rented hardware.

---

## 4. Defects found on the way, and which are still open

**Fixed.** A round inside a benchmark waited forever for its own parent's GPU lock — `bench/run`
held it and exported `BENCH_LOCK_HELD` while `bin/handoff` keyed on `HANDOFF_GPU_LOCK_HELD`, so
nothing connected them and the wait loop had no deadline. It would have consumed the whole of the
report-channel queue. Two regression cases, because one is not enough: 13 proves `handoff` honours
the flag, 14 proves `bench/run` sets it.

**Fixed — the residency check measured the wrong number.** It read `VmRSS` and warned that
gemma4-agentic was "at least partly in host memory". It was not: llama.cpp **mmaps** the GGUF, so
the model file's page cache is file-backed and counts toward `VmRSS` without a byte of it being a
spill. On a fully resident gpt-oss: `VmRSS` 1.19 GB, `RssFile` 0.81 GB, `RssAnon` **0.38 GB**, with
nvidia-smi reporting all 12,756 MiB on the card, and sustained generation at 94–96% GPU on 14% of
one CPU core. The check now reads `RssAnon`. It had nearly bought a needless 10 GB download of a
smaller quant, while the throughput evidence contradicting it sat in the same terminal.

**Fixed — `llamacpp-serve start <model>` served a different model, silently.** The unit names one
model in its `ExecStart`, so restarting it to serve another starts the unit's model:
`start lfm2.5-8b` brought up gpt-oss three times running, each looking like a different failure,
and the state file then recorded gpt-oss so nothing downstream noticed either. It now reads the
unit's `ExecStart` and, when the requested model differs, stops the unit and starts directly.

**Open — the most diagnostic artifact this stack produces is being deleted.** llama-server logs
every completion it discards under `unparsed peg-native output:`, with the full text. Those logs
are rotated on each server start and the old ones are pruned: **99 archived samples, the entire
evidence base for the harmony fault, no longer exist on this machine.** Three survived, and those
three overturned a model verdict. `providers/lcpp.sh` already brackets each round by byte offset
into that log for token accounting; the same bracket would let a round copy its own discarded
completions into its result directory, where they would outlive rotation.

**Fixed, and this entry had the cause wrong.** It said the unit hardcodes `-c 65536`. It does not:
`ExecStart` is `llamacpp-serve foreground gpt-oss-20b`, and `cmd_foreground` reads the context from
the state file. The 65536 was written by **this tool's own failed start** — `start lfm2.5-8b 65536`
wrote the context, failed on a busy port, and the gpt-oss server that returned a moment later read
65536 where the session had been running 98304. The previous value is now restored on every failure
path. Diagnosing it as a hardcoded unit value was a guess that matched the symptom and not the
mechanism.

---

## 5. The harmony spec, and what llama.cpp does to our tools

[openai/harmony](https://github.com/openai/harmony) is the official renderer and parser for the
format gpt-oss speaks. Reading it answered two questions this project had only guessed at, and
raised a third that matters more than either.

### Our lenient parser is spec-sanctioned, not guesswork

`tools/native-agent`'s `parse_harmony` is tolerant in three documented ways, each added from an
observed failure. Two of them turn out to be the specification, not leniency. From `docs/format.md`:

> If the model decides to call a tool it will define a `recipient` in the header … **The recipient
> might be defined in the role or channel section of the header.**
>
> The model **might also** specify a `<|constrain|>` token to indicate the type of input.

So a recipient whose position varies, and an optional `<|constrain|>`, are both expected. Those are
exactly the shapes llama.cpp discards — 99 of 3,131 completions in one night, 75 of them a
"garbled" header and 18 a `final` message tagged `<|constrain|>json`.

**llama.cpp is stricter than the format's own specification.** Fed the same strings, the official
parser does not reject them. It is worth saying that it does not parse them *well* either — on the
garbled header it returns `channel='functions.write_file'`, `recipient='<|channel|>commentary'`,
which is not the intended reading. `parse_harmony` recovers the intent that both of the others lose.

### llama.cpp flattens every nested tool argument to `any[]`

The spec renders tools as TypeScript-like types in a `functions` namespace and states plainly that
**"it is important to stick to this format closely to improve accuracy of function calling"**.
llama.cpp does render that format, and does emit the channel rules. It does not render the types.

The same `read_files` schema, through both renderers:

| | |
| --- | --- |
| **harmony** | `files: { path?: string, // first line, 1-based`<br>`start?: number, // last line, inclusive`<br>`end?: number, }[]` |
| **llama.cpp** | `files: any[]` |

Four nested structures in the real tool set are erased this way:

| tool | field | rendered as |
| --- | --- | --- |
| `read_files` | `files` | `any[]` — `path`, `start`, `end` invisible |
| `submit_report` | `files_changed` | `any[]` |
| `submit_report` | `tests_run` | `any[]` |
| `submit_report` | `deviations` | `any[]` |

The `start`/`end` window — the change that turned three dead rounds into an accepted one — **is not
in the type the model is shown**. It survives only because it happens to be described in prose in
the tool's description string, which is why that description reads the way it does.

Worse for `submit_report`: llama.cpp builds the tool-call **grammar** from the same schema, so the
model is *forced* into a shape it was never shown. A model fighting a grammar it cannot see is
precisely the failure `capability-baseline`'s `response-format` probe watches for.

### The fix is half-built already

`providers/nativeraw.sh` generates through `/completions`, taking the prompt from `/apply-template`
so it cannot drift from the server's idea of it. That call is the one thing to replace: render with
harmony's own renderer instead, and the tool definitions become correct wholesale. Same loop, same
tools, one dependency, and it is an arm — measurable against the same control as everything else.

This is the first finding here that changes what the model is **told**, rather than how its answer
is read.
