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
than a greenfield one. Treat anything below 100% as unusable rather than slow.

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

## Results

_Round 1 pending._
