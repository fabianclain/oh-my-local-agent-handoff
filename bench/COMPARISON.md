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

## Results

_Round 1 pending._
