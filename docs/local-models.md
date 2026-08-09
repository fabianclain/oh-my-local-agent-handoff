# Local models as implementation agents

Everything measured while driving local models through this harness against a real Laravel
codebase. Hardware: RTX 5060 Ti, 16 GB, ~14.4 GB usable after the desktop.

Nothing here is inferred from model cards or benchmarks published elsewhere. Every claim comes
from a run, and the ones that were wrong are marked as such, because most of the value is in
which confident conclusions turned out to be harness bugs.

---

## The short version

A local model **can** do real work in this pipeline, within a narrow band:

- **Creating new files** — migrations, models, factories, plain services. Gemma 4 12B: 2 for 2,
  needing no correction.
- **Not editing existing files.** Same model, 0 for 5. It regenerates rather than patches, and
  what it does not reproduce is lost.
- **Not anything statistical.** Aggregate SQL, ratios, anything where a plausible answer and a
  correct answer look identical on review.

Three things gate usability, in this order. Each is cheap and each has produced a wrong verdict
when skipped:

1. **Does it emit native tool calls?** Not "does `ollama show` list `tools`" — actually probe it.
2. **Is it 100% resident on the GPU?** Below that, treat as unusable rather than slow.
3. **Does it have context headroom?** An agent loop spends context on file reads and tool
   results before it writes anything you can verify.

---

## 1. Tool-call format — the gate that invalidates everything else

`ollama show` listing `tools` means the template *claims* tool support. It does not mean the
emitted format is one your client parses.

Probed with a file on disk and a prompt to read it:

| Model | Arch | Source | Result |
| --- | --- | --- | --- |
| gemma4:12b-128k | gemma4 | ollama library | **native tool calls** |
| devstral-small-2:24b | mistral3 | ollama library | **native** |
| Devstral Q3_K_S / UD-Q3_K_XL | mistral3 | HF GGUF | **native** |
| qwen2.5-coder:14b | qwen2 | ollama library | text |
| JanusCoder-14B | qwen3 | HF GGUF | text |
| gemma-4-12B-coder-fable5 | gemma4 | HF GGUF | text |

A failing model returns something like:

```json
{ "name": "read", "arguments": { "filePath": ".handoff/plans/probe.md" } }
```

wrapped in a markdown fence, as plain text. The client never executes it, no file contents come
back, and the model then reports — accurately — that it cannot see the file.

**This produced the single worst misjudgement in these notes.** qwen2.5-coder was recorded twice
as fabricating a blocker to look diligent, described as the most dangerous failure mode observed.
It was telling the truth.

**The pattern is per-build.** Not per-architecture: one gemma4 model works and another does not.
Not per-source: HF GGUFs work for Devstral and fail for JanusCoder. It is decided by whichever
chat template that specific package ships, and it is not predictable from the model card.

**Neither engine change fixes it.** Ollama was already current (0.32.6). llama.cpp's Vulkan build
with `--jinja`, given JanusCoder's own HF GGUF with the template embedded, produced the same
fenced JSON with `tool_calls` absent. The format is the model's.

> Trap: ollama stores the chat template as a **separate layer outside the GGUF**. Pointing
> llama.cpp at an ollama blob tests a template-stripped model and tells you nothing.

---

## 2. Residency — below 100% GPU, treat it as unusable

Not "slower". Unusable.

| Build | Weights | Context | Residency | Outcome |
| --- | ---: | ---: | --- | --- |
| Devstral Q4_K_M | 15 GB | 16k | 69% GPU | correct code, truncated before its report |
| Devstral UD-Q3_K_XL | 12 GB | 32k | 72% | 17 GB footprint |
| Devstral UD-Q3_K_XL | 12 GB | 16k | 85% | **101 minutes, zero files written** |
| gemma4:12b | 7.6 GB | 32k | **100%** | completes in 77–149s |

The 101-minute row is the important one. `llama-server` sat at 550% CPU throughout — computing,
not hung. A **15% layer offload** did not cost 15% of throughput; on a task that must read
existing files before editing them, it cost everything. Every token waits on the CPU-resident
layers, and editing pays that across a far larger prompt than greenfield work.

Distinguishing a working run from a hung one from outside is otherwise impossible — both show a
live process and a flat log. Two signals resolve it:

- **GPU busy + log flat** → generating, be patient
- **no model in `ollama ps` + log flat** → dead, kill it

---

## 3. Context — headroom beats model quality

KV cache is far more expensive than it looks. For a 24B at 32k it cost roughly **5 GB**, not the
1–2 GB assumed. Weights that "fit with 2 GB spare" do not fit.

`OLLAMA_FLASH_ATTENTION=1` with `OLLAMA_KV_CACHE_TYPE=q8_0` roughly halves it — UD-Q3_K_XL's
footprint fell from 17 GB to 15 GB at 32k. Worth setting, with one caveat below.

Ollama defaults `num_ctx` to **4096** regardless of a model's advertised ceiling, so a
393k-capable model silently truncates at 4k. Declaring the window in the client's config is not
enough; bake it into a derived model with `PARAMETER num_ctx`. A model served at 4k fails in ways
that look like dishonesty.

**The trade-off that decides model choice:** Devstral 24B wrote the best code of anything tested,
hosted models included — a single-pass `sed -E 's/[^a-z0-9]+/-/g'` where Gemma needed two steps.
It delivered nothing, because 15 GB of weights forced context down until the agent loop ran out
of room. **A smaller model with room to work beats a better model that is starved.**

> Unresolved: gemma scored 5/5 in 77s before KV quantisation and a context cut, then 4/5 in 149s
> after. Two variables changed at once — a design mistake. Quantised KV plausibly costs output
> fidelity, and structured output is where precision loss would show first, but that is untested.

---

## 4. Failure modes, with evidence

### It reports success it did not achieve

The one to fear. A round returned `status: complete`, **zero deviations, zero blockers**, and
claimed the migration ran, the tests passed and the UI was updated. In fact the migration was a
**single line of literal `\n` characters** — a parse error, never executed, column never created;
a production file was left unparseable; the UI file was untouched; no tests were written.

**Treat the report as untrusted metadata. Check the tree first.**

### It replaces whole files, and picks the wrong one

Asked to add a relation to a model and extend a service, it wrote the relation **into the
service** and replaced the file: `PageProfiler.php` went 421 lines → 11. The code was correct;
its destination was not.

That one happened to be a parse error, so a syntax gate caught it. **Luck.** A fragment carrying
its own `class` declaration would have been valid PHP and silently deleted 410 working lines.
Valid code in the wrong file is worse than broken code, because nothing complains.

### It writes plausible, silently wrong SQL

Asked for aggregate reports over per-date rows:

```php
->whereBetween('position', [11, 20])          // filters raw rows, not AVG(position)
->groupBy('site_url', 'query')
->selectRaw('CAST(SUM(clicks) AS decimal(6,4)) as ctr')  // a click count labelled as a ratio
```

`WHERE` runs before `GROUP BY`, so both filters test a single day. The CTR column is not a ratio
at all. Nothing fails to parse; the report would simply be full of confident wrong numbers.

**The plan stated the `SUM(clicks)/SUM(impressions)` rule explicitly and it shipped the wrong
version anyway.** Stating a constraint is not the same as honouring it — a constraint only a test
can enforce needs a test, not a sentence.

### Escaped newlines, in contents and in paths

Files written as one line containing the two characters `\` and `n`. It also happens to
**filenames**: a real file named `OpportunityReport.php` with a trailing newline, invisible to
`ls`, evading a `*.php` check, printing across two lines in `find`.

### It mis-transcribes long identifiers

Given `search-log-persist-total-results`, it looked for `search_log_persist_total_results`,
failed, and reported the plan missing rather than listing the directory. Renaming to `totals.md`
made the same round proceed. **Keep plan slugs short, ideally one word.**

### It writes its reasoning into the deliverable

The first artifact contained three successive implementations in one file, each commenting on the
last: *"Correction: the above is wrong"*, *"Actually, the rule is..."*.

**Fixed by rules about output, not about the task** — see below. This is the single most
effective prompt change measured.

---

## 5. What actually improves results

### Output discipline — 2/5 → 5/5, unchanged task

Adding this section took Gemma from 2/5 to 5/5 on identical task text, *faster* than before, and
took Devstral from 0/5 to 5/5:

> The files you write are deliverables, not scratchpads. One implementation only — never leave an
> earlier attempt beside a later one. No commentary about your own process. No alternatives kept
> "in case". Write real newlines. Run `php -l` on each file and confirm it parses. Never report a
> command as passing unless you ran it and saw it pass. Read each file back before finishing.

Note what did **not** help: making the task smaller or more specific. The failing plan was
already one 30-line file with five explicit criteria and exact input-to-output examples. There
was no ambiguity left to remove. The model understood the task; it could not stop narrating.

### Greenfield for the local model, edits for the hosted one

Creating a file has one obvious destination. Editing requires holding a file's existing contents
in mind and returning them unchanged apart from the edit — and a model that regenerates rather
than patches loses everything it did not reproduce.

- **Local:** new migrations, models, factories, services, views, tests.
- **Hosted:** edits to existing files, anything touching several files at once, anything
  statistical, anything where being wrong is silent.

Greenfield is necessary but **not sufficient**: it protects the codebase from destruction, not
the output from being wrong. The bad SQL above was in a brand-new file.

---

## 6. What the harness must do

Every item below was added after a specific failure.

**Gate the tree before reading the report.** For each changed file: does it parse; has a tracked
file lost more than half its lines; does the path contain control characters. Revert the round if
any fail.

**Refuse to start on a dirty tree.** The model's context is already clean — each round gets a
fresh session. The shared state is the *working tree*, and a file left dirty by a previous failed
round is read as intended and appears in the next round's diff, framing an innocent round for
damage it did not do. That produced a confident, wrong attribution here.

**Close stdin.** `codex exec` and `opencode run` both append piped stdin when stdin is not a TTY,
so in a background shell they block forever. Observed as a round sitting 31 minutes with a 0-byte
log — indistinguishable from a slow model until you look for child processes.

**Never `git stash push -u` then `git stash apply` as a safety net.** It restores the broken state
you were escaping. It reintroduced an unparseable migration twice here. Archive with
`git stash show -p > file.patch` and drop the stash.

**A syntax sweep is not a contamination check.** Two contaminated files parsed perfectly; one
silently converted a null into a zero. `git status` catches what `php -l` cannot.

---

## 7. Benchmarking method

**A run blocked by the harness, the adapter, the config or the machine is void.** Not a model
result, not scored, re-run after fixing the cause. Counting harness faults as model faults
produces confident wrong conclusions, and every one here would have been: a model recorded as
fabricating a blocker (served 4k context), one recorded as stalling (adapter blocked on stdin),
and a whole round lost (`--force` deleting every provider's results rather than the one rerun).

The test: *could a different harness, config or machine have produced a different outcome for the
same model and prompt?* If yes, void it.

A result still counts when the cause is real and outside the harness — a model exhausting context
because the hardware cannot hold more is a **configuration result**, labelled as such, and it
changes when the configuration does.

**Isolate every attempt in its own worktree** from the same commit, or one provider inherits
another's edits. **Run one benchmark at a time**; concurrent runs share the GPU and, with
`OLLAMA_MAX_LOADED_MODELS=1`, evict each other's model continuously, measuring contention rather
than models.

---

## 8. Setup checklist for a new model

```bash
ollama show <model> | grep -A6 Capabilities     # 'tools' present? necessary, not sufficient
# probe: write a file, ask the model to read it, require the marker back
printf 'FROM <model>\nPARAMETER num_ctx 32768\n' > Modelfile && ollama create <name> -f Modelfile
ollama ps                                        # demand 100% GPU
```

Register the same context in the client's config as well as baking it. Then benchmark — and only
then.
