# Local models as implementation agents

Everything measured while driving local models through this harness against a real Laravel
codebase. Hardware: RTX 5060 Ti, 16 GB, ~14.4 GB usable after the desktop.

Nothing here is inferred from model cards or benchmarks published elsewhere. Every claim comes
from a run, and the ones that were wrong are marked as such, because most of the value is in
which confident conclusions turned out to be harness bugs.

---

## The short version

> **Reasoning level is not the lever it was assumed to be.** `low` against `off` on the six-file
> plan, 15 runs each: both delivered a reviewable patch 14 times out of 15, and every quality
> difference is inside chance (p ≥ 0.70). `off` was nominally ~26% *more* expensive per usable
> patch, not less, though that does not reach significance either (p = 0.18–0.22). The theory that
> the implementer should not think, because the planner already did, is dismissed — see round 6.

> **The serving engine is a gate, not an implementation detail.** gpt-oss through ollama scored
> 1/3 with malformed tool calls; the same official weights through llama.cpp scored 4/4, and then
> **4/4 on a nine-criteria multi-file task, every run first-attempt** — a plan gemma scores 0/9 on.
> Nothing about the model changed. Before concluding anything about a local model, know which
> engine served it. See §7b.

Two local models do real work in this pipeline:

- **gpt-oss:20b** writes the best patches measured here — 3 of 5 runs deleted exactly one line,
  the one being changed. Roughly twice gemma's throughput per token, but it spends a long
  reasoning channel before acting, so it is slower in wall clock.
- **gemma4:12b @96–128k** is the most reliable at completing at all, and the least clean: it
  damages the line next to its insertion point in a majority of runs.
- **Neither can be trusted without a byte-identical check** on the regions the plan did not name.
  Their defects pass the functional tests.
- **Nothing statistical.** Aggregate SQL, ratios, anything where a plausible answer and a correct
  answer look identical on review.

> An earlier version of this section said local models create files well and cannot edit them at
> all. That was superseded by measurement: they patch rather than regenerate, and the real defect
> is mis-locating the insertion point.

Five things gate usability. Each is cheap, and each has produced a wrong verdict when skipped:

0. **Which engine serves it?** Ollama and llama.cpp are not interchangeable for a model whose
   tool-call format the engine has to parse. This one was discovered last and should have been
   checked first.

1. **Does it emit native tool calls?** Not "does `ollama show` list `tools`" — probe it, and probe
   it more than once. A single blank probe was read as a rejection for a model that works.
2. **Is the packaging sound?** Read the chat template and the stop list. Three models here were
   blocked by packaging rather than capability.
3. **How much residency does the window cost?** Below 100% is a throughput tax of roughly the
   layers moved, not an automatic cliff — but measure it, because one model did lose everything.
4. **Which client?** There is no best one. Cline drives its own tool loop and rescues models that
   cannot emit native calls; it also fails to parse gpt-oss, which opencode handles fine.

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
| qwen2.5-coder:14b | qwen2 | ollama library | text — **native via shim** |
| Qwen3-Coder-30B-A3B | qwen3 | HF GGUF | text — **native via shim** |
| JanusCoder-14B | qwen3 | HF GGUF | text |
| gemma-4-12B-coder-fable5 | gemma4 | HF GGUF | text |
| gpt-oss-20b-Coding-Distill | gpt-oss | HF GGUF | **native once repackaged** — see below |
| gpt-oss:20b | gpt-oss | ollama library | **native** |

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


### The Qwen family emits correct tool calls — as text

Four models were rejected by the tool-call probe: `qwen2.5-coder:14b`, `JanusCoder-14B`,
`Qwen3-Coder-30B-A3B-Instruct` and `gemma-4-12B-coder-fable5`. That rejection is about **format,
not capability**, and the distinction matters because Qwen3-Coder is marketed specifically for
agentic coding.

Probed at ollama's API directly, with tools in the payload:

```
qwen2.5-coder → content: {"name":"read","arguments":{"filePath":"/tmp/probe.md"}}
qwen3-coder   → content: {"name":"read","arguments":{"filePath":"/tmp/probe.md"}}
```

Correct tool, correct argument name, correct path — in `content` rather than `tool_calls`.

**One cause is a packaging bug.** Qwen3-Coder's documented format is
`<tool_call><function=name><parameter=key>value</parameter></function></tool_call>`. The unsloth
GGUF ships a template containing `<tool_call>` but **neither `<function=` nor `<parameter=`** — a
Qwen2.5-era template. The model is instructed in a format it was not trained to emit and falls
back to bare JSON. Worth reporting upstream.

**A shim fixes this at the API layer.** `tools/toolcall-shim.py` proxies ollama, parses a tool
call out of `content`, and promotes it into `tool_calls`. It only promotes a call whose name
matches a tool the request actually offered, so incidental JSON in prose is untouched. Verified
with curl for both qwen models: `tool_calls: PRESENT`.

**It now works inside opencode.** Qwen3-Coder-30B-A3B returns a real `tool_use` with
`status: completed` and the file's contents, and gemma — the control that previously failed
through the shim — works through it too.

Getting there needed the route that was recommended over guessing: read what
`ollama-ai-provider-v2` actually parses. Two independent bugs were found, and the distinction
matters because both produced the identical symptom of opencode hanging with no error and no
output.

**Bug 1 — `arguments` must be an object, not a JSON string.** The OpenAI wire format serialises
tool-call arguments; ollama's does not. The provider validates every NDJSON line against a zod
schema declaring `arguments: z.record(z.string(), z.any())`, and
`createNdjsonStreamResponseHandler` *drops* a failing line with nothing but a `console.warn`. The
shim wrote arguments the OpenAI way, so the line carrying the tool call vanished and the client
saw a stream containing only its terminator. Confirmed by running the shim's real output through
that exact schema, loaded from opencode's own installed zod:

```
line 1: DROPPED -> expected record, received string   (the tool call)
line 2: VALID                                         (the terminator)
```

**Bug 2 — the proxy must be threaded.** `HTTPServer` serves one connection at a time and
`protocol_version = "HTTP/1.1"` keeps connections alive, so a single idle connection — which any
pooling client leaves open — blocks every later connection indefinitely. Measured against the old
shim: a second connection opened while the first sat idle received nothing and timed out after 8s.

**This corrects a conclusion recorded here.** "Gemma also fails through the shim, so the fault is
the shim" was the right verdict reached through the wrong single cause. Gemma emits native tool
calls and never touches the promotion path at all; it was being felled by bug 2, sitting
underneath bug 1. Fixing only the visible bug would have left the shim broken and looked like
proof the approach could not work.

`tools/shim-selftest` checks both, each against the exact failure it targets, rather than asking
whether the shim broadly works.


### gpt-oss-20b-Coding-Distill — two packaging defects, then a real one

`hf.co/mradermacher/gpt-oss-20b-Coding-Distill-i1-GGUF:Q3_K_M` returned an empty string to every
prompt: no content, no tool call, no thinking, three tokens generated. That is not a model
verdict, and the void rule says find the cause before recording one.

**Defect 1 — the chat template is corrupted.** It renders the user turn as

```
{{ if .Prompt }}tart|>user<|message|>{{ .Prompt }}<|end|>{{ end }}
```

`tart|>` — the leading `<|s` is missing from `<|start|>`. The assistant turn then opens with
`<|message|>` directly, skipping the `<|channel|>` that harmony requires.

**Defect 2 — the stop list contains `<|message|>`.** Ollama derives stop strings from the
template, so the corruption propagated: the parameters include both `<|message|>` and the same
mangled `tart|>user<|message|>`. Generation halts at the first message delimiter, which is why
nothing ever came back.

Both are repairable. Build from the **raw GGUF blob** with ollama's official harmony template
harvested from `gpt-oss:20b` — not `FROM` the ollama model, because `PARAMETER stop` appends and
the broken stops are inherited, whereas building from the blob re-derives them from the correct
template. After that the model advertises `tools`, generates normally, and is **100% GPU resident
at 32k** with 1.6 GB spare.

**After the repair it passes the tool-call gate**, emitting a native call:

```json
{"name": "read", "arguments": {"filePath": "/tmp/probe.md"}}
```

Official `gpt-oss:20b` behaves the same and is also 100% resident, so it makes a useful control
for whether the distill fine-tune costs anything.

> **A wrong verdict recorded here, and how it happened.** This model was first written up as
> failing the tool-call gate "and not from confusion" — its reasoning trace said *"Use the
> `commentary` channel for tool calls"* and then appeared to stop. That was wrong. The first probe
> gave the tool a terse one-line description and drew a blank; the follow-up probe actually
> returned `tool_calls` in the message, and the value was never printed before the reasoning trace
> was read as the whole story.
>
> One probe is not a gate. The probe in `.handoff/bin/setup-local-model` requires a marker to come
> back through a real tool execution precisely so that a blank cannot be mistaken for a refusal —
> reading a raw API response by eye bypasses that and is how this went wrong.

---

## 2. Residency — a partial offload costs throughput, and sometimes everything

This section used to read *"below 100% GPU, treat it as unusable — not slower, unusable"*. That was
too strong, and round 5 disproved it.

| Build | Weights | Context | Residency | Outcome |
| --- | ---: | ---: | --- | --- |
| Devstral Q4_K_M | 15 GB | 16k | 69% GPU | correct code, truncated before its report |
| Devstral UD-Q3_K_XL | 12 GB | 32k | 72% | 17 GB footprint |
| Devstral UD-Q3_K_XL | 12 GB | 16k | 85% | **101 minutes, zero files written** |
| gemma4:12b | 7.6 GB | 32k | **100%** | completes in 77–149s |
| gpt-oss:20b | 13 GB | 128k | **84%** | **7/7 in 60s**, and again 7/7 in 406s |

The last two rows are the point. At essentially the same offload — 85% and 84% — one model wrote
nothing for an hour and a half and another produced a byte-perfect patch in a minute.

**What the offload reliably costs is throughput, roughly in proportion to the layers moved.**
Measured on gpt-oss with everything else held constant: **61 tok/s at 100% GPU, 43 tok/s at 84%**.
That is a ~30% tax, not a cliff.

So Devstral's collapse was not "15% offload" as a general law. It was that model, that
quantisation, or the far larger prompt an editing task builds on a 24B — and the evidence never
separated them. Treat residency as a **cost to price in**, and measure the specific model rather
than assuming the cliff.

One thing the offload did **not** buy was reliability: 2/5 against 1/5 at n=5 is a single run, and
the extra context it unlocked was never used (peak 17k of 131k granted). Buy an offload for
context you will actually consume, not on faith.

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


### It patches correctly — and deletes the line it patched next to

The greenfield/edit split above is real but the **mechanism was wrong**, and this is the more
useful finding.

Given a surgical task — add a property, a setter, and change one line in a 70-line class —
Gemma produced genuinely small diffs: **+8/−3** and **+9/−4** lines, one file touched. It does
not regenerate files. It patches.

But both runs deleted an adjacent line at the insertion point:

```diff
-    /** @var array<int, array{description: string, quantity: int, unit_price: float}> */
-    private array $lines = [];
+    private float $discountRate = 0.0;
+
+    public function setDiscountRate(float $rate): void { ... }
```

The `$lines` declaration was **replaced** rather than added alongside. Reproducible, 2 for 2.

**Why this is worse than a crash.** The functional verification passed on both runs:
`subtotal()` returned 22.50, `total(0.2)` returned 27.00, exit 0. PHP falls back to a dynamic
property, so the class still works — with a deprecation notice — and **will break outright in
PHP 9**. A test suite would be green. Only a byte-identical check on untouched regions catches it.

**And note which half it got right.** The plan contained a semantic trap: `tax()` and `total()`
already build on `subtotal()`, so applying the discount again in `total()` would double-count it
and still parse. Gemma avoided that on both runs. It got the *reasoning* right and the
*mechanical* part wrong — the opposite of the usual assumption about small models.

**Consequence for routing:** "no edits" is too blunt. The requirement is a gate that asserts
**regions the plan did not name are byte-identical**. With that, surgical edits become viable
work for a local model. Without it, they silently degrade a codebase in a way tests do not catch.

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

**Score an empty diff as zero.** "The file parses" passes trivially on an unmodified tree, so a
run that did nothing collected 1/6 rather than 0/6 and sat above the floor in the results table.
Devstral scored exactly that way six times out of six while changing zero bytes. A criterion a
do-nothing run can satisfy is not measuring the model. `bench/run` now forces criteria to zero on
an unchanged tree and reclassifies a `complete` report over an untouched tree as `false-success`,
so fabrication is counted as fabrication rather than as a weak pass.

**Enforce the patch-only contract in the harness, because the client will not.** A tracked file
that loses more than half its lines, or whose change removes more lines than the file originally
had, is treated as regenerated rather than patched and the round is not green.

> Tested and does not work: **opencode's permission config does not block tools in `run` mode.**
> A project-level `opencode.json` with `"write": "deny"` was ignored — the file was created. So
> was `"edit": "deny"`. Preventive tool restriction is therefore unavailable in opencode 1.17.4,
> and patch-only has to be detection-and-reject after the round rather than prevention during it.
> Worth re-testing on a later version before assuming it still holds.

**Keep three prompt layers apart.** Benchmark findings (this file) are for the maintainer and are
never shown to a model under test — telling a model which mistakes it is expected to make
contaminates the measurement. `templates/agent-rules.md` is a short, task-independent operational
prompt sent as developer instructions. The plan is the task and only the task. Only the rule
headings from the rules file travel to the model; the rationale table stays behind.

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

## 7b. How gpt-oss tool calling actually fails

Worth its own section because four plausible explanations were wrong before the real one turned
up, and each wrong one was stated confidently.

**The error belongs to ollama, not the client.** `error parsing tool call: raw='{"input":"*** Begin
Patch..."}]'` is an **HTTP 500 from ollama**, which the client merely relays. Reproduced with a
plain `urllib` call and no client anywhere in the picture —
`tools/repro-ollama-toolcall-500.py`. Ollama fails to parse a tool call **its own model just
generated**.

**What the model emits is array-wrapped.** The payload is `[{"input": "..."}]`; ollama consumes
the object and then trips on the trailing `]`, hence *"invalid character ']' after top-level
value"*.

**Three conditions must coincide.** Remove any one and it stops:

1. an `apply_patch`-style tool — one freeform string argument carrying a whole patch,
2. a conversation already containing an assistant tool call and a substantial tool result,
3. a long tool description.

**The description is a measurable trigger.** Same model, same conversation, varying only that
string:

| `apply_patch` description | API-level failures |
| --- | ---: |
| Cline's shipped text, 1224 B with worked examples | **2/5** |
| a 105 B replacement | **0/5** |

End to end through Cline, with the proxy shortening it: **3/4 runs produced a correct patch against
a 1/3 baseline**. Parse errors still occur; what changes is that the model recovers within the
client's retry budget instead of giving up. So this is mitigation, not a cure.

**Why opencode is unaffected.** It ships no `apply_patch`. gpt-oss tries it anyway, opencode
rejects it as unknown, and the model falls back to small `edit` calls of 22–181 B that never hit
the bug. That is luck of tool inventory, not superior handling.

### llama.cpp does not reproduce it — the engine is the boundary

Same official weights (`ggml-org/gpt-oss-20b-GGUF`, MXFP4), same `apply_patch` schema including the
1224-byte description, same multi-turn conversation, served by `llama-server` b10331 with `--jinja`:

| | ollama | llama.cpp |
| --- | ---: | ---: |
| Tool calls valid at the API | 2/5 malformed, HTTP 500 | **8/8 valid** (incl. 693/717/818 B) |
| Correct patch through Cline | 1/3 | **4/4** |
| Multi-file plan, nine criteria | not reached | **4/4 at 9/9, all first attempt** |
| Generation throughput | 61 tok/s | 60 tok/s (n=94) |

Throughput is a **wash** — an earlier claim of ~20% faster came from two unrepresentative log
lines and is withdrawn. The engine buys correctness, not speed.

**Consequences, all of which reverse earlier conclusions here:**

- Every gpt-oss result obtained through ollama is **void** as a model measurement, including the
  offload comparison, which is therefore unresolved again.
- "gpt-oss is client-fragile" is withdrawn. It is *ollama*-fragile.
- The proposal to replace freeform `apply_patch` with small targeted edits is **withdrawn**. The
  identical tool and payload sizes work once the serving layer is correct; changing tool inventory
  now would add a variable for no measured benefit.
- The missing piece was a protocol boundary between client and model, and it already exists —
  llama.cpp provides it. No harmony shim needs writing. The adapter's job is narrow: pin the server
  configuration, health-check it, keep logs, run a conformance probe, and map provider errors into
  the result taxonomy.

**Pin the pairing.** "gpt-oss" now names several serving stacks that behave differently, so every
run records engine, build, model-file digest, context, KV type, GPU layers, client, client version,
reasoning level and tool-schema identity (`manifest.json` per result). Without that, the next
provider regression gets attributed to the model — the exact mistake this section undoes.

### Four explanations that were wrong

Each was plausible, each was measured, each failed:

| Hypothesis | How it died |
| --- | --- |
| Argument size breaks serialisation | 2,858 B parsed fine; failures happen at 700 B |
| Tool-list bloat (18 of 25 tools are `team_*`) | Stripped them — 2 of 3 runs still failed |
| `think: false` on a reasoning model | 1/3 with reasoning on, 1/3 with it off |
| Cline's response parser | Reproduced against ollama's API with no client present |

The lesson is the project's own rule, applied to a component rather than a run: a symptom seen
only through a client says nothing about where the defect lives until it is reproduced without one.

### And a fifth: "the model sometimes returns no final message"

This one survived longest because it looked like model behaviour and appeared under two different
models. Runs kept producing a byte-perfect tree and no usable report, and the working theory was
that the model occasionally just stopped talking.

**It is three things, and the theory was closest to the first.** `tools/final-turn-shape` reads
Cline's event stream and reports whether a `text` block arrived in each attempt. Over the first
nine runs of round 6 the split is perfect — 11 attempts ending `tool, text, reasoning` all
completed, 3 ending `reasoning, tool, reasoning` all errored:

1. **The model does stop talking.** It ends its last turn having produced reasoning and a tool
   call and *no text block at all*. Cline reports *"does not match the expected peg-native
   format"*, which reads like a malformed reply and is really an absence. So the original theory
   was right about the symptom and wrong about it being unfixable.
2. **The retry that exists to recover from that never ran** — `--id` is incompatible with `--json`
   plus a prompt argument, so it died instantly on an empty prompt. 25 of 61 runs.
3. **With the retry running, it answers with `{}`** — because its prompt carries the validation
   error and nothing else, to a fresh session: no schema, no task, no account of the work. The
   `opencode` adapter rebuilds all three; the Cline adapter does not.

Each layer hid the one below it. Only fixing (2) made (3) observable, and only measuring (3) made
(1) provable rather than assumed.

It is an adapter defect. Cline's `--id` is incompatible with `--json` plus a prompt argument in
3.0.52, the adapter passed it on the retry, and the retry died instantly on *"JSON output mode
requires a prompt argument or piped stdin"* — an empty-prompt error, reproduced directly against
the CLI with no harness involved. The prompt-validate retry never ran, not once, so a malformed
final message was always terminal.

**25 of 61 runs with a preserved provider log hit it, and 16 of those had a correct tree.** What
the model actually does is produce output Cline's parser rejects (*"does not match the expected
peg-native format"*), which a working retry is specifically designed to recover from.

The fix existed in the working checkout while every benchmark ran from a clone that never received
it. That is the real finding: two copies of the harness, no provenance recorded anywhere in a
result, and nothing to notice the difference.

---

## 8. What has been tried, and what it was worth

Ranked by measured effect, not by how good the idea sounded.

### Worked

| Change | Effect |
| --- | --- |
| **Output-discipline rules in the prompt** | Gemma 2/5 → 5/5 on unchanged task text, and faster. Devstral 0/5 → 5/5. Still the single most effective change measured. |
| **Turning reasoning off under Cline** | Gemma 0/7 → **7/7**, 801 s → 95 s, three context-limit hits → none. One flag. |
| **Per-model context sizing** | Gemma 32k → 96k recovered 4/5 → 5/5. Under Cline, forcing 128k past its hardcoded 32k removed the failure entirely. |
| **Repackaging a broken GGUF** | gpt-oss Coding-Distill returned an empty string to every prompt; rebuilt from the raw blob with a correct template it generates, calls tools and is 100% resident. |
| **A tool-call shim** | Took the Qwen family from "cannot drive the harness at all" to running. Three separate bugs had to be fixed before it worked. |
| **Scoring an empty diff as zero** | Turned two fabricated successes from a middling `complete 1/6` into `false-success 0/7`. |
| **A byte-identical criterion on unnamed regions** | Catches both collateral-damage variants automatically — gemma deleting the adjacent declaration and gpt-oss merging into it — which the functional tests pass straight through. |
| **Probing before benchmarking** | Rejected three unusable models in about a minute each. |

### Did not work

| Attempt | Outcome |
| --- | --- |
| **Updating ollama, and llama.cpp with `--jinja`** | Neither fixes text-format tool calls. The format is the model's. |
| **Devstral at any quantisation** | Six surgical runs, zero bytes changed, three of them reporting `complete`. |
| **opencode permission config as patch-only enforcement** | `write: deny` and `edit: deny` in a project-level config were both ignored; the file was created regardless. Preventive tool restriction is unavailable, so patch-only is enforced by detection and rejection instead. |
| **Cline's `openai-compatible` path** | Avoids the forced `num_ctx`, but qwen and gpt-oss both fail on it. Only gemma survives. |
| **Cline `--data-dir` for isolation** | Enables a sandbox mode that strips the shell: `ls -la` came back as `Executable not found in $PATH`. Use `--config`. |
| **Cline `--id` for session resume** | Incompatible with `--json` plus a prompt. Declared native on the strength of the help text; it had never been exercised. |
| **A global 128k window** | Sound for gemma (100% resident, 5 GB spare), pushes gpt-oss to 83% and qwen to 74% — where qwen's probe fails outright. Context must be per-model. |
| **Auto-completing truncated tool calls** | Deliberately *not* done. Brace-balancing a truncated payload would turn two failures into passes and let a partial `newString` replace a file with a valid-looking partial copy. |

### Still unresolved

- **Did `q8_0` KV cost quality?** Never varied independently of context.
- **Why did Devstral Q3_K_S time out at 16k** after completing the same task in 39 s at 32k?
- **Why does Cline lose the final assistant message** on runs whose patch is perfect? Several
  rounds produced a byte-perfect tree and no report at all.
- **Is Qwen3-Coder usable?** It passed the Cline gate once and then failed a trivial file-read
  probe three times in four. One clean surgical patch, and nothing reproducible around it.

---

## 8b. The register of wrong conclusions

Kept as prominently as the results, because it is the most reusable thing here. Every entry was
believed, several were written down as findings, and each was overturned by measurement rather
than by argument.

### Wrong about the model, when it was the plumbing

| Believed | Actually |
| --- | --- |
| qwen2.5-coder fabricated a blocker to look diligent | Served at a 4,096-token default; it could not see the plan and said so |
| gpt-oss is client-fragile | Ollama returns HTTP 500 for tool calls its own model generated. Same weights through llama.cpp: 8/8 valid |
| gemma fails through the shim | The shim was single-threaded and wedged by the first idle keep-alive connection |
| The model sometimes goes quiet | Three stacked defects — it does stop talking, the retry meant to catch that never ran, and once running it answers `{}` because its prompt carries no schema and no account of the work |
| Devstral at 85% residency proves partial offload is fatal | gpt-oss at 84% produced a byte-perfect patch in 60s |

### Wrong about what would help

| Predicted | Measured |
| --- | --- |
| Reasoning `off` should be cheaper — the planner already did the thinking | Nominally **26% dearer**, and no better on any axis. Direction backwards |
| Less reasoning means fewer missing final messages | The opposite: 33% at `low`, 40% at `off` |
| Giving the retry ground truth about the tree lets it report honestly | Damage went 1/15 to 4/15. A retry told not to edit any file edits files |
| Richer repair feedback should reduce attempts | Inconclusive — and 20 of the 27-point "effect" was present before the variable applied |
| Token counts will be a lower-variance instrument than wall clock | They are not. Throughput holds a 5.4% band while wall clock spans 4.9x |
| Sampling temperature explains the run-to-run spread | Deterministic sampling made spread **wider**: CV 61% to 76% |
| Asserting original lines keep their order closes the mis-placed-insertion hole | It does not. Nothing is deleted or reordered by an insertion; a hunk bound is what constrains it |
| The malformed control tokens the parser discards are a sampling artifact — the server runs at temperature 0.8, a creative-writing default | No. At `--temp 0 --top-p 1 --top-k 0 --seed 42`, 3/8 rounds still lost their report against a 33% baseline, and the completion-level rate was unchanged at 1.17% against 1.11%. Greedy decoding produces the same malformed harmony, so no sampler setting avoids it — and the fault is deterministic, which is what makes it reportable |
| Telling the model to run the syntax checker after every write will catch truncation while it is still repairable | n=20 per arm: **damage identical at 5/20**, every outcome measure indistinguishable, 38% slower and 37% more tokens. Second prompt-layer variant to move nothing. Instructions are not a mechanism |
| Money and aggregates are where this model breaks down | Not when the arithmetic is specified. Five of five implementations of integer proration with largest-remainder allocation were correct under 4000 randomised trials each, including the tie-break and an odd-divisor rounding edge the plan never spelled out. The greenfield 0/7 was about deciding, not computing |

### 8c. Why the model calls a tool instead of reporting — measured directly, 2026-08-11

`tools/report-probe` provokes the final turn in isolation: sixteen samples, about two minutes,
against `bench/run`'s forty minutes for eight rounds. Every cell below is n=16 at temperature 0.8,
same conversation, same schema.

| The report turn is asked with | reports cleanly | calls a tool instead | no answer at all | HTTP 500 |
| --- | ---: | ---: | ---: | ---: |
| tools registered, free choice *(what the harness does)* | 44% | **56%** | 0 | 0 |
| the same, with `tests_run` dropped from the schema | 56% | 44% | 0 | 0 |
| verification results supplied, nothing forbidden | 56% | 44% | 0 | 0 |
| `tool_choice: "none"` | 38% | 0 | **62%** | 0 |
| "Do not call any tool" in the prompt | 75% | 0 | 0 | **19%** |
| **both — results supplied AND tools forbidden** | **88%** | 12% | 0 | 0 |
| no tools registered at all | **100%** | — | 0 | 0 |

**The model is not ignoring the instruction. It is obeying a different one — ours.** The report
schema asks it to attest to `tests_run` and `files_changed`; `templates/agent-rules.md` tells it
never to claim a command passed unless it ran it. So at report time it goes to establish ground
truth. Its own reasoning, captured from a raw response:

> *"We need to fill status, summary, files_changed, tests_run, deviations, blockers. We should run
> tests to see if any failures. Let's run tests."*

**Forbidding the tool at the API level is worse than allowing it.** `tool_choice: "none"` produces
silence, not reports: `finish_reason: stop`, ~105 tokens of reasoning, empty content. The model
resolves "I must verify" against "I cannot act" by stopping rather than by answering. That is the
obvious flag to reach for and it makes the problem worse.

**The tension is what produces malformed harmony.** Prohibiting tool calls in the prompt without
removing the reason to make them yields 19% HTTP 500 *"output does not match the expected
peg-native format"* — the parse fault, induced deliberately, **at 666 tokens of context.** Supplying
the verification results as well removes the conflict and the 500s vanish.

That last point corrects §3's reading of the depth table. The production correlation between
conversation depth and parse failures is real, but depth is a *proxy*: a deep conversation is one
where the model is being pushed to conclude while it still wants to act. The fault can be produced
at 666 tokens by creating that conflict directly. Smaller steps still help — they reach the
conclude-or-act moment with less accumulated pressure — but "keep the conversation shallow" is the
symptom's lever, not the mechanism's.

### Wrong for a long time about the two loudest numbers, 2026-08-11

Both were attributed to the model for weeks. Both are the serving stack, and both were sitting in
`llama-server`'s own log under a warning nobody read. `tools/peg-audit` now reads it.

| Believed | Actually |
| --- | --- |
| Roughly a quarter of rounds end with the model declining to write a report | The report is written **in full**, and llama.cpp's harmony parser discards it — addressed to the `final` channel with a `<\|constrain\|>JSON` tag instead of emitted as a tool call. Across 48 runs the signature was identical every time: attempt 1 finishes in error with no text block, attempt 2 completes |
| The retry recovers those rounds | **22 of 48 runs spent a second attempt and 15 still ended without a report.** Around 40% of runs paid double for a defect no retry can address |
| Tool-call corruption is an intermittent adapter fault, depressing every arm uniformly | Two distinct faults with different fixes, cleanly separated by conversation depth: reports discarded shallow, harmony headers transposed deep |
| Context window size is a variable worth an arm | It is not. 96k against 128k moved nothing (1.11% against 1.32% discarded). **Conversation depth** is the variable: 0.00% below 16k, 2.17% at 32–48k, up to 6.06% above 48k. A conversation reaching 50k fails the same under either ceiling |
| Upstream has probably fixed the harmony parsing by now | Asserted with no evidence, in a commit message. The 26 builds between `b10331` and `b10357` touch `common/chat.cpp` **only** for an unrelated chat template. Check the diff before recommending an upgrade |

The last row is the one to remember. The other five were overturned by measurement; that one was an
invention that survived a commit message because it sounded like the kind of thing that is true.

And one more, from the same afternoon:

| Believed | Actually |
| --- | --- |
| Changing the channel the report is asked for cannot help, because the parser cannot map what the model produced either way | Backwards. The GGUF's chat template contains no `<\|constrain\|>` in 16,616 characters and puts `to=` before the channel token; the model emits `<\|constrain\|>` and puts the channel first. It was trained on one harmony dialect and prompted in another. `<\|constrain\|>json` is legal **only on a tool call** — so asking for the report as a tool call is the one change that puts the model's own instinct onto a parseable path. Round 10 had already measured 1/12 against 4/15 and it was dismissed as coincidence |

The lesson is narrower than "check your assumptions". It is that a mechanism was declared —
*the parser cannot map the output* — without reading the thing that decides it, which was one HTTP
request away the whole time: `GET /props` returns the chat template.

### Wrong about the benchmark, which was scoring the model down for obeying it

`templates/agent-rules.md` grants the model `.handoff/scratch/` in as many words — *"that directory
is yours, it is ignored by the verifier and by git."* `tools/verify-round` excluded it. `bench/run`
did not, and nothing compared the two.

**8 of 40 runs were recorded as `patch-damaged` for creating files they were explicitly permitted to
create**, dropping the measured usable-tree rate from 90%/100% to 75%/75%. `bench/summary`'s second
opinion had already flagged all ten disagreements in its own output; nobody read that either.

Same shape as `tools/check-plan` and `bench/run` once parsing plans with separate copies of the same
expressions. Two tools that judge the same artifact must be tested against each other, not only
against their own idea of correctness. `tools/smoke-e2e` now does that.

### Wrong about the harness, by the harness's own author

Written the same day, each caught by testing the guard against the exact failure it targets:

- A conformance probe that printed `CONFORMANCE OK` over **zero tool calls** — the precise failure
  it existed to catch, one level up.
- A line-boundary assertion in a selftest that passed vacuously; the check that caught the mutation
  was a different one.
- A process-group kill that signalled the wrong pid, and a test that passed because the process had
  detached rather than because it had died.
- Two `pgrep -f` waiters that matched their own command line and could never exit; the same mistake
  as `pkill -f` killed a shell.
- A verifier that failed a round because it had run before, counting its own earlier output as a
  file the model invented.

**The pattern worth extracting.** Every one of these was found by asking *could something other
than the model have produced this?* — and none by inspection or reasoning. A guard that has not
been run against the failure it was written for is an assumption wearing a test's clothes.

---

## 9. Harness improvements

### Landed

| Change | What it fixed |
| --- | --- |
| Empty diff scores zero; `complete` over an untouched tree becomes `false-success` | Two fabricated successes were scoring a middling `complete 1/6` |
| Patch-only gate — over half a file's lines lost, or more removed than existed | Whole-file regeneration passed silently |
| Checklist and command counts must match | `surgical-discount` capped every model at 2/6 by construction |
| Plan asserted readable in the worktree before the run | "Plan file does not exist" has been both true and fabricated |
| Driver runs in its own process group, killed as a group | An orphaned agent CLI outlived a timeout and competed with the next repetition |
| Adapter logs stream to disk as they arrive | A timed-out run preserved no provider log at all |
| Repair loop, capped at 3 attempts, fed the harness's own failing-command list | First-pass success was the only thing measurable |
| Per-result `manifest.json` — engine, build, model digest, context, KV, client, reasoning | "gpt-oss" names several serving stacks that behave differently |
| Byte-identical criterion on unnamed regions | Catches collateral damage that functional tests pass straight through |
| Outcome taxonomy derived from the tree, not the report | A byte-perfect patch with no final message scored identically to a run that changed nothing |
| Repair feedback rendered by `tools/render-feedback`, with an optional `full` level | The retry saw only exit codes: not the error text, and not what it had already changed |
| Token accounting per run, summed across attempts, from llama-server's own timing records | Cost to an accepted patch had every input except the one that varies most |
| `tools/harness-selftest` — the whole harness end to end against a provider that runs no model | Harness bugs presented as model failures, which is what cost this project its longest investigation |
| `harness_commit` / `harness_dirty` in every metrics file, and `tools/sync-bench-clone` | The clone benchmarks run from drifted from the working checkout for hours; 25 of 61 runs exercised a bug already fixed elsewhere, and no result said which harness produced it |
| `tools/check-no-ghosts`, run before every round | An agent process left in a deleted worktree still holds the model and still generates — twice read as a model collapsing, and now it would also be charged to another run's token count |
| `tools/engine-conformance` — is the stack emitting usable tool calls, before the round starts | A benchmark cannot tell an engine regression from a model regression; not having this is why every ollama-served gpt-oss result is void |
| `bench/compare` — Fisher, Mann-Whitney, and the attempt-1 control | Two dramatic findings dissolved under it. Significance is the wrong test for the control: a 20-point noise floor at p = 0.36 was three quarters of a "result" |
| `bench/summary` — cost per usable patch, failures charged to the successes | "15/15 correct" read as uniform when one run cost 5.7x the others and three had changed files the plan never named |
| `tools/final-turn-shape` — why a run produced no report | Turned the project's longest-standing unexplained outcome into a mechanism: the turn ends with no text block at all |
| Verifier verdict narrowed to the plan's commands plus scope | Across 68 bundles the harness's own gates caught one thing the plan had not. The rest were re-deciding what the plan already decided |
| `handoff do` verifies on completion and folds the verdict into its exit status | The benchmark had a gate the actual tool did not: real runs printed a diff and exited with whatever the provider returned |
| Agent rules ban self-written verification scripts | 13 invented across the rounds; one run produced seven and never cleaned them up |
| `tools/llamacpp-serve` takes sampling flags | The stack had served at a creative-writing profile — temp 0.8, random seed — for every measurement ever taken here, unexamined |

### Open

Moved to [docs/roadmap.md](roadmap.md), which carries enough reasoning on each to pick it up cold.
Summarised here so this section is not a dead end:

1. ask for the report through the channel that works — built, opt-in, unmeasured. The model emits
   tool calls reliably and final text unreliably; this is the largest available win
2. converge `verify-round` and `bench/run` into one gate implementation — lower priority than it
   looked, since the two agreed on 22 of 23 runs carrying an evidence bundle
3. run `bench/plans/semantic.md` against a model. Written and validated, never run. It is the only
   plan here where a plausible wrong answer survives review, and therefore the real test of the
   gates
4. a plan the model reliably fails once, so an A/B on the repair loop has more than a handful of
   informative runs
5. `bench/validate-plan`, so the reference/trap/do-nothing check the methodology requires is a
   command rather than a good intention

### Previously listed here, in detail

**1. A conformance gate for the serving stack.** The highest-value item. Turn
`tools/repro-ollama-toolcall-500.py` into an engine-neutral probe — first-turn call, a call after
a substantial tool result, the real `apply_patch` schema, short/medium/~1 KB arguments, streamed
and non-streamed, a reused connection — and run it whenever the engine build, GGUF, template,
client version, context or tool-schema hash changes. That converts "llama.cpp works today" into an
enforced property. Without it, a silent engine regression is indistinguishable from a model
regression, which is precisely the trap this project just spent a long time in.

**2. A result taxonomy that does not collapse.** Four outcomes are currently flattened toward one:

- protocol failed before execution
- protocol fine, patch wrong
- protocol fine, patch correct, **final report missing** ← several perfect trees scored as failures
- protocol fine, patch correct, reported

The third is a re-ask; the second needs a human. On a cost-to-accepted-patch metric they are
nothing alike, and today both read as `report-unparseable`.

**3. Cost to an accepted patch.** The metric the project exists to optimise, still not computed.
Attempts, wall clock, throughput and context are all recorded now; nothing multiplies them.

**4. Criterion 7 cannot see a mis-placed insertion.** It verifies no original line was deleted or
altered, and gemma once split a method signature from its body by inserting *between* lines —
which passed. Asserting original lines keep their relative order would close it.

**5. `providers/opencode.sh` still buffers its log** and loses it on timeout, exactly as the Cline
adapter did before that was fixed.

**6. Raise repetitions to 15+** for a model that survives screening. Most gaps reported at n=5 here
are one or two runs wide.

**7. A semantic-risk task class** — aggregate SQL, money, dates, permissions, concurrency — where a
plausible wrong answer is indistinguishable from a right one on review.

**8. Investigate the missing final message.** Several runs produce a byte-perfect tree and no
report at all, under both gemma and gpt-oss. It is the single most common non-model failure left.

---

## 9b. Model and engine work

- **Does reasoning help once it has room, and what does it cost?** Reasoning off won decisively at
  32k, but that comparison was confounded by the window, and under ollama it was buried in engine
  noise. Measurable for the first time now that the tool-call path is clean.
- **Re-run the residency/offload question.** Its only evidence came through ollama and is void.
- **Isolate ollama's defect to rendering or parsing** before proposing a patch. Capture the raw
  generated stream from each engine at the same boundary — llama.cpp with `--skip-chat-parsing`,
  ollama immediately before `builtinParser.Add`. If only ollama's stream contains the array, the
  fault is upstream of the parser and an "unwrap arrays" fix would be wrong.
- **Report the two GGUF packaging bugs upstream.** unsloth's Qwen3-Coder ships a Qwen2.5-era
  template; mradermacher's gpt-oss Coding-Distill ships a template with a literal typo and a stop
  list that halts generation after three tokens. Both silently degrade the model for everyone.
- **Try Qwen3-Coder at a larger quantisation** if the card ever allows it. Q2_K is aggressive and
  its one clean patch was as good as anything measured.
- **Test-first delegation** — hosted model writes the acceptance tests, local model iterates to
  green — remains the most promising token-saving structure and is still untried.

---

## 10. Setup checklist for a new model

### Serve it with llama.cpp — this is the recommended path

Ollama is documented below because most of this project's history ran on it, and because its
tooling for inspecting a package is genuinely useful. It is no longer the recommended way to serve
a model for real work.

The reason is measured, not stylistic. Same official gpt-oss weights, same tool schema, same
conversation:

| | ollama | llama.cpp |
| --- | ---: | ---: |
| Tool calls valid at the API | 2/5 malformed, HTTP 500 | **8/8** |
| Correct patch through the client | 1/3 | **4/4** |
| Four-file architectural task | not reached | **15/15 at 9/9** |
| Generation throughput | 61 tok/s | 60 tok/s |

Throughput is a wash. What llama.cpp buys is a tool-call path that works.

```bash
# 1. get a GGUF that llama.cpp can actually load — from Hugging Face, not from ollama's blob store
curl -fL -o ~/.cache/agent-handoff/models/<model>.gguf \
  "https://huggingface.co/<org>/<repo>/resolve/main/<file>.gguf"

# 2. serve it, pinned
tools/llamacpp-serve start <model> 65536
tools/llamacpp-serve status

# 3. point the client at it
cline auth -p openai-compatible -m <model> -b http://127.0.0.1:8071/v1 -k dummy \
  --config ~/.cline-llamacpp

# 4. probe before benchmarking: a real tool call, after a tool result, with a large argument
tools/engine-conformance --engine llamacpp --model <model> --repeat 2
```

`engine-conformance` is the one to run. It covers a first-turn call, a call after a 20 KB tool
result, a ~1 KB `apply_patch` argument, a streamed turn and a reused connection, and it fails
loudly rather than quietly when the engine never produced a tool call at all — a state its own
first version reported as a pass. `repro-ollama-toolcall-500.py` remains as the minimal
reproduction of ollama's specific defect, for filing upstream.

Expect on llama.cpp b10331 with gpt-oss-20b MXFP4: `CONFORMANCE OK`, 14 turns, 12 of them
`apply_patch`.

> **Ollama's blobs are not portable.** Its `gpt-oss:20b` declares model architecture `gptoss`, and
> llama.cpp rejects it with `unknown model architecture`. The Hugging Face build declares
> `gpt-oss` and loads. Download the weights again rather than reusing the blob store.

Pick the largest window that stays **100% GPU-resident**, and verify it — for gpt-oss on a 16 GB
card that is 64k, which also clears the ~36k a multi-file plan actually consumes. 128k buys
nothing this workload uses and costs about a third of throughput.

### Serving with ollama

Still the quickest way to *inspect* a package, and fine for models whose tool calls it handles —
gemma works well through it.

```bash
ollama show <model> | grep -A6 Capabilities     # 'tools' present? necessary, not sufficient
ollama show --template <model>                  # read it — corruption here looks like incapacity
ollama show --parameters <model>                # a stop string that appears mid-turn kills output
# probe: write a file, ask the model to read it, require the marker back
printf 'FROM <model>\nPARAMETER num_ctx 32768\n' > Modelfile && ollama create <name> -f Modelfile
ollama ps                                        # demand 100% GPU
```

Register the same context in the client's config as well as baking it. Then benchmark — and only
then.

Two ollama-specific hazards worth knowing before you attribute anything to a model:

- **Cline overrides the baked context**, sending `num_ctx: 32768` regardless. `tools/ollama-ctx-proxy.py`
  rewrites it per model.
- **gpt-oss tool calls are corrupted** on this path, returning HTTP 500 for the model's own valid
  output. See §7b; this is why llama.cpp is recommended.

**Read the template and the stop list before concluding anything.** Three of the models tested
here were blocked by packaging rather than capability, and each looked like a different kind of
model failure from the outside: one emitted correct tool calls as text, one shipped a chat
template for the wrong model generation, and one shipped a template with a typo plus a stop list
that halted generation after three tokens.

**Repairing a broken package.** Harvest a known-good template from a correctly packaged build of
the same architecture and rebuild from the raw GGUF blob:

```bash
ollama show --template <good-model> > harmony.tmpl
BLOB=$(python3 -c "import json;print([l['digest'].replace(':','-') for l in \
  json.load(open('<manifest-path>'))['layers'] if l['mediaType'].endswith('.model')][0])")
{ echo "FROM /usr/share/ollama/.ollama/models/blobs/$BLOB"
  echo 'PARAMETER num_ctx 32768'
  printf 'TEMPLATE """'; cat harmony.tmpl; printf '"""\n'; } > Modelfile
ollama create <name> -f Modelfile
```

Build from the **blob**, not `FROM <ollama-model>`. `PARAMETER stop` appends rather than replaces,
so a derived model inherits the broken stop list and stays broken; building from the blob makes
ollama re-derive the stops from the template you supplied. Verify with
`ollama show --parameters <name>` that the bad entries are gone.
