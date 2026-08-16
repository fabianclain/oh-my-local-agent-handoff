# Start here — a local model doing your implementation work

You write a specification. A model running on your own GPU implements it. The harness checks the
result against your specification and tells you whether to trust it.

Nothing here asks you to trust the model's opinion of its own work, because measured over 30 runs
that opinion is missing a third of the time and has occasionally been invented.

---

## What you get, measured

On a six-file refactoring task, 30 runs, gpt-oss-20b on a 16 GB card:

| | |
| --- | ---: |
| Met every acceptance criterion | 29/30 |
| Green on the first attempt | **78%** (95% CI 59–89%) |
| Usable patch within three attempts | **93%** (79–98%) |
| Typical cost | ~5 minutes, free at inference |
| Heavy tail | p90 is 2.3× the median; worst case 9.9× |

**The code is the reliable part.** When it finishes, the work is correct. What is unreliable is
everything around reporting on it — which is why the harness reads the tree and not the report.

**Those figures are a six-file refactor of code that already existed.** On a greenfield Laravel
task — new service, new view, aggregate SQL — the same stack went **0 accepted in 7 rounds**. Do
not carry the numbers above across task shapes; carry the method instead.

| | six-file refactor | greenfield + aggregate SQL |
| --- | ---: | ---: |
| Rounds accepted | 93% within three attempts | **0 of 7** |
| Best single round | — | 9 of 12 criteria, then 3 of 14 on the resume |

What broke there, by frequency: invented conditions the plan never mentioned (3 of 7), file
truncation on a *later* edit of a file the model had already written (2 of 7, both fatal, both on
files over 150 lines), tool-call format errors (2 of 7 — one round made 44 calls, none of them a
write, and reported success over an empty diff), scratch files despite prose forbidding them
(2 of 7), placement errors after two prose warnings (2 of 7), and silently dropped fields in a
contract a later step depended on.

The reviewer wrote the same service by hand afterwards: 8/8 tests, 12/12 acceptance, first run.
Read that as scope guidance rather than as a verdict — the local model is worth reaching for on
mechanical change to code that exists, and is currently a poor bet on greenfield design.

**This is a specific slice, not a general coding agent.** It works for well-specified, mechanically
checkable changes. It is unproven on ambiguous work, on design decisions, and on tasks where a
plausible wrong answer looks identical to a right one. Section "Where this stops working" below is
worth reading before you rely on it.

---

## 1. Prerequisites

- A GPU with ~14 GB free. This was measured on an RTX 5060 Ti (16 GB).
- [llama.cpp](https://github.com/ggml-org/llama.cpp) built with GPU support, and `llama-server`
  reachable. Default location: `~/.local/opt/llamacpp/llama-b10331/llama-server`, or set
  `LLAMA_SERVER`.
- `npm i -g cline`
- `php`, or whatever your project's acceptance commands need.

## 2. Set up the model

```bash
git clone https://github.com/fabianclain/oh-my-local-agent-handoff
cd oh-my-local-agent-handoff
tools/setup-local-implementer
```

That checks prerequisites, starts `llama-server` at a context size chosen from your **free** VRAM
(32k unless ~15 GB is free — 64k does not fit alongside a desktop session, and llama.cpp spills to
host RAM rather than refusing), points Cline at it, and — the step
that matters — **probes the stack with a real tool call**. A server that answers `/health` can
still corrupt every tool call it returns, and a benchmark cannot tell that apart from a bad model.
Finding that out the hard way cost this project every result it had gathered.

To check the harness itself rather than the model — after pulling, or if something behaves oddly:

```bash
tools/smoke-e2e     # ~2s: the whole journey against a provider that runs no model. No GPU.
```

If the weights are missing it prints the download command and stops. Get the GGUF from Hugging
Face, **not** from ollama's blob store: ollama keeps the chat template as a separate layer outside
the GGUF, so its blobs are template-stripped and will serve a model that cannot emit tool calls.

## 3. Set up your project

```bash
cd ~/your-project
export PATH="/path/to/oh-my-local-agent-handoff/bin:$PATH"
handoff init
```

`handoff init` creates the plans directory, copies a config template if there is none, and adds the
gitignore entries. It is idempotent, and it skips any path the project already tracks — a project
can legitimately keep plans under `.claude`, and blanket-ignoring it there would quietly stop new
plans being added.

Edit `.handoff/config.sh` — it carries how your project builds, tests and formats into every
prompt. Without it the implementer is guessing at your conventions.

### Run it in a worktree, and check where the worktree's database points

The implementer runs arbitrary commands against a live tree with approval disabled. Nothing in the
harness isolates that, so isolate it yourself:

```bash
git worktree add ../myproject-featurename -b featurename
```

One session lost its development database — every table, including `sqlite_master` — with no
backup. The cause was never established, but the leading candidate is a scratch script a round
wrote that booted the whole application against the real database. Recovery was possible only
because the raw source data happened to still be on disk.

**A worktree alone is not isolation if the database is not.** Copying `.env` across brings an
absolute `DB_DATABASE` with it, which points the worktree straight back at the live file and buys
nothing. Point it at a copy, and take a backup you can actually restore from.

**Do not skip the `.gitignore` line.** Plans usually assert "exactly N files changed", and any
agent framework writing state into your working directory will break that check. The first
end-to-end run of this guide was rejected for three files that belonged to the agent framework
rather than the model.

## 4. Write a plan

The plan is the whole game. It is a contract, and the acceptance criteria are what make the
verdict mean anything — the verifier's ceiling is your plan's.

```bash
cp /path/to/oh-my-local-agent-handoff/templates/plan.md .handoff/plans/my-task.md
```

A real, working example — this exact plan was run against a local model while writing this guide:

````markdown
# Free shipping over £50

## The change

In `src/Cart.php`, add one method:

```php
public function shipping(): int
```

It returns the shipping cost in pence:

- `0` if `subtotal()` is 5000 or more
- `499` otherwise
- `0` if the cart is empty

## Files to touch

| Path | Action |
| --- | --- |
| `src/Cart.php` | modify |

One file. Creating any file fails this round.

## Acceptance criteria

- [ ] The file parses
- [ ] A cart with one £60 item ships free
- [ ] A cart with one £10 item costs 499
- [ ] An empty cart ships free
- [ ] Exactly at £50 ships free
- [ ] Exactly one file changed, none created

## Verification

```bash
php -l src/Cart.php
php -r 'require "src/Cart.php"; $c=new Cart; $c->add("a",6000,1); exit($c->shipping()===0?0:1);'
php -r 'require "src/Cart.php"; $c=new Cart; $c->add("a",1000,1); exit($c->shipping()===499?0:1);'
php -r 'require "src/Cart.php"; $c=new Cart; exit($c->shipping()===0?0:1);'
php -r 'require "src/Cart.php"; $c=new Cart; $c->add("a",2500,2); exit($c->shipping()===0?0:1);'
test "$(git status --porcelain -- . ':(exclude).handoff' | wc -l)" -eq 1
```

## Out of scope

Tests, other files, refactoring anything not named above, committing.
````

Four rules that decide whether this works:

1. **One acceptance criterion, one executable command.** The counts must match — the harness
   refuses a plan where they disagree, because a plan with six criteria and two commands caps every
   model at 2/6 by construction, and one shipped that way here.
2. **Dictate the signatures.** Difficulty should mean more work, not more decisions. The
   implementer executes; it does not design.
3. **Test the boundary and the zero case.** "What happens with no rows?" has caught more defects
   here than any other single question. Note the `£50 exactly` case above.
4. **Name the files, and say what happens if others change.** That is what makes the scope gate
   mean something.

### Check the plan before you run it

```bash
tools/check-plan .handoff/plans/my-task.md
```

It applies the harness's own parsing — the expressions are copied from `bench/run` character for
character — and tells you whether the plan would be refused, and whether its verdict would mean
anything.

**Expect existing plans to fail.** On the project this was extracted from, **48 of 48** plans
written for human review were refused:

| Reason | Plans |
| --- | ---: |
| Criteria and commands disagree in number | 38 |
| No commands in a fenced block under `## Verification` | 10 |
| No paths in the `## Files to touch` table | 6 |
| No `- [ ]` criteria at all | 3 |

That is not a defect in those plans. They were written for a workflow where a person reads the
diff, and a person does not need one executable command per checklist line. Machine verification
does, and there is no way to infer the missing half.

So budget for rewriting plans, not converting them. The good news is that the rewrite is the part
that carries the value: a plan whose criteria are each one command is also a plan you have thought
through properly, which is why the largest measured improvement in this project came from output
discipline and not from any model setting.

`check-plan` also prints advisories, which do not block a run but decide whether its verdict is
worth much:

- **a command a do-nothing tree could pass** — `php -l` on an unmodified file succeeds, so a
  criterion resting on it measures nothing
- **nothing asserting how many files changed** — then the plan is not enforcing its own scope

### Prefer a sequence of small steps to one large plan

A step should be one to two files, three to six criteria, one coherent behaviour. Write the whole
sequence up front, then run it:

```bash
handoff sequence <slug>-1-service <slug>-2-view
```

It commits each accepted step and stops at the first rejection. The commit is not housekeeping —
the implementer leaves changes uncommitted and every plan asserts how many files changed, so step
1's leftovers would fail step 2's file count. That is the whole reason a person used to sit at
every step boundary, and the reason a tool can sit there instead.

Be clear about what this buys, because it is not what it looks like. Smaller steps are **not**
measurably more likely to succeed: the six-file plan scored 87% on first attempt against the
four-file plan's 80%. What they buy is cheap failure, localised diagnosis, banked progress — and
most importantly criteria a stub cannot fake, because narrow scope is what lets each criterion
assert something specific.

Cut pure logic away from anything that renders. A service class is close to an ideal fit; a view is
the easiest thing in a codebase to satisfy with three lines that mean nothing.

### Using it in any repository on this machine

Everything above runs from inside this checkout. To use `handoff` in an unrelated project:

```bash
tools/install-local                    # or: tools/install-local --check
```

Two things, and neither touches a repository or the model server:

1. **`handoff` goes on PATH**, as a symlink in `~/.local/bin`. Adding this repository's `bin/` to
   PATH in `~/.bashrc` looks equivalent and is not — Ubuntu's stock `~/.bashrc` returns at line 5
   for non-interactive shells, so `bash -c handoff`, cron, ssh commands and anything an agent
   spawns never see it. That cost a benchmark night its first launch. `~/.profile` adds
   `~/.local/bin` for login shells and it is already in the systemd user environment, so the
   symlink works where the PATH export does not.

2. **`~/.config/agent-handoff/config.sh` is written** with the provider, model and port, which sets
   the implementer for **every project at once**. Without it `bin/handoff` defaults to `codex`, a
   hosted CLI, and driving a local model elsewhere means `HANDOFF_PROVIDER=native` on every
   invocation or a config file committed into every repository you touch.

Configuration is read in three layers, each overriding the one before:

| Layer | Where | Scope |
| --- | --- | --- |
| user | `~/.config/agent-handoff/config.sh` | every project on the machine |
| project | `<repo>/.handoff/config.sh` | that repository, written by `handoff init` |
| environment | `HANDOFF_PROVIDER=...` and friends | the single invocation |

So a machine-wide default is one file, a repository with its own opinions overrides it, and a
one-off experiment overrides both without editing anything.

Then, in the other repository:

```bash
cd ~/dev/some-project
handoff init          # idempotent; safe to re-run on a configured project
```

`tools/setup` does all of this at once — `install-local` for PATH and the user config,
`build-integrations` for the skills, `setup-local-implementer` for the model stack, and `doctor` to
state what is actually true at the end. Each refuses rather than half-succeeding.

### Or drive it from Claude Code

`integrations/claude-skills/local-implementer/SKILL.md` is a Claude Code skill that does all of the
above: it interviews you about the change, writes the plan in verifiable form, checks it, runs it,
and reports the harness's verdict rather than the model's account of itself.

```bash
mkdir -p ~/.claude/skills
cp -r integrations/claude-skills/local-implementer ~/.claude/skills/   # every project on the machine
```

There are two skills, one per seat, and both install for both CLIs:

```bash
tools/build-integrations --install
```

`/local-implementer` writes the plan; `/local-drive` gets an existing plan through the gates and
reports. The intended pairing is Claude planning and Codex driving — the expensive model spends its
turn on the specification, which is the part that decides everything, and a cheaper one runs the
loop. See [DRIVING.md](DRIVING.md).

Then ask for a feature in plain language and it takes it from there. The division of labour is the
point: the hosted model writes the specification, which is the part the local model cannot do and
the part that decides whether verification means anything.

## 5. Run it

```bash
HANDOFF_PROVIDER=local handoff do my-task
```

`handoff do` implements, then verifies, and **folds the verdict into its exit status** — so a round
the gates reject fails even when the model exits cleanly. Check it:

```bash
HANDOFF_PROVIDER=local handoff do my-task && echo ACCEPTED || echo REJECTED
```

Do not pipe it to `tail` and read `$?`; you will get `tail`'s status. That trap caught the author of
this guide while writing it.

## 6. Read the verdict, not the report

```
# Verification evidence — ACCEPT
11 passed, 0 failed, 0 advisory, 3 not run.
```

The full bundle is at `.handoff/runs/<slug>/evidence/evidence.md`: every gate, its command, its
exit code, a digest of its output. Three things to know about how to read it:

**The verdict is your plan's acceptance commands, plus scope.** Nothing else votes. That split is
measured: across 68 evidence bundles the harness's own extra gates caught exactly one thing the
plan's commands had not.

**"Not checked" is not "passed".** `pint`, `phpstan` and `pest` run only if present. They are
listed explicitly so that absence of a failure is never mistaken for evidence of correctness.

**Advisory findings do not reject, and are worth reading anyway** — a file regenerated rather than
patched, for instance. They are what tells you whether an accepted patch is one you actually want.

Then `handoff diff my-task` to see exactly what changed, and commit it yourself. The implementer
never commits.

## 7. Look at what actually happened

Every run is recorded. The run directory is reused by the next round of the same plan, so the
journal copies each round's plan, evidence and event stream somewhere immutable first.

```bash
handoff log       # one line per run: outcome, criteria score, time, writes, adapter errors
handoff stats     # across all runs: what is actually failing, and how often
```

The column to watch is **writes**. A round with zero writes never attempted the task — that is an
adapter or context failure wearing a model failure's clothes, and re-specifying the plan will not
help. Backfilling three real runs found the context limit hit in all three.

`handoff retro <slug>` asks the model, read-only and after it has been shown the verdict, what it
would change about the plan. Full detail in [usage.md](usage.md).

## 8. When it fails

Roughly 1 in 14 tasks needs you. Far more common, about 1 in 3, is a correct patch with **no report
at all** — the tree is fine and the model simply ended its turn without saying anything. Check the
verdict; if the gates accept, take the patch.

If the gates reject, the usual causes in order: the plan was ambiguous, an acceptance command was
wrong, or the model genuinely got it wrong. Read `evidence.md` first — it names the failing command
and shows its output.

---

## Where this stops working

Stated plainly, because the measurements have limits and quoting them outside those limits would be
dishonest:

- **Everything above was measured on synthetic PHP fixtures with no test suite.** The style,
  static-analysis and test-suite gates never ran once in 68 bundles. On a real codebase they do,
  and the picture may differ.
- **One task class:** mechanical refactors with dictated signatures. No ambiguity, no design.
- **The dangerous class is untested.** `bench/plans/semantic.md` — where a plausible answer and a
  correct one look identical — is written and validated but has never been run against a model.
  Money, dates, aggregates and permissions are where a local implementer is most dangerous.
- One model, one engine, one client, one GPU.

---

## Where to go next

| | |
| --- | --- |
| [DRIVING.md](DRIVING.md) | Who does what, how to size a task, how to read a failure |
| [usage.md](usage.md) | The full command surface, provider table, settings with their evidence |
| [how-it-works.md](how-it-works.md) | The gates, the four prompt layers, who decides what "verified" means |
| [queueing.md](queueing.md) | Several projects, one model: the lock, your place in the queue, the spool, callbacks |
| [answerability.md](answerability.md) | The three exit codes every gate uses, and what a check must do when it cannot answer |
| [local-models.md](local-models.md) | Every measured finding, and the register of conclusions that turned out wrong |
| [changing-the-model.md](changing-the-model.md) | Swapping or fine-tuning the model: the capability gate, three models tried, and why fine-tuning waits |
| [../bench/COMPARISON.md](../bench/COMPARISON.md) | Round-by-round results |

If you take one thing from the rest of the documentation, take this: **fifteen harness defects have
been found in this project and nine were mistaken for model behaviour first.** When a run looks
wrong, ask whether something other than the model could have produced it, before concluding
anything about the model.

The most recent three are the shape to watch for. A model spent three rounds searching a file
whose anchors sat past the read cap, unreachable by any tool it had; a round was told it had
"damaged the tree" when a second agent session had reverted the file underneath it; and a gate
reported `pass` over a file that did not parse. In each case the harness produced a confident,
specific, wrong account of what the model had done.
