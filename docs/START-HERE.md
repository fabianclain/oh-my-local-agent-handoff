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
task — new service, new view, aggregate SQL — the same stack went **0 accepted in 5 rounds**. Do
not carry the numbers above across task shapes; carry the method instead.

| | six-file refactor | greenfield + aggregate SQL |
| --- | ---: | ---: |
| Rounds accepted | 93% within three attempts | **0 of 5** |
| Best single round | — | 9 of 12 criteria |

What broke there, in order: file corruption on a second edit of a long file (2 of 5, both fatal),
invented conditions the plan never mentioned (3 of 5), scratch files despite prose forbidding them
(2 of 5), and silently dropped fields in a contract a later step depended on.

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

That checks prerequisites, starts `llama-server` at 64k context, points Cline at it, and — the step
that matters — **probes the stack with a real tool call**. A server that answers `/health` can
still corrupt every tool call it returns, and a benchmark cannot tell that apart from a bad model.
Finding that out the hard way cost this project every result it had gathered.

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
sequence up front, run them one at a time, and **commit between steps** — the implementer leaves
changes uncommitted and every plan asserts how many files changed, so step 1's leftovers will fail
step 2's file count.

Be clear about what this buys, because it is not what it looks like. Smaller steps are **not**
measurably more likely to succeed: the six-file plan scored 87% on first attempt against the
four-file plan's 80%. What they buy is cheap failure, localised diagnosis, banked progress — and
most importantly criteria a stub cannot fake, because narrow scope is what lets each criterion
assert something specific.

Cut pure logic away from anything that renders. A service class is close to an ideal fit; a view is
the easiest thing in a codebase to satisfy with three lines that mean nothing.

### Or drive it from Claude Code

`skills/local-implement/SKILL.md` is a Claude Code skill that does all of the above: it interviews
you about the change, writes the plan in verifiable form, checks it, runs it, and reports the
harness's verdict rather than the model's account of itself.

```bash
mkdir -p ~/.claude/skills
cp -r skills/local-implement ~/.claude/skills/     # available in every project on the machine
```

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

## 7. When it fails

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
| [usage.md](usage.md) | The full command surface, provider table, settings with their evidence |
| [how-it-works.md](how-it-works.md) | The gates, the four prompt layers, who decides what "verified" means |
| [local-models.md](local-models.md) | Every measured finding, and the register of conclusions that turned out wrong |
| [../bench/COMPARISON.md](../bench/COMPARISON.md) | Round-by-round results |

If you take one thing from the rest of the documentation, take this: **ten harness defects have
been found in this project and six were mistaken for model behaviour first.** When a run looks
wrong, ask whether something other than the model could have produced it, before concluding
anything about the model.
