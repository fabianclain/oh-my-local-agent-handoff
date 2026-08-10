# Using agent-handoff on a new project

## One-time setup

```bash
git clone https://github.com/fabianclain/agent-handoff ~/dev/agent-handoff
echo 'export PATH="$HOME/dev/agent-handoff/bin:$PATH"' >> ~/.bashrc
source ~/.bashrc
handoff            # prints usage — confirms it is on PATH
```

### Providers

You need at least one implementer CLI installed and authenticated.

**Codex** — install per [openai/codex](https://github.com/openai/codex) and log in. Nothing else
to configure; `codex` is the default provider.

**A local model** — free to run, and good enough for well-specified work. Install
[Cline](https://github.com/cline/cline) (`npm i -g cline`) and a llama.cpp build, then:

```bash
# weights from Hugging Face — ollama's blobs declare a non-standard architecture and will not load
mkdir -p ~/.cache/agent-handoff/models
curl -fL -o ~/.cache/agent-handoff/models/gpt-oss-20b-MXFP4.gguf \
  "https://huggingface.co/ggml-org/gpt-oss-20b-GGUF/resolve/main/gpt-oss-20b-MXFP4.gguf"

tools/llamacpp-serve start gpt-oss-20b 65536      # pins the stack; one model at a time

cline auth -p openai-compatible -m gpt-oss-20b \
  -b http://127.0.0.1:8071/v1 -k dummy --config ~/.cline-llamacpp

HANDOFF_PROVIDER=lcgptossl handoff do <slug>
```

Serve it with **llama.cpp rather than ollama**. On identical weights and tool schemas, ollama
returns HTTP 500 for tool calls its own model generated: 2/5 malformed against 8/8, and 1/3
correct patches against 4/4. Throughput is the same either way, so there is nothing to trade off.
Ollama is still fine for models it handles cleanly — gemma runs well through it — and its
`ollama show --template/--parameters` remain the quickest way to inspect a package.

Read [docs/local-models.md](local-models.md) before trusting output from any local model. Its
defects are quiet: patches that pass every functional test while deleting the declaration beside
the insertion point, and reports of success over an untouched tree.

**GLM** — no separate CLI exists. Zhipu's ZCode is a desktop app, not scriptable. GLM runs
through the Claude Code binary pointed at z.ai's Anthropic-compatible endpoint, which is the
path z.ai documents. Install Claude Code, get a key from the z.ai platform, then:

```bash
mkdir -p ~/.config/agent-handoff && chmod 700 ~/.config/agent-handoff
cat > ~/.config/agent-handoff/glm.env <<'EOF'
export ANTHROPIC_BASE_URL="https://api.z.ai/api/anthropic"
export ANTHROPIC_AUTH_TOKEN="your-z-ai-key"
export ANTHROPIC_DEFAULT_OPUS_MODEL="GLM-5.2"
export ANTHROPIC_DEFAULT_SONNET_MODEL="GLM-5.2"
export ANTHROPIC_DEFAULT_HAIKU_MODEL="GLM-4.7"
EOF
chmod 600 ~/.config/agent-handoff/glm.env
```

**Keep this outside every repository.** The `glm` provider reads it automatically; nothing needs
to be committed anywhere. Rotate the key if it has ever appeared in a chat transcript, a shell
history, or a screen share.

> **Note:** setting `ANTHROPIC_BASE_URL` globally in your shell would route *all* Claude Code
> usage through z.ai, including interactive sessions. The `glm` provider sources these variables
> only for the duration of a run, which is why the file is not sourced from `~/.bashrc`.

## Per-project setup

Two files, once per repository.

```bash
cd your-project
mkdir -p .handoff/plans
cp ~/dev/agent-handoff/templates/config.sh .handoff/config.sh
printf '\n/.handoff/runs/\n' >> .gitignore
```

Then edit `.handoff/config.sh`. This is the highest-leverage file in the whole setup — it is
injected into every implementer prompt, and without it the implementer cannot know how your
project builds, tests, or formats. Expect to spend review rounds on avoidable churn if you skip
it.

```bash
read -r -d '' PROJECT_RULES <<'RULES' || true
Project conventions:
- Format with `<formatter>` before finishing. This is mandatory.
- Generate files with `<scaffolding command>`, non-interactively.
- Tests live in `<path>` and run with `<command>`.
- <Any architectural rule not obvious from reading one file.>
- <Any trap that has bitten before — these are the most valuable lines here.>
RULES
```

If your plans already live somewhere else, point at it rather than moving them:

```bash
HANDOFF_PLANS_DIR="$REPO_ROOT/.claude/plans"
```

### Traps worth encoding

The last bullet matters more than it looks. Real examples from projects using this:

- *"Never run the browser test suite in a foreground shell — its server child inherits stdout and
  the run never returns."* Without that line, every round hangs.
- *"Do not change dependencies."* Once a sandbox has network access this is a rule the
  implementer is asked to follow, not a boundary the OS enforces.

## Running

```bash
handoff do <slug>                              # default provider (codex)
HANDOFF_PROVIDER=glm handoff do <slug>         # same plan, GLM implements
HANDOFF_PROVIDER=glm handoff resume <slug>     # feed back review comments
handoff diff <slug>                            # exactly what changed
handoff verify <slug>                          # re-run the gates over the tree
```

`do` verifies when it finishes and folds the verdict into its exit status, so a round the gates
reject exits non-zero even when the provider exited cleanly. `HANDOFF_NO_VERIFY=1` suppresses it,
for callers that run the same gates themselves.

Provider is chosen per invocation, so you can mix freely across rounds — but **resume must use
the same provider as the original run**, since the session id belongs to that provider.

### Choosing a provider

| | codex | glm | opencode |
| --- | --- | --- | --- |
| structured output | native | native | prompt-validate |
| session resume | native | native | native |
| sandbox | native (OS) | weak (permissions) | none |

The driver prints any non-native capability at dispatch. It is not decoration: a
prompt-and-validate JSON round is a weaker guarantee than a schema-enforced one, and a
permission-mode sandbox constrains a misbehaving run through the harness rather than the kernel.

A reasonable default: **codex** for anything where being wrong would be silent — parsing,
aggregation, authorisation, migrations. **glm** for well-specified work where the acceptance
criteria are mechanically checkable. Both benefit identically from a good plan.

Tune the model within a provider:

```bash
HANDOFF_MODEL=gpt-5.3-codex-spark handoff do <slug>   # faster, mechanical work
HANDOFF_EFFORT=low handoff do <slug>
```

### Settings for a local implementer

Measured on gpt-oss-20b via llama.cpp, 30 runs of a six-file plan plus 15 earlier on a four-file
one. Short version: **reasoning `low`, and stop tuning it.**

| Setting | Recommendation | What the evidence says |
| --- | --- | --- |
| Reasoning | **`low`** | `low` vs `off`, n=15 each: quality indistinguishable (p ≥ 0.70 on every outcome). `off` was nominally 26% *dearer* per usable patch, not cheaper, and not significantly so (p = 0.18–0.22). Every point estimate favours `low`; none favours `off`. |
| | not `off` | The theory that the implementer needs no reasoning because the planner did it is not supported. `off` also had the higher no-report rate (40% vs 33%) and produced the single worst run seen — seven invented verification scripts, never cleaned up. |
| | not `medium` | Indistinguishable on quality, and it is where "writes its own verification scripts instead of running the plan's" was first seen. |
| Engine | **llama.cpp, not ollama** | Not a preference. Ollama corrupts this model's tool calls; every result taken through it is void. Run `tools/engine-conformance` after any engine, GGUF, template or client change. |
| Context | 64k, and know it is tight | One run in fifteen on the six-file plan exceeded it and silently lost history. Bigger costs GPU residency, so the fix is detection first. |

The honest summary of the reasoning question: **no measurable difference, choose on architecture.**
`low` is the recommendation because nothing points away from it, not because it was shown to win.

**Where the effort actually pays.** Reasoning level bought nothing. The things that changed outcomes
were the serving engine, one incompatible CLI flag that silently disabled every recovery attempt,
and whether anything checked the tree afterwards. Spend the time on the plan and the gates.

### Adopting this on a project that already has plans

Run `tools/check-plan` over them first. Every plan on the project this was extracted from was
refused — 48 of 48 — and the dominant reason was that criteria and commands disagreed in number.
Plans written for a human reviewer do not carry one executable command per checklist line, because
a human does not need one.

Rewrite rather than convert. The missing half cannot be inferred, and writing it is the part that
makes the verdict worth having.

## The loop

1. Write `.handoff/plans/<slug>.md` from `templates/plan.md`. Fill in **States to handle** and
   **Fixtures** — skipping those is where defects come from.
2. `handoff do <slug>`
3. **Read the verdict, not the report.** `do` prints one and writes the evidence to
   `.handoff/runs/<slug>/evidence/evidence.md`: every gate, the command, its exit code, an excerpt.
   `result.json` is the model's account of itself and is recorded as untrusted metadata.
4. `handoff diff <slug>` and compare against the plan's *Files to touch*.
5. Not right? Write `.handoff/runs/<slug>/feedback.md`, then `handoff resume <slug>`.
6. Right? Commit. The implementer never commits; you do.

### Why the verdict and not the report

Measured on this harness, over hundreds of runs:

- Runs have reported `status: complete`, with invented file paths, over a tree they never touched.
- Between **a quarter and two fifths** of local-model runs return **no report at all** while
  leaving a byte-perfect patch. The tree is fine; the envelope is missing.
- A report that does arrive can claim a test passed that was never run.

None of that makes the model unusable — it makes *its self-assessment* unusable. The gates read the
tree instead, and they catch the case that matters most: a wrong answer that parses cleanly and
reads plausibly. A patch returning `4` where the plan said `5` is rejected on the acceptance
command, not on appearances.

This is also the economics. A rejected round should never reach a hosted reviewer; if every attempt
costs hosted tokens to triage, the case for a local implementer collapses.

## Three models, one task: `handoff auto`

The loop this automates has three seats, and they are different jobs:

| Seat | Who | Why that one |
| --- | --- | --- |
| **Driver** | you, or Claude Code via the skill | Decides what to build, splits it into steps, reads the handover, owns the commit |
| **Planner** | `codex` and `glm`, alternating | Re-specifies after a rejection. Hosted, cheap relative to a person's time, and *not* the model being judged |
| **Implementer** | the local model | Writes the code. Free at inference, and reliable when the specification is mechanical |

```bash
handoff auto <slug>                                  # local ×2 → planner → local ×2 → planner → stop
handoff auto <slug> --planners glm --escalations 1   # one cheap escalation only
handoff auto <slug> --dry-run                        # print the ladder without running anything
```

Each rung is recorded in `.handoff/runs/<slug>/ladder.md`, which doubles as the handover brief when
the ladder gives up: what was tried, what each round scored, and what to read first.

**Why alternate planners.** Two different models reading the same failure is a second opinion for
the price of one API call. More usefully, if both write plans that fail the same way, that is
evidence about the *task* — the step is too big, or the work is not mechanical — rather than about
either plan. That is the moment to write it yourself.

**Why the planner is never the implementer.** The ladder refuses to start if they are the same
model. One model writing the plan, writing the code, and being judged against its own criteria has
removed the only independent step in the loop. `codex` is a perfectly good implementer and the
harness's default provider, which makes this an easy mistake to make by accident.

**What a planner is allowed to touch.** The new plan file, and `.handoff/ladder-notes.md` for
anything that is not a plan change. Nothing else. If it edits source, or the harness that judges
the work, the ladder stops and hands you the diff. A model editing its own grader is self-approval
by another route, and no automation here gets to do it — if a planner thinks the harness is wrong,
it says so in the notes and a person decides.

### Where the ladder stops early, and why

- **The gates accept.** Done; the changes are uncommitted, review and commit.
- **A round scored worse than the round before it.** Repairing is losing ground — the usual cause
  is a partial edit truncating a file the previous round had nearly finished. Repair stops
  immediately rather than continuing.
- **The round never happened.** No write attempted and an adapter error recorded: the plan was
  never asked, so the same plan is re-run once instead of spending an escalation re-specifying it.
- **The planner's plan would be refused by `check-plan`.** Better to stop than to send the local
  model at a contract the harness will not score.

## Keeping track across runs

Every `do` and `resume` appends one record to `.handoff/journal/runs.jsonl` and copies that round's
plan, evidence and event stream into `.handoff/journal/runs/<run-id>/` before the next round can
overwrite them.

```bash
handoff log                 # one line per run: outcome, criteria score, time, writes, errors
handoff log <slug>          # just this plan's rounds
handoff stats               # across everything: outcomes, adapter errors, what rejects rounds
tools/journal show <slug>   # the whole record for the latest round of a plan
tools/journal export-sqlite # a queryable .db, rebuilt from the records in a second
```

**Why this exists.** `.handoff/runs/<slug>` is reused by every round of the same plan. One real
feature ran seven rounds and left three surviving logs — the other four had been overwritten by the
time anyone came to write up what happened, including both rounds that failed most informatively.

**Why JSON Lines and not a database.** No daemon, no migrations, nothing beyond python3, safe to
append to from concurrent runs, and readable with `grep` and `jq`. SQLite is available as a derived
view rather than the source of truth — a corrupted source of truth is the failure that prompted
this in the first place.

### What it records, and the one number worth watching

Per run: the plan and its hash, the provider and model, wall time, the files changed with insertion
and deletion counts, the verdict and criteria score, every gate that failed, token totals, and —
mined from the provider's own event stream — how many tool calls it made, how many of those were
writes, and every error the adapter reported.

**Watch `write_calls`.** A round with zero writes did not fail at the task; it never attempted it.
Backfilling three real runs immediately showed this:

```
outcomes           patch-damaged 3
adapter errors     context-overflow 3, output-token-limit 2, tool-call-format 1
```

Every one of those rounds hit the context limit, and two hit the output-token ceiling mid-turn.
Those are infrastructure failures being scored as model failures, and no amount of re-specifying
the plan addresses them.

### Asking the model what it thinks went wrong

```bash
handoff retro <slug>        # read-only turn; the answer is stored on the run record
```

The model is shown the plan and the harness's verdict, then asked what was unclear, what it got
wrong, and — the useful part — what it would change **about the plan**. Asked without the verdict a
model grades itself with the same confidence its completion reports do, which is why the verdict
goes in first.

Treat the answers as leads, not findings. This is stored as data and never fed back into a later
run automatically: two rounds tested giving the implementer a richer account of its own failure and
both made outcomes worse.

## Two things that will bite you

**Do not run two rounds against the same files at once.** The tree-snapshot diff is cumulative,
so concurrent rounds appear in each other's changed-file lists. Rounds touching disjoint
directories are fine in parallel.

**`| tail` masks exit codes.** `handoff do x | tail -3` reports the exit status of `tail`, not the
run. Redirect to a file instead if you want the status.
