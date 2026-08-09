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
```

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

## The loop

1. Write `.handoff/plans/<slug>.md` from `templates/plan.md`. Fill in **States to handle** and
   **Fixtures** — skipping those is where defects come from.
2. `handoff do <slug>`
3. Read `.handoff/runs/<slug>/result.json`. **Then verify it yourself.** Re-run every command in
   `tests_run`; a claimed pass you did not observe does not count.
4. `handoff diff <slug>` and compare against the plan's *Files to touch*.
5. Not right? Write `.handoff/runs/<slug>/feedback.md`, then `handoff resume <slug>`.
6. Right? Commit. The implementer never commits; you do.

## Two things that will bite you

**Do not run two rounds against the same files at once.** The tree-snapshot diff is cumulative,
so concurrent rounds appear in each other's changed-file lists. Rounds touching disjoint
directories are fine in parallel.

**`| tail` masks exit codes.** `handoff do x | tail -3` reports the exit status of `tail`, not the
run. Redirect to a file instead if you want the status.
