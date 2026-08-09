# Draft issue for ollama

Everything below is measured on this machine. Fill in or trim as you like — the reproduction
script is `tools/repro-ollama-toolcall-500.py` in this repo.

---

**Title:** gpt-oss: HTTP 500 "error parsing tool call" — ollama rejects a tool call its own model
generated

**Version:** ollama 0.32.6 (client and server)
**Model:** `gpt-oss:20b` (ollama library) and `hf.co/mradermacher/gpt-oss-20b-Coding-Distill-i1-GGUF:Q3_K_M`
**Hardware:** RTX 5060 Ti 16 GB, `OLLAMA_FLASH_ATTENTION=1`, `OLLAMA_KV_CACHE_TYPE=q8_0`,
`OLLAMA_MAX_LOADED_MODELS=1`

## What happens

`POST /api/chat` returns **HTTP 500** with:

```json
{"error":"error parsing tool call: raw='{\"input\":\"*** Begin Patch\\n*** Update File: f.php\\n@@\\n-    public function total(float $rate): float\\n…*** End Patch\"}]', err=invalid character ']' after top-level value"}
```

The payload ollama cannot parse is its **own model's output**. Note the trailing `]` with no
opening bracket: the generation appears to be array-wrapped, `[{"input": …}]`, and the parser
consumes the object then fails on the remaining `]`.

## Expected

Either the tool call is parsed (a single-element array unwrapped), or — at minimum — a malformed
generation is reported as a recoverable condition rather than a 500. A model-output problem
surfacing as a server error makes this look like a client bug: it cost us a long investigation in
which the error was wrongly attributed to the calling client, because the client was only
relaying ollama's 500 verbatim.

## Reproduction

`python3 repro-ollama-toolcall-500.py gpt-oss:20b 10`

It is non-deterministic — roughly 2 in 5 at the API level. Three conditions must coincide;
removing any one makes it stop:

1. an `apply_patch`-style tool: one freeform string argument carrying a whole patch
2. a conversation already containing an assistant tool call **and** a substantial (~1.6 KB) tool result
3. a long tool description

## What we ruled out, with measurements

| Hypothesis | Result |
| --- | --- |
| Large arguments break serialisation | 2,858 B parsed fine; failures occur at ~700 B |
| Too many tools offered (25) | Reduced to 7 — 2 of 3 runs still failed |
| `think: false` on a reasoning model | 1/3 success with reasoning on, 1/3 with it off |
| The client's response parser | Reproduced with plain `urllib`, no client present |

## The tool description is a measurable trigger

Same model, same conversation, varying only the `apply_patch` description string:

| Description | Failures |
| --- | ---: |
| 1224 B (Cline's, with worked examples) | **2/5** |
| 105 B replacement | **0/5** |

## llama.cpp does not reproduce it

Same official weights (`ggml-org/gpt-oss-20b-GGUF`, MXFP4), same tool schema including the 1224 B
description, same multi-turn conversation, served by `llama-server` b10331 with `--jinja`:

**8/8 valid tool calls, 0 malformed, 0 errors**, at argument sizes 228–818 B — including 693, 717
and 818 B, the range that fails under ollama.

End to end through the same client: **4/4 correct edits via llama.cpp** versus **1/3 via ollama**.
llama.cpp was also faster on the same model, ~74 tok/s against ~61.

Because llama.cpp never produced the array-wrapped form at all, the cause may be in ollama's
harmony **prompt rendering** rather than in the parser — the two engines evidently render the same
conversation differently. We have not read the ollama source, so that is a hypothesis, not a claim.

## Possibly related packaging note

`gpt-oss:20b` from the ollama library declares model architecture **`gptoss`**, while the Hugging
Face GGUF declares **`gpt-oss`**. llama.cpp refuses the ollama blob with
`unknown model architecture: 'gptoss'`. Mentioning it in case the two builds differ in ways that
bear on the harmony path.
