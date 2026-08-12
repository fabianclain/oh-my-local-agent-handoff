# agent-handoff

**Let a big hosted model do the thinking, and your own GPU do the typing.**

A capable hosted model — Claude, Codex, whichever you already pay for — writes a precise,
machine-checkable plan and reviews the result. A model running on your own machine writes the code.
A few hundred lines of bash sit between them and decide, from the files on disk, whether the work
is actually acceptable.

## Why you would want that

**It moves the expensive part off your bill.** Implementation is where the tokens go: reading
files, writing them, re-reading them, fixing what broke. Planning and reviewing are short by
comparison. Handing the long middle to a local model keeps your hosted usage for the two jobs it is
genuinely better at.

**Your hardware is already sitting there.** A 16 GB card runs a 20B model at conversational speed.
It is not as strong as a frontier model — but it does not have to be, because it is never asked to
decide anything. It is asked to implement a specification that has already been decided, and then
its work is checked.

**The checking is the point.** The local model's report is never trusted. Every verdict comes from
the tree: did the acceptance commands pass, did it touch only the files the plan named, did it
quietly rewrite a file it was told to patch. A model that says "all tests pass" and changed nothing
is scored as a failure, automatically.

## How you use it

Three steps. The rule underneath them is that **whoever writes the plan does not decide whether the
result is acceptable** — a model reviewing its own work accepts its own misreading of the task,
every time.

**1. Plan with the hosted model, and ask for _only_ the plan.**

Describe what you want, and say plainly: write the plan, do not implement it. Left to itself a
capable model starts editing, and then it is both author and reviewer of its own work. What comes
back is `.handoff/plans/<slug>.md` — the files it may touch, one criterion per line, and one shell
command per criterion. `handoff check <slug>` refuses it if those disagree.

**2. Hand it to the local model.**

```bash
/local-implementer     # from Claude Code, or `handoff do <slug>` directly
```

It implements, the harness verifies, and `handoff do` exits non-zero if the gates reject. Nothing
is committed — you own the commit.

**3. Read the gaps, not the report.**

The model's account of its own work is the least reliable artifact available and is never trusted;
every verdict comes from the files on disk. Read what the gates rejected, read the diff, and write
down what the round missed. That list is the input to the next plan.

The criteria are the deliverable, and prose is only advice. One plan said in bold *"do not comment
out the removed blocks, delete them"*; the model commented the import out anyway, because the line
above it was already a commented import and local convention beat the instruction.
`test "$(grep -c 'SearchConsole' …)" -eq 0` caught what the sentence did not.

**[docs/WORKFLOW.md](docs/WORKFLOW.md)** has the whole loop, including how to read each verdict and
what to do about it.

## What it costs you, honestly

- **Specification takes longer than the change** on small tasks. A five-minute edit is not worth a
  plan. The break-even is somewhere around "I would have to explain this carefully anyway".
- **A local model is slower** than a hosted one, and slower than you for trivial work. The win is
  on mechanical changes across many files, where the tedium is real and the thinking is not.
- **You still read the diff.** The gates catch what a command can catch. They do not catch a blank
  line left behind by a deletion, or an odd re-indent, and if your project has no formatter those
  land in the commit.

The compensation is that a plan precise enough for a local model is precise enough to catch
specification bugs before anyone writes code — which is the failure mode that actually ships.

## Quick start

```bash
git clone https://github.com/fabianclain/oh-my-local-agent-handoff
cd oh-my-local-agent-handoff
tools/install-local              # links `handoff` onto PATH, picks the local implementer
tools/llamacpp-serve start gpt-oss-20b 98304   # your model server

cd ~/any-project
handoff init                     # .handoff/plans + a config template
handoff do <slug>                # implement the plan, verify it, print the diff
```

`handoff do` exits non-zero if the gates reject the round. Nothing is committed — the reviewer owns
the commit, always.

**[docs/WORKFLOW.md](docs/WORKFLOW.md)** — how this is used day to day: plan with the hosted model
and ask for *only* the plan, hand it to the local one, then read the gaps rather than the report.

**[docs/START-HERE.md](docs/START-HERE.md)** — the same thing at walking pace, including how to
read a verdict.

**[docs/DRIVING.md](docs/DRIVING.md)** — the three seats. Claude plans with `/local-implementer`,
Codex runs the loop with `/local-drive`, the local model writes the code. Whoever writes the plan
must not be whoever decides a rejected round was fine.

> **Status: early, but measured.** Extracted from real feature work on a production Laravel
> codebase, then put under a benchmark harness of its own — well over a hundred recorded rounds,
> each carrying the harness commit and the served context that produced it, so a result can be
> traced to the code and the stack that made it.
> The reasoning, including the conclusions that were wrong and how they were caught, is in
> [docs/local-models.md](docs/local-models.md) and [bench/COMPARISON.md](bench/COMPARISON.md).

## Why

Handing a task to a coding agent and reading the diff works until it doesn't. The failures that
matter are quiet: a parser that passes twelve tests against fixtures someone invented, a health
check that always returns success, an aggregate that silently double-counts.

Over ~30 rounds building a real feature this way, **every defect that shipped originated in a
specification, not an implementation.** The implementer built what it was told, faithfully, every
time. The tests passed because they were written from the same specification that was wrong.

That single observation drives every design decision here.

## What it does

```
handoff do <slug>       implement .handoff/plans/<slug>.md, then verify it
handoff verify <slug>   re-run the gates over the working tree
handoff resume <slug>   feed back review comments, same session
handoff diff <slug>     exactly what changed during the run
```

The plan is a **contract**: goal, context, files to touch, states to handle, fixture provenance,
objectively checkable acceptance criteria, and a binding *out of scope* list. The implementer
returns **schema-enforced JSON**, not prose:

```jsonc
{ "status": "complete|partial|blocked",
  "files_changed": [...], "tests_run": [{ "command": "...", "passed": true, "detail": "..." }],
  "deviations": [...], "blockers": [...], "follow_ups": [...] }
```

The implementer never commits. **The harness verifies before a human or a hosted model looks at
anything**: `handoff do` runs the plan's acceptance commands against the tree when it finishes and
folds the verdict into its exit status, so a round the gates reject fails even when the model
exited cleanly. The reviewer reads the evidence bundle — every gate, its command, its exit code —
and owns the commit.

That ordering is not a nicety. Measured over 30 clean runs of a six-file task, **a third of correct
patches arrive with no report at all**, and reports have historically claimed success over trees
the model never touched. The self-report cannot be the signal.

## Four mechanisms, each from a specific failure

**Tree-snapshot diffing.** Before/after `git write-tree` using a throwaway index, so you get
exactly what the implementer touched. Plain `git diff` is useless in a repo that already has
uncommitted work — and most real repos do.

**Session-pinned resume.** Review rounds continue the same conversation, so feedback is "fix line
42" rather than re-explaining the design. Pinned to a recorded session id, not "most recent".

**A read-only advisory lane.** `consult think` and `consult debug` run sandboxed read-only. An
implementer that *can* edit files *will* edit files; separating review at the sandbox level is
the only reliable way to get a review that cannot quietly fix what it finds.

**`deviations` in the schema.** The highest-value field. Its best catch: the implementer was told
to stop using an endpoint, correctly realised this left the connection test unable to fail,
implemented it as instructed anyway, and *reported the problem*. A health check that always
returns success is invisible in a diff.

## What the tests will not catch

This is the part worth reading twice.

- **Tests inherit the specification's blind spots.** A parser passed twelve tests while unable to
  parse a single real page, because the class it selected on had been removed months earlier.
  More tests would have deepened the illusion.
- **Fixtures must be captured, not imagined.** If a fixture mirrors an external system, it must
  come from that system. This is the single highest-value rule here.
- **Never trust the self-report.** Re-run every claimed test. Three reports were wrong: two
  hijacked by an unrelated harness hook, one falsely claiming `blocked` while the work was
  complete and correct.
- **Verify against real data, not just tests.** Every genuinely valuable check was a live request
  or a query against the real database.
- **The zero case is where defects live.** "What happens with no rows?" caught more than any
  other single question. The plan template makes it mandatory.

What actually found things: an adversarial read of plan-against-code, a browser console, and a
person clicking a link.

## Setup

```bash
git clone https://github.com/fabianclain/oh-my-local-agent-handoff
cd oh-my-local-agent-handoff
tools/install-local          # symlinks `handoff` into ~/.local/bin, writes your defaults
tools/install-local --check  # confirms it the way a non-interactive shell sees it

cd your-project
handoff init                 # .handoff/plans, a config template, and the right .gitignore lines
```

`tools/install-local` writes `~/.config/agent-handoff/config.sh`, which sets the implementer for
every project at once. A project with its own opinions can override it in `.handoff/config.sh`, and
an environment variable overrides both.

Adding the repository's `bin/` to `PATH` in `~/.bashrc` looks equivalent and is not: the stock
`~/.bashrc` returns early for non-interactive shells, so cron, ssh commands and anything an agent
spawns never see it.

`.handoff/config.sh` carries your project's conventions into every prompt. Without it the
implementer cannot know how your project builds, tests, or formats — the largest avoidable source
of review churn.

Copy `commands/*.md` into `.claude/commands/` if you drive this from Claude Code.

## Benchmark harness

`bench/` runs the same self-contained plan in isolated worktrees and preserves raw per-run
evidence. Methodology is in `bench/METHODOLOGY.md`, results in `bench/COMPARISON.md`.

```bash
bench/run --plan wide --providers lcgptossl --repeat 15
bench/report        # every run individually — combining them hides the variance
bench/summary       # cost per usable patch, failed runs charged to the successes
bench/compare wide <control> <arm>    # is the difference real?
```

`bench/compare` exists because two dramatic findings here dissolved under it. It runs Fisher and
Mann-Whitney, and — for a variable that only acts on repair — scores attempt 1 separately, where
the arms are identical by construction. One comparison showed a 27-point gap of which 20 points
were already present before the variable applied.

```bash
handoff auto <slug>   # local implements ×2 → a hosted planner re-specifies → local retries ×2 → stop
```

Three seats, three different jobs: you (or Claude Code) drive, `codex` and `glm` alternate as the
planner that re-specifies after a rejection, and the local model implements. The ladder refuses to
run if the planner and the implementer are the same model, and a planner that edits anything but
its plan file stops the ladder rather than being trusted.

Every run is journalled: `handoff log` for one line per run, `handoff stats` for outcomes,
adapter errors and what actually rejects rounds, `handoff retro <slug>` to ask the model what it
would change about the plan. Records are JSON Lines under `.handoff/journal/`, with each round's
plan, evidence and event stream archived before the next round overwrites the run directory.

The harness has its own tests, none of which need a GPU:

```bash
tools/selftest-all          # every suite, plus the checks no single suite can make
tools/smoke-e2e             # the whole journey in two seconds — run this one first
```

`smoke-e2e` walks `init → check → do → verify → diff` against a provider that runs no model and
asserts the state left at each step, plus the things only an end-to-end pass can see: that every
path in a documented command exists, that all four prompt layers reach the implementer, and that
each documented refusal exits with its documented status *and says why*. Every check in it was
mutation-tested — break the thing it guards and that check, and preferably only that check, fails.

## Providers

A provider is `(binary, env block, capabilities)`, not just a binary. Adapters declare what they
support natively and the driver **degrades loudly** — a prompt-and-validate JSON round is not the
same guarantee as a schema-enforced one, and the difference is printed rather than hidden.

| | structured output | session resume | sandbox |
| --- | --- | --- | --- |
| `codex` | native | native | native |
| `opencode` | prompt-validate | native | none |
| `cline` | prompt-validate | none | none |
| `lcpp` (Cline → llama.cpp) | prompt-validate | none | none |

Adding one means implementing five functions in `providers/<name>.sh`. Nothing above the adapter
is provider-specific.

## Running the implementer locally

A local model can do real work here, within limits that are measured rather than assumed. The full
record is in [docs/local-models.md](docs/local-models.md); the short version:

**Recommended stack — gpt-oss 20B served by llama.cpp, driven by the harness's own loop.**

```bash
tools/llamacpp-serve start gpt-oss-20b 98304
handoff do <slug>            # `native` is the default after tools/install-local
```

llama.cpp rather than ollama: ollama returns HTTP 500 for tool calls its own model generated, and
every result taken through it had to be thrown away.

The harness's own loop rather than a third-party CLI, measured head to head on the same plan under
one harness commit — 18 rounds against 15. Both produced a usable tree in **every** round; they
differ only in whether the completion report survived the serving stack, which the owned loop can
retry and a rented one cannot.

**How reliable, on 30 clean runs of a six-file task** (95% confidence intervals, because the
spread here is wide enough that point estimates mislead):

| | |
| --- | ---: |
| Met every acceptance criterion | 29/30 |
| Green on the first attempt | **78%** (59–89%) |
| Usable patch within three attempts | **93%** (79–98%) |
| Correct patch but **no report at all** | 1 in 3 |
| Typical cost | ~5 min, ~15k generated tokens, free at inference |

**The code is the reliable part; the envelope is not.** When it finishes, the work is correct. What
fails is everything adjacent to reporting on it — which is why the harness judges the tree and the
report is recorded as untrusted metadata.

**The tail is heavy.** Median 279s but p90 at 644s and a worst case of 1404s — a 9.9x range. Budget
for the tail. That spread is a property of the agent loop, not of sampling: setting temperature to
0 with a fixed seed made it *wider*, because token-level determinism does not survive a loop whose
first tool call it does not control.

**Reasoning level is not the lever it looks like.** `low` against `off`, 15 runs each: both
delivered a reviewable patch 14 times in 15, and every quality difference is inside chance
(p ≥ 0.70). Use `low` because nothing points away from it, not because it was shown to win.

An earlier version of this section reported **15/15** on the four-file task. That was accurate
about acceptance criteria and hid that three of those fifteen runs changed files the plan never
named. Corrected rather than deleted, because which numbers turned out to be incomplete is part of
what this repository is for.

**Use llama.cpp, not ollama, for gpt-oss.** Same weights, same tool schema, same conversation:
ollama returns HTTP 500 for tool calls its own model generated — 2/5 malformed against 8/8, and
1/3 correct patches against 4/4. Throughput is identical, so the choice costs nothing.
`tools/repro-ollama-toolcall-500.py` reproduces it with no client involved. Ollama remains fine for
models it handles cleanly; gemma runs well through it.

Three things gate a local model, and each has produced a wrong verdict when skipped: **which
engine serves it**, whether it emits native tool calls, and whether the window you want keeps it
100% GPU-resident. Read the chat template and the stop list before concluding anything about
capability — three models tested here were blocked by packaging, not ability.

```bash
tools/engine-conformance --engine llamacpp --model gpt-oss-20b
```

Run that whenever the engine build, GGUF, template, client version, context size or tool schema
changes. A benchmark cannot tell an engine regression from a model regression; not having this
check is why every ollama-served gpt-oss result had to be thrown away.

**The most useful thing in this repository is the record of what turned out to be wrong.** Ten
harness defects have been found here and six were mistaken for model behaviour first — a retry
disabled by an incompatible CLI flag for 25 of 61 runs, a "the model goes quiet" mystery that was
three stacked bugs, a dramatic finding that was noise present before the variable applied. That
register is in [docs/local-models.md](docs/local-models.md) and
[bench/COMPARISON.md](bench/COMPARISON.md), kept as prominent as the results.

## Licence

MIT — see [LICENSE](LICENSE).
