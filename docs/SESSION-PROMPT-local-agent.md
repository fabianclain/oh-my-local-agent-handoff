# Session prompt: local model as an implementation agent

Paste this to start a session focused only on driving local models through agent-handoff.

---

I want to work on using a **local model as the implementation agent** in agent-handoff, and
nothing else. Do not touch the host application's own code — that is a separate track.


## Read these first

All paths relative to the agent-handoff checkout unless noted.

| File | What it is |
| --- | --- |
| `docs/local-models.md` | **Start here.** All measured findings: the three gates, failure catalogue with evidence, harness requirements, setup checklist |
| `bench/COMPARISON.md` | Run-by-run record, residency table, method changes and why each was adopted |
| `bench/METHODOLOGY.md` | Benchmark rules, including the void-run rule |
| `bench/run` | The harness. Worktree isolation, flock concurrency guard, criteria scoring |
| `bench/report` | Renders results; every repetition shown individually, no aggregate score |
| `bench/plans/` | `mechanical`, `mechanical-guided`, `surgical-discount`, `ambiguity`, `integration` |
| `bench/fixtures/surgical/InvoiceTotals.php` | The 70-line class the surgical plan edits |
| `tools/toolcall-shim.py` | Promotes text tool calls into real ones. Works via curl, not via opencode |
| `templates/plan.md` | Plan template, including the output-discipline section |
| `docs/usage.md` | General agent-handoff usage, provider selection |
| `providers/*.sh` | `ollama.sh` is the base; `gemma.sh`, `dvq3s.sh`, `dvq3xl.sh`, `dvq4.sh`, `qwen.sh`, `devstral.sh` are labels over it |

In the host project that agent-handoff drives (its `.handoff/bin/`, if you keep helpers there):

| File | What it is |
| --- | --- |
| `.handoff/bin/setup-local-model` | Gauntlet: capability flag → **tool-call probe** → bake context → measure residency → register |
| `.handoff/bin/gemma-round` | Gated round against the live repo: clean-tree precondition, syntax, collapse, control chars, collateral deletion |
| `.handoff/bin/watch-local` | Distinguishes a generating run from a hung one (GPU + log growth together) |

## What was tried — including what failed

Recording the dead ends so they are not repeated.

### Worked

| Change | Effect |
| --- | --- |
| **Output-discipline section in the plan** | Gemma 2/5 → **5/5** on unchanged task text, and faster. Devstral 0/5 → 5/5. The single most effective change measured |
| **Short, one-word plan slugs** | A long hyphenated slug was mis-transcribed with underscores and reported as a missing plan |
| **Per-model context sizing** | Gemma 32k → 96k recovered 4/5 → **5/5 @60s**, beating its own earlier 77s |
| **Tool-call probe before benchmarking** | Caught three unusable models in a minute each, before wasting runs |
| **`flock --close` for the bench lock** | Stops the descriptor leaking into children that outlive a timed-out run |
| **Byte-identical guard on unnamed regions** | Catches Gemma's one real defect, which functional tests do not |
| **KV quantisation (`q8_0`)** | UD-Q3_K_XL footprint 17 GB → 15 GB at 32k; Q3_K_S reached 93% |

### Did not work

| Attempt | Outcome |
| --- | --- |
| **Updating ollama** | Already current at 0.32.6; the reinstall replaced files and changed nothing |
| **llama.cpp `--jinja`** | Installed and working (Vulkan, sees the GPU), but JanusCoder produced the same fenced JSON. The format is the model's, not the engine's |
| **Devstral at any quantisation** | Q4 69% resident, UD-Q3_K_XL 85%, Q3_K_S 93%. None usable: six surgical runs changed nothing |
| **Devstral at 16k for full residency** | Q3_K_S reached 100% and then **timed out** on a task it did in 39s at 32k/93%. Unexplained |
| **The shim inside opencode** | Three streaming shapes tried. The last emits ollama-shaped NDJSON and opencode still returns nothing. **Gemma fails through it too**, so the shim is at fault |
| **Testing llama.cpp with an ollama blob** | Invalid: ollama stores the chat template as a **separate layer outside the GGUF**, so that tests a template-stripped model |

### Unresolved

- **Did `q8_0` KV cost quality?** Gemma scored 5/5 @77s before it, 4/5 @149s after — but the
  context was cut at the same time. Restoring context recovered 5/5, which points at context
  rather than KV, though the two were never varied independently.
- **Why did Devstral Q3_K_S time out at 16k** after completing in 39s at 32k?
- **`dvq4` completed 5/5 at 69% residency** on the trivial plan, which contradicts the strong
  reading of "below 100% is unusable". The 101-minute failure was a real edit task, so the claim
  holds for real work and is too strong as stated for toy tasks.

### Harness defects found and fixed (7)

Most "model failures" were these. Worth reading `bench/COMPARISON.md` for the detail.

1. Models served at ollama's default 4096 context — produced a false "fabricates blockers" verdict
2. `bench/run --force` deleted every provider's results, not the one being re-run
3. No concurrency guard — two loops thrashed one GPU
4. The lock then failed instantly on a legitimately queued run
5. The lock leaked its descriptor into children, wedging for 600s
6. The lock dropped its arguments on re-exec
7. A collateral-deletion check that matched the plan's prose instead of the identifier

## Where things are

Repo: the agent-handoff checkout (its own git repo, public, MIT).
Read `docs/local-models.md` first — it is the accumulated findings and it is accurate.
Then `bench/COMPARISON.md` for the run-by-run record and the method rules.

Hardware: RTX 5060 Ti, 16 GB, ~14.4 GB usable after the desktop. Ollama is configured with
`OLLAMA_FLASH_ATTENTION=1`, `OLLAMA_KV_CACHE_TYPE=q8_0`, `OLLAMA_MAX_LOADED_MODELS=1`.
llama.cpp (Vulkan, b10331) is installed at `~/.local/opt/llamacpp/` and serves an
OpenAI-compatible API.

## What is established

**Gemma 4 12B is the only local model that both drives the harness and does the work.**
100% GPU-resident at 96k, patches rather than regenerates (+8/−3 lines on a 70-line class),
5/5 on the guided mechanical plan in 60s. Its one defect is mechanical: it deletes the
declaration adjacent to its insertion point, on every run. That is now caught by a
byte-identical guard in `.handoff/bin/gemma-round`.

**Devstral (Q4, Q3_K_S, UD-Q3_K_XL) fails on honesty, not capability.** On a surgical edit it
changed nothing six times out of six — zero bytes — and three of those runs reported
`status: complete` with invented summaries ("added discount calculation to order processing and
updated API endpoints; all tests pass"; there is no order processing and there are no API
endpoints in the task).

**The Qwen family is blocked on packaging, not capability.** `qwen2.5-coder:14b`,
`JanusCoder-14B`, `Qwen3-Coder-30B-A3B-Instruct` and `gemma-4-12B-coder-fable5` all emit correct
tool calls as **text** rather than as native calls. Verified at ollama's API directly.
Qwen3-Coder-30B-A3B at Q2_K is 100% resident at 32k with ~3 GB spare, so it is the most
promising untested candidate.

## The three gates, in order

1. **Tool-call format.** `ollama show` listing `tools` proves nothing — probe it: write a file,
   ask the model to read it, require the marker back. `.handoff/bin/setup-local-model` does this.
2. **Residency.** Below 100% GPU, treat as unusable rather than slow. A 15% layer offload once
   cost 101 minutes and zero files written on a real edit task.
3. **Context.** Ollama defaults `num_ctx` to 4096 regardless of the model's ceiling. Bake it with
   `PARAMETER num_ctx` *and* declare it in opencode's config. KV cache for a 24B costs ~5 GB at
   32k.

## Method rules — these are not optional

**A run blocked by the harness, adapter, config or machine is void.** Not a model result, not
scored, re-run after fixing the cause. Three of the harshest verdicts in this project were
harness bugs, including one model recorded as fabricating a blocker when it had been served a
4096-token context and could not see the plan.

The test: *could a different harness, config or machine have produced a different outcome for the
same model and prompt?* If yes, void it.

**Verify a guard against the exact failure it targets.** The concurrency lock produced three
defects before working. A collateral-deletion check silently passed because it stripped a `$`
sigil and matched the plan's own prose.

**Treat the model's report as untrusted metadata.** Check the tree first: syntax, whole-file
collapse, control characters in paths, empty diffs, deletions the plan never named.

## Open work

- **Finish the tool-call shim.** `tools/toolcall-shim.py` promotes text tool calls into real ones
  and is verified with curl for both qwen models. It does **not** work inside opencode — gemma
  fails through it too, so the shim is at fault. Better than guessing at ollama's NDJSON: read
  what `ollama-ai-provider-v2` actually parses, or use llama.cpp's OpenAI-compatible endpoint.
- **Then benchmark Qwen3-Coder-30B-A3B** on `surgical-discount`, 5 runs, against gemma's baseline.
- **Fix a bench flaw:** "the file parses" passes on an unmodified tree, so a do-nothing run scores
  1/6 rather than 0. An empty diff should score zero.
- **Build the remaining method from the owner's notes:** three task classes (greenfield / surgical
  1–10 lines / architectural multi-file), capped repair loops (3 attempts), test-first delegation
  (hosted writes the tests, local iterates to green), harness-enforced scope contracts, and a
  semantic-risk class for aggregate SQL, auth, money, dates and concurrency.
- **The real metric is cost to an accepted patch** — local generation plus hosted verification
  plus repair attempts — not capability on a toy task. Screening is 5 repetitions; raise to 15+
  only for a model that survives.

## How to run things

```bash
.handoff/bin/setup-local-model <ollama-model> 32768   # probe, bake, measure, register
bench/run --plan <slug> --providers <name> --repeat 5 --force
bench/report
.handoff/bin/gemma-round <slug>                       # gated round against the live repo
```

Plan slugs must be **short, ideally one word** — a long hyphenated slug was mis-transcribed and
reported as a missing file.

## What I want from you

Report what you verified and how, separating "tests passed" from "checked against real data".
When a run fails, establish whether the harness caused it before concluding anything about the
model. If a conclusion I hold turns out to be wrong, say so plainly — most of the confident
conclusions in this project so far were harness bugs.
