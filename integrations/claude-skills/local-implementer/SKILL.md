---
name: local-implementer
description: Design a feature, write a machine-verifiable plan, and have a local model on this machine implement it while the harness verifies the result. Use when the user asks to build or change something with the local model, mentions agent-handoff, or says "implement this locally". Also use when they want a plan written in verifiable form.
user-invocable: true
---

# Implementing with the local model

You design and specify. A local model (gpt-oss-20b on this machine) writes the code. The harness
decides whether the result is acceptable — not you, and never the model's own report.

Your job is the part the local model cannot do: turning a request into a specification whose every
claim is mechanically checkable. That is the measured bottleneck.

## When this is the right tool

**Good fit** — a contained change to code that already exists, with dictated signatures: adding a
method with specified behaviour, threading a parameter through, a pure service class, anything
where "did it work?" is answered by running a command.

**Almost everything should be split.** One large round is rarely the right shape; a sequence of
one-file steps usually is. See step 3 — decomposing is the default, not a fallback for when
something fails.

**Split it especially** — greenfield work, and anything mixing a service with a view.
The measured figures below come from a six-file *refactor*; creating new files from a spec is a
different shape with more freedom and far more surface to fake.

Views were long called the worst case, on the grounds that a three-line template can satisfy a
text assertion while containing nothing real. That is true of TEXT assertions and it is not true
of views: 32 rounds building a self-contained page were accepted 30 times, gated on things that
are arithmetic rather than opinion —

    handoff view-lint <file>          tag balance; malformed HTML renders and passes everything
    handoff contrast <file> --min 4.5 WCAG is a defined function of two colours
    a structural check                landmarks present and in order, every in-page anchor
                                      resolving to an id that exists, every image labelled

For editing an existing file, two more, and they answer questions `php -l` cannot:

    handoff patch-shape <ref> <file> --max-hunks 3 --max-added 70
        The change has the SHAPE the plan asked for. --max-hunks bounds where edits land, because
        a change scattered across a dozen places is not the change you described. --max-added
        bounds how much arrives at each: a file appended to itself is ONE hunk, every original
        line surviving in order, and it passes everything else.

    handoff docblock-anchor --base <ref> <file>
        Every docblock still sits on the declaration it sat on before. A method inserted between a
        docblock and its method is valid PHP, a clean `php -l`, and leaves the docblock describing
        something else. This is the failure that ended the two most promising rounds of a real
        feature, and nothing else in the harness sees it.

Write them as `handoff <gate>`, never as a path. `tools/docblock-anchor` resolves inside the
harness checkout and nowhere else, so a criterion naming it fails for the wrong reason in your
project — which is the whole reason these are subcommands.

The anchor check is the one to copy: `href="#features"` against `id="feature"` renders correctly,
reads correctly, satisfies every text assertion, and is broken. Only a join between the two sets
sees it. Split a service from its view when they are different KINDS of work, not because a view
cannot be checked.

**Do it yourself instead** — and say so:

- Ambiguous requirements, or work needing design decisions. The implementer executes; it does not
  design. Difficulty must mean *more work*, not *more decisions*.
- Anything where a plausible wrong answer is indistinguishable from a right one: dates, aggregate
  SQL, permissions, concurrency. Money is measurable and mostly fine — see below — but only with
  criteria that discriminate.
- **Anything you could just do in five minutes.** Specification takes longer than a small change,
  and on a single small step it will lose on wall clock every time. Reported from real use: two
  steps that would each have taken about five minutes by hand cost considerably more to specify.
  The value there was not speed — it was being forced to say exactly what "removed" means, which
  caught a commented-out import that bold prose in the same plan had failed to prevent. Spend the
  specification when the change is repetitive, spans many files, or is one you would have to
  explain carefully anyway; skip it when you would type it faster than you can describe it.

## What to expect

On mechanical change to code that exists: **90–100% of rounds produce a tree a reviewer can take**,
roughly five minutes each. Over one night on a six-file refactor, `native` produced a usable tree
in 18 of 18 rounds and a report in 18 of 18. A missing report is now a provider signal rather than
a fact of life — see step 8b — so if you are seeing a quarter of rounds without one, check what you
are driving. Judge the tree either way; never read anything into a missing report.

**Hard arithmetic is a good fit, if you specify it completely — and "completely" is stricter than
it sounds.** A plan requiring integer proration with largest-remainder allocation and half-up
rounding has now been run sixteen times and every implementation fuzzed against the specification,
4000 randomised trials each. Fourteen were correct, including tie-break rules and an odd-divisor
rounding edge the plan never spelled out.

**Two were wrong, and both passed every acceptance criterion.** One returned the right amounts in
the wrong order and disagreed on 2,283 of 4,000 trials; the other gave every leftover cent to the
same line and disagreed on 1,107. Neither was caught by the gates, because in both cases the
worked example in the criteria could not discriminate:

- the ordering example used three *identical* lines, so every remainder tied and every order was
  the same order
- the ordering-fix example had exactly one cent left over, so a loop that mis-distributes several
  behaves correctly on it

The rule that follows is worth more than the reassurance it replaces: **a worked example that is
symmetric in the thing it tests cannot test it.** Vary the thing you are checking — unequal
remainders, more than one leftover cent, different lengths — and take the case from an observed
failure where you can, because an invented one usually fails to discriminate.

**Its twin, found later and the same shape: an example that discriminates one DIRECTION of an
error does not discriminate the other.** A third implementation wrote `intdiv($sum + intdiv($D+1,
2), $D)` where the specification says `intdiv($D, 2)` — ceil of half instead of floor. Identical
for even periods, different for odd ones, wrong on 285 of 4,000 fuzzed trials, and accepted at 10
of 10.

It had been reasoned that odd periods were safe, and that reasoning was correct about a *different*
wrong formula. Ruling out one way of getting a term wrong says nothing about the other. When a
criterion pins down a rounding rule, a tie-break or a boundary, ask which way a plausible
implementation could be wrong — then check that your example separates BOTH.

**On greenfield work carrying DESIGN DECISIONS, expect much worse.** One real feature — new
service, new Livewire view, aggregate SQL — went **0 accepted in 7 rounds**, best round 9 of 12
criteria. The reviewer then wrote the same service by hand and it passed 8/8 first run.

That was read for months as "greenfield is hard", and the qualifier is the whole finding. Measured
against a greenfield task with the decisions already made — a self-contained page, every section,
string and colour dictated — the same model produced **30 accepted of 32 runs, at 12 or 13 of 13
criteria, nearly all on the first attempt, in about three minutes each**. It writes the page in one
edit and four tool calls.

So the variable is not novelty, it is who decides. The model executes a complete specification well
and invents a poor one. On greenfield design, write the decisions yourself and hand over the
mechanical remainder — and having done that, do not then expect it to fail.

## The procedure

### 0. If anything is unproven, spike it — and spike the WHOLE toolchain

Before specifying work that depends on something you have not seen succeed, prove it by hand:
build the smallest thing that exercises it and watch it work.

**One gate is not the toolchain.** Reported from real use: a spike proved `react-dom/server` bundles
for Hermes, and the plan that followed asserted a typecheck the project could not pass — the app had
`@types/react` and not `@types/react-dom`, and the plan's own rules forbade adding a dependency. The
criterion was unsatisfiable under the constraints it shipped with, which is a specification defect
and costs a whole round.

So spike every gate the plan will assert: it bundles **and** it typechecks **and** it lints **and**
its tests run. If a gate needs a package the project lacks, either add it before the round or leave
that gate out — a criterion the constraints forbid can never pass.

### 1. Understand the request before specifying it

Ask about anything that would change the code; stop when the answer would not. Boundary and zero
cases matter most. Read the files you intend to name.

### 2. Wire the project up

`handoff init` — idempotent, safe on a configured project.

### 3. Break the work into the smallest steps that each stand alone

**Default to decomposing.** If the user brings you a plan or a feature description, your first job
is to turn it into a *sequence* of small rounds, not one large one. One step should be something
you could describe in a sentence and verify in three commands.

Rough sizing, from what has been measured: **one to two files, three to six criteria, one
coherent behaviour.** A step touching six files is a round; a step touching one is a step.

**The real budget is conversation depth, not the context window.** The serving stack discards
malformed output at a rate that tracks how deep the conversation has gone, and the cliff is sharp:

| Conversation depth | Completions discarded |
| --- | ---: |
| below 16k tokens | 0.00% |
| 16k–32k | 0.76% |
| 32k–48k | 2.17% |
| above 48k | 2.55–6.06% |

A discarded call is not a retry — it is a turn that never reaches the client, so the model can
spend its whole budget reading files and write nothing. Measured across two sessions at 96k and
128k windows, and *the window made no difference*: a conversation that reaches 50k fails at the
same rate whichever ceiling it runs under. Enlarging the window does not buy you a bigger step. It
only stops you overflowing.

**Depth is a proxy, not the cause, so do not treat the table as a budget to spend up to.** The same
fault has been induced deliberately at **666 tokens** by putting the model in conflict — asked to
attest to test results while forbidden from running anything. What deep conversations have in
common with that is pressure to conclude while the model still wants to act. Small steps help
because they reach that moment with less accumulated pressure, not because tokens are toxic.

So size a step by the conversation it will produce, not by the window it has available. A step that
needs the model to read six files before it can write one is a deep conversation regardless of how
few files it changes.

**Editing inside a big file.** `read_files` returns about 20,000 bytes at a time. A file past that
is read in windows — `{"path": ..., "start": 871, "end": 930}`, 1-based and inclusive, taking the
line numbers straight from a `search` match. That works, and it is still two round trips before
the model has seen the code it must edit, on top of the search that located it.

The cost is worth stating plainly, because it was paid: a step whose two insertion anchors sat at
lines 871 and 914 of a 1,052-line component ran three times and wrote nothing. Once the anchors
are quoted verbatim in the plan, none of those trips are needed — so quote them, with their line
numbers, whenever the target file is over a few hundred lines:

```
Insert immediately after this line (currently line 914):

    private function moveOption(int $optionId, int $direction): void
```

A line number goes stale the moment anything above it changes, which is why the quoted text is
what the model anchors on and the number is only a hint about where to look.

**Be honest about what this buys.** It does *not* make the model more likely to succeed per step —
the six-file plan actually scored slightly better on first attempt (87%) than the four-file one
(80%). What it buys is:

- **Cheap failure.** A rejected step wastes one step. A rejected six-file round wastes everything,
  and a three-attempt failure costs three times a large run rather than three times a small one.
- **Localised diagnosis.** When a big plan fails you learn that *something* was wrong. When step 3
  of 5 fails you know exactly what.
- **Criteria a stub cannot fake.** This is the real prize. Narrow scope lets each criterion assert
  something specific; a six-file plan's criteria are necessarily coarser, and coarse criteria are
  what a stub slips past.
- **Banked progress.** Steps 1 and 2 are committed and safe while step 3 is retried.

**How to cut.** In order of preference:

1. **Pure logic before anything that renders.** A service class is close to an ideal fit; a view is
   the easiest thing in a codebase to fake past a text assertion. Never in the same step.
2. **One file per step** where the files are genuinely independent.
3. **One method or one behaviour per step** when a single file is doing several things.
4. **Data before presentation, and each layer gated on its own tests.**

Name them in order: `<slug>-1-service`, `<slug>-2-view`. Write every plan up front so the user can
review the whole sequence, then run it:

```bash
handoff sequence <slug>-1-service <slug>-2-view <slug>-3-page
```

**Run the sequence rather than the steps.** `handoff sequence` checks every plan first, runs them
in order, commits each accepted step, and stops at the first rejection with the tree as the gates
left it. It never re-specifies — deciding a criterion is wrong comes back to you.

**Add `--reroll 2` unless you have a reason not to.**

```bash
handoff sequence --reroll 2 <slug>-1-service <slug>-2-view <slug>-3-page
```

A rejected step is asked again from a restored tree, with no feedback — an independent sample of
the same plan, not a nudge toward the criterion it just missed. The case is arithmetic: the
benchmark step measured at 6 accepted rolls out of 10 lands 60% of the time if the sequence stops
on rejection, and lands every time if it is re-rolled, for an expected 1.67 rounds of GPU. Steps
here are usually satisfiable and occasionally unlucky, and re-rolling is the cheap answer to
unlucky.

Two things about it are worth knowing before you rely on it:

- **A re-roll is not a repair.** A repair hands the model its failing commands and the tree it
  already wrote; against an impossible criterion that is what produced `Carbon::setTestNow()` in
  production code. A re-roll shows it neither, so it cannot harden a bad assertion. Repairs are
  still one-per-step and still gated behind `--consult`.
- **Rolls are not free against an unsatisfiable criterion** — every one fails identically and the
  step stops anyway, several rounds later. With `--consult` set, a consult answer that cannot
  confirm the failure was the model's *cancels* the remaining rolls, which is the composition worth
  paying for: not "retry with a hint" but "is this reachable at all, before we ask again".

When a step is rejected on every roll, read that as evidence about the **plan**. An unlucky roll
does not repeat three times, and the stop says how many times it asked. Nothing is thrown away —
each discarded attempt is committed to `refs/handoff/discarded/<slug>/<roll>`, readable with
`git show`.

**Why the commit matters, and why a tool now does it.** The implementer leaves changes uncommitted,
and the scope gate compares the tree against the plan's file list, so step 1's files still sitting
there are charged to step 2 and it fails for a reason unrelated to itself. That is why someone had
to commit between steps — and because nothing but a person could, a person sat at every step
boundary performing a mechanical act. A field report of nine rounds counted the cost: five
approvals, not one of which decided anything. Every one was "continue".

So do not ask the user to approve each step. **Approve the plan sequence once, before any of it
runs** — that review is where their judgement is worth something, and it fits in one turn. Then
run the sequence and bring back what it stops on.

Two things it deliberately refuses, both of which mean the verdicts would be meaningless:

- a working tree that is not clean, because step 1 would be charged with whatever is already there;
- any plan whose acceptance commands are destructive. See "Criteria are executed, twice" below.

**And write the plans up front for the same reason, not only for review.** Writing step 2's plan
*while step 1 is running* puts a new file in the tree mid-round, and it shows up under "changed by
this run". It is harmless only when it lands somewhere excluded — `.handoff/plans/` is — and a
scratch note anywhere else is charged to the model. Nothing should touch the tree between
`handoff do` and its verdict. Reported from real use.

**Several projects at once.** `handoff do` takes a machine-wide lock on the local model and waits
rather than refusing when another project is mid-round, printing who holds it, your position, and
an estimate drawn from real round durations. You do not have to do anything to get this. Concurrent
rounds do not fail — they silently misattribute each other's tokens, which is worse.

**Queue across projects; never queue a sequence.** For work in a DIFFERENT repository, enqueue it
and walk away:

```bash
cd ~/dev/other-project && handoff queue 01-service
handoff drain                    # runs everything queued, one at a time, oldest first
```

Queueing steps 1 and 2 of one sequence looks like the obvious use and is the one thing the QUEUE
cannot do. The implementer leaves its changes uncommitted, so step 2's scope gate is charged with
step 1's files and fails for a reason that has nothing to do with step 2. Both rules that prevent
that — *commit between steps* and *stop on the first rejection* — are enforced by the queue rather
than requested: a second job for a repo that already has one is **refused**, and a rejected job
holds back that repository's remaining jobs and no other project's.

Use `handoff sequence` for steps within one repository, and the queue for work across several. The
difference is only that the queue cannot commit, which is what `sequence` was added to do — the
rule was ever about that limitation, never about sequences being unsafe. See `docs/queueing.md`.

**That includes another agent session.** `handoff do` and `handoff resume` now take a lock on
`.handoff/.lock` and refuse to start while a round is running in the same checkout, because the
rule above was written and then broken the same day: two sessions drove this harness at one
repository, one reverted the file the other was patching, and both got verdicts about each other's
edits. If you see `refusing to start: a round is already running`, that is the mechanism working —
find the other round rather than deleting the lock. A lock whose owner has exited is cleared
automatically and says so.

Before starting a sequence in a repository you do not have to yourself, check: `ls -la
.handoff/.lock` and whether anything else is holding the tree.

**Stop on the first rejection.** Do not run step 4 because step 3 failed — fix step 3's plan and
re-run it. Later steps usually assume the earlier ones landed.

### 4. Write the tests yourself, before the run

**This is the highest-leverage rule here.** If the implementer writes both the code and the test
that judges it, they agree with each other and are wrong together. A hand-written expectation of
`fresh: 6, stale: 1` caught an invented freshness rule; a model-authored test would have asserted
`fresh: 0, stale: 7` and passed green.

For anything numeric or stateful, write the assertions first, with the numbers you worked out
yourself. Then list those files under `## Files to read, not modify` so the implementer cannot
edit them:

```markdown
## Files to read, not modify

| Path | Why |
| --- | --- |
| `tests/Feature/RankingTest.php` | written by the reviewer; it judges this change |
```

The harness fails the round if a file listed there comes back modified.

**When step N produces a structure step N+1 consumes, assert its complete shape in step N.** Not
just the values the step's own criteria happen to read — every field, spelled as the later step
will spell it. A service was accepted on aggregates that were all correct; three fields the view
needed had been silently dropped and one renamed. Step 1 would have passed, and step 2 would then
have failed on a guarantee step 1 was supposed to provide. One assertion listing the full key set
costs a line and closes the gap.

### 5. Write the plan

Plans go where `.handoff/config.sh` says. Shape from `templates/plan.md`.

1. **One acceptance criterion, exactly one executable command, same order.** Enforced.
2. **Dictate the signatures** — exact names, parameters, return types.
3. **Assert against a stub, not against nothing.** The bar is not "would a do-nothing tree fail" —
   it is "would a *stub* fail". Four of ten criteria once passed against a three-line blade whose
   own comment said it only needed to render the string above. A single `assertSee('Rankings v2')`
   is indistinguishable from a real page. Assert what a stub cannot fake: the component type,
   several independent strings, a computed value, and the *absence* of placeholder markers.
4. **Name every file**, and assert the count:
   `test "$(git status --porcelain --untracked-files=all -- . ':(exclude).handoff' | wc -l)" -eq N`

   `--untracked-files=all` is not optional. Without it, `porcelain` collapses an untracked
   **directory** to a single line, so a plan that creates `src/newthing/` and asserts `-eq 2`
   passes with five files inside it. The guard is still there and has silently stopped guarding —
   and new-directory work is exactly when you most want it.
5. **Any named API that must be used deserves a grep criterion.** "Use `deduplicatedQueries()`"
   was prose; the model injected the dependency, never called it, and queried the table directly —
   which against real data would have inflated every count, because that method exists precisely to
   remove duplicate captures. `grep -q 'deduplicatedQueries' src/Foo.php` catches it in a second.
   The same applies to any constraint prose has already failed at once, "no scratch files" included.
6. **Anything you are tempted to repeat or bold needs a command instead.** Prose emphasis is not a
   control. A route-ordering constraint stated twice, in two sections, was still violated; what
   caught it was an acceptance command returning 404. If you find yourself writing "remember to",
   you have found a missing criterion.

   This has now been measured directly rather than argued. An arm whose only difference was an
   instruction to run the syntax checker after every write, and to repair before continuing, was
   run 20 times against 20 controls: **damage identical at 5/20, every outcome measure
   indistinguishable, and 38% slower.** Two prompt-layer variants have now been tested and neither
   moved anything. Instructions are not a mechanism. Criteria, gates and smaller steps are.

7. **Every state you name under `## States to handle` needs a criterion, or an admission.** A score
   is a fraction of the criteria and gets read as a fraction of the work. Those are the same number
   only when the states are gated. A page listing four viewport and theme states, none of them
   gated, scored 6/6 while shipping two contrast failures and an unscrollable overflow.

   If a check already covers the state but the linter cannot see it, say which one:
   `- [gated by criterion 1] an empty cart returns zero`. The match is between the state's words
   and the criteria's words, so a state covered by a TEST SUITE is invisible to it — the criterion
   says "the suite passes" and the state says "an empty cart returns zero". Ten states gated by one
   command all read as ungated, and without this form the only ways out were inflating the criteria
   to make them visible or writing `[unverifiable]` about something you had in fact verified.

   If a state genuinely cannot be checked from the command line, write it as
   `- [unverifiable] dark theme contrast`. `handoff roundup` then prints it next to the score, so
   the round-up never implies coverage the gates did not provide. Saying so out loud is worth more
   than a 6/6 that quietly means 6 of 10.

   **Write commands the implementer can actually run.** A verification block is not only the
   harness's; the model runs it too, and that is the only way it catches its own mistake before
   submitting. One round reported `blocked` — *"unable to execute the plan's verification commands
   due to shell quoting issues"* — over a tree the harness then scored 10 of 10. The code was
   right, the model could not check it, and it said so honestly rather than claiming a pass.

   That plan verified with eight `php -r '...'` one-liners carrying nested single and double
   quotes. A sibling plan using thirteen plain commands had half the rate of non-complete
   statuses. Correctness never depended on it, because the harness verifies independently — what
   is lost is the repair loop having anything to act on. Prefer a command the implementer can run
   over a clever one that only the harness will.

   **Do not hand-roll a changed-file count. The harness already answers that question.**

   A criterion like

   ```bash
   test "$(git status --porcelain --untracked-files=all -- . ':(exclude).handoff')" -eq 1
   ```

   looks like a scope guard and is a worse one than the gate you already have, for three reasons
   that each cost a round in a real project:

   - It is narrower than the harness's own exclusions, which also cover `.omc`, `vendor`,
     `node_modules` and `storage`. Agent state written into the tree is then charged to the model.
   - It cannot tell a file the model created from one that was **already** untracked. The harness
     can: it snapshots untracked files before the round and compares. `handoff init` itself writes
     a `.gitignore`, and a plan counting files failed on it while the harness's scope gate — which
     knew the file predated the run — correctly passed.
   - Plain `--porcelain` collapses an untracked DIRECTORY to one line, so the count stops guarding
     the moment the model creates a folder.

   The `scope` gate in the evidence bundle already reports every changed file the plan did not
   name, with pre-existing untracked files excluded, and it rejects the round on its own. Name the
   files in `## Files to touch` and let it do the work. If you want a criterion that says so out
   loud, assert the CONTENT you expect rather than a count of paths.

### 6. Check it

```bash
handoff prepare <slug>
```

One command: it runs `check-plan` (which refuses a plan the harness cannot score), then the plan
linter, then every acceptance criterion against the current tree. Fix what it rejects; read the
advisories. Acceptance is not quality.

The linter's findings are not style notes — each one is a round it cost someone:

| It says | What happened |
| --- | --- |
| `porcelain-collapse` | `-eq 2` passed with five files in a new directory |
| `ungated-states` | four states named, none gated, 6/6 over a page with two contrast failures |
| `coloured-output` | a grep that could not span the escape sequence in the middle of it |
| `one-sided-whitespace` | added blank lines counted; the damage was a removed one |
| `uncounted-zero-assertion` | see the next section — this is the one that produces malformed code |
| `symmetric-example` | two wrong proration implementations passed every criterion |

The dry run is the half that catches an unsatisfiable criterion before it costs a round. Anything
reported as **ALREADY PASSES** does not test the change; anything reported as failing should fail
for the reason you expect, and if you cannot say why, read the output it prints rather than
assuming.

**Watch for exit 2 specifically.** The gates here use three codes: `0` holds, `1` does not hold,
`2` could not check. A `2` in the dry run means your criterion is pointed at something the gate
cannot read — a file that is not built yet, a stylesheet with no document, a file that does not
parse. It rejects the round, so it is not dangerous, but it is not testing what you think either,
and it will still be `2` after the model has done the work perfectly. Read the reason it prints;
every gate that returns 2 is required to give one. See `docs/answerability.md`.

A criterion whose gate says `UNKNOWN` is a criterion you have not written yet.

### 7. Run it

```bash
HANDOFF_PROVIDER=${HANDOFF_PROVIDER:-native} handoff do <slug> >/tmp/run.log 2>&1; echo "verdict exit=$?"
```

**The provider is the user's to choose, and this line no longer overrides them.** It used to read
`HANDOFF_PROVIDER=native`, which quietly ignored `~/.config/agent-handoff/config.sh` and every
environment variable — so a person who had deliberately selected a different stack got `native`
anyway and had no way to tell from the output.

Which stack, and what is actually known about each:

| provider | what it changes | evidence |
| --- | --- | --- |
| `native` | the path every published number here was measured on | 29/30 on the six-file task |
| `nativeharmony` | OpenAI's renderer instead of llama.cpp's template | fixes two measured defects, below |
| `nativelow` | that, plus the report declared and grammar-enforced, reasoning `low` | 2/2 accepted on a real plan, 5 reports, none repaired |

The two defects `nativeharmony` fixes are mechanical, not preferences. llama.cpp's template
collapses every nested tool argument to `any[]`, so `read_files`' `start` and `end` are not in the
type the model is shown at all; and it JSON-quotes tool results, so a seven-line file arrives with
**zero newlines** and seven literal `\n` sequences. The model has never seen the line structure of
anything it was asked to edit.

**Unresolved, and the reason `native` is still the default here.** On the one real comparison so
far, green-on-first-attempt went 4/4 to 0/2 (p = 0.07) while generated tokens went *down* and
acceptance held — more attempts to reach the same place. That comparison was confounded and n=2.
Until the screen settles it, changing the default would be choosing on a hunch.

To run a different stack every time, set it once rather than per-invocation:

```bash
echo ': "${HANDOFF_PROVIDER:=nativelow}"' >> ~/.config/agent-handoff/config.sh
```

**Redirect; do not pipe.** `handoff do x | tail` returns *tail's* exit status, not the verdict, and
that has already caused a failing round to be reported as passing.

**Isolation.** The implementer runs arbitrary commands in the live working tree with approval
disabled. One run wrote a bootstrap script that booted the real application against the real
database. If the project has live services, a shared SQLite file, or anything else with side
effects, run it in a scratch worktree instead:

```bash
git worktree add ../scratch-<slug> -b <slug>
```

and work there. Nothing in the harness does this for you.

### 8. Report what actually happened

Read `.handoff/runs/<slug>/evidence/evidence.md` and `handoff diff <slug>`. Report the verdict,
which gates failed, what changed from the diff, any **advisory** findings, and anything under
**"Not checked"** — absence of failure there is not evidence of correctness.

**Never repeat the model's report as fact.** Reports have claimed success over untouched trees. If
the gates accept and the report is missing, say the patch is good and the report is missing.

The implementer never commits.

### 8b. Check whether the round happened at all before diagnosing it

```bash
handoff log <slug>          # outcome, criteria score, files, adapter errors — one line per round
```

If the **files** column is 0, the tree is untouched: the model never attempted the task, and an
adapter fault or a context overflow ate the round. Re-run the same plan once; do not re-specify it.
Backfilling three real runs found a context overflow in all three, which had been read as the model
failing.

**This column used to count tool calls and was not trustworthy.** It counted calls to a fixed list
of tool names, so it missed `replace_in_file` and every edit made through the shell — a reported
round that deleted eleven files showed 0, and following this section literally would have sent you
to re-run a round that had done the work. It now counts what the diff says changed, created or
deleted, so a 0 means the tree really did not move. That is the only version of this signal worth
acting on: if you are reading an older run, check the diff before trusting a 0.

**The evidence file's `tree-changed` gate had the same failure, from the other direction, and it
is also fixed.** The subtraction that stops stray untracked files being blamed on the model used to
excuse them by NAME, so a file that was untracked before the run and untracked after read as
unchanged however much it had been rewritten. That is the ordinary state mid-sequence: the plan
creates a view in one round, the next round edits it, and nothing has been committed in between
because this procedure tells you to review before committing. A reported round came back as *"the
working tree is unchanged; nothing was implemented"* over a tree that had in fact changed — the one
signature whose remedy above is to re-run rather than re-specify. It is now compared by content
against the run-start snapshot. **If you are reading a run from before that fix, read the diff.**

**A missing report is not a diagnosis, and it is not yours to fix.** The mechanism is now settled,
and the rate depends entirely on which implementer you are driving.

The model writes the report in full. llama.cpp's harmony parser cannot map it, the server answers
HTTP 500, and **the provider call ends there** — that last part was the missing half for months.
Across 71 archived runs a parse fault ended the call in 13 of 13 cases and no client re-asked;
22 of 29 runs that hit one lost their report, against 1 of 42 that did not (Fisher p = 2.5e-11).

`native` retries the completion, which recovers about 89% of them. Measured over one night, one
harness commit, one stack:

| implementer | usable tree | report survived |
| --- | ---: | ---: |
| `native` (default) | 18/18 | **18/18** |
| a rented CLI | 15/15 | 9/15 |

Both produced a usable tree in **every** round. If you are seeing a quarter of rounds lose their
report, check which provider you are on before anything else — that is the signature of driving
something other than `native`.

**That 18/18 is one night, one stack, and it is not the whole story.** Two rounds of real work have
since lost the report on `native` to a *different* failure: the completion came back with no JSON
in it at all — once at 4,346 characters, once at 0 — and the retry, which exists for parse faults,
does not help when the model simply answered without an object. Under investigation. Until it is
settled, treat the report as a convenience and the tree as the evidence, which is the standing rule
anyway: a round whose report is missing but whose gates pass is `patch-ok-no-report` and the work
is good.

Do not re-specify a plan over a missing report, and do not add instructions telling the model to
remember to report: that has been tried and cannot work, because the report is already being
written. Judge the tree.

`tools/peg-audit` reads the server's own log and will tell you how many were discarded, and at what
conversation depth. If the depths cluster high, that is your step-size signal.

**At the end of a session, run `handoff roundup <slug>`.** It assembles the rounds table, the
failing gates with their commands and output, and the mechanically-derivable causes, then files it
centrally at `~/.local/share/agent-handoff/roundups/` so patterns across repositories are visible
in one place. `handoff roundup --index` lists what has been filed.

It states infrastructure and refuses to state anything else. A failed acceptance command can be a
model defect, a criterion that could never have passed, or an ambiguous plan, and the harness
cannot tell those apart — so it prints the evidence and leaves the cause blank. **Those blanks are
the part worth filling in while it is fresh**, and they are the only record of the distinction that
matters most: whose fault the round was.

It also prints **what the score does not cover**: every state the plan named that no criterion
mentions, and every one it declared `[unverifiable]`. Read that section before writing "accepted,
6/6" anywhere — the two numbers are the same only when the list is empty.

`handoff stats` aggregates this across every run in the project, and `handoff retro <slug>` asks
the model — read-only, after it has been shown the verdict — what it would change about the plan.
Treat its answers as leads to check, not findings.

### 8a. Or hand the running to an operator

You are the expensive model, and the expensive part of your job is the specification, not watching
rounds go by.

For steps in this repository, `handoff sequence` is enough and needs no second agent — it commits
each accepted step and stops at the first rejection. Reach for an operator when the running needs
judgement the tool has none of: several repositories, a step you expect to need narrowing, or a
report written back to you in prose.

Once the plans are written and `handoff check` accepts them, another agent can run them:

```bash
codex          # then: /local-drive feature-1-service feature-2-view
```

`/local-drive` is the operator half of this pair. It checks the machine, runs each plan, reads the
verdicts, repairs once, escalates narrowly, commits accepted steps, and comes back with a report.
It is told in its own words that it may narrow a plan but may not redesign one, and that a plan
which is *wrong* rather than unclear is a finding to bring back to you rather than something to fix.

Before you hand over, make sure the plans can stand without you in the room:

- Every step's criteria are counted and commanded — `handoff check` on each one.
- The order is explicit, and each step says what it assumes about the ones before it.
- Reviewer-written tests exist and are listed under `## Files to read, not modify`.
- Anything you would have said out loud is in the plan. The operator will not know it otherwise.

Then say plainly what you want back: which steps, in what order, what to commit, and what to bring
to you rather than solve. The report you get is the input to your next round of planning.

### 8c. Or let the ladder do the retrying

```bash
handoff auto <slug>            # local ×2 → a hosted planner re-specifies → local ×2 → stop
```

`handoff auto` runs the loop below without you: the local model implements, repairs once against
the exact failing commands, and if it is still rejected a hosted planner (`codex` and `glm`,
alternating) writes a new, narrower plan and the local model tries that. It stops the moment the
gates accept, and hands back `.handoff/runs/<slug>/ladder.md` when they do not.

Use it for a step you have already specified well and expect to need a retry or two. Do the
diagnosis yourself — step 9 — when the failure looks like it is about the *task* rather than the
plan, because that is the judgement the ladder cannot make. Two rounds failing the same way is that
signal.

The ladder will not let the planner be the implementer, will not run a plan `check-plan` refuses,
stops as soon as a round scores worse than the round before it, and stops if a planner edits
anything except its own plan file.

### 9. When the gates reject — diagnose, then re-specify narrowly

**Never re-run the same plan.** The harness already retried it internally up to three times, handing
the model its failing commands each time. Running it again unchanged asks a question that has been
answered.

Your value here is the diagnosis, and it is the part of the loop the local model measurably cannot
do for itself. Two rounds tested the alternative — giving the implementer a richer account of its
own failure, then giving it git's account of the tree — and both made outcomes worse. Diagnosis is
judgement. Keep it on your side.

**Read, in this order:**

1. `.handoff/runs/<slug>/evidence/evidence.md` — which command failed, and its real output
2. `handoff diff <slug>` — what the tree now contains
3. The criterion that failing command was supposed to enforce

**Classify it, because the four causes have different fixes:**

| What you find | What it means | What to do |
| --- | --- | --- |
| It failed for a reason the plan never mentioned | The plan was ambiguous | Specify that one point exactly, and add a criterion for it |
| The command tests something the plan never asked for | Your acceptance command is wrong | Fix the command, not the code |
| The code is a stub that satisfies weaker criteria | The criteria were too coarse | Sharpen the assertions — the commonest case in view work |
| The code attempts the right thing and gets it wrong | A genuine model error | Narrow the step until the mistake has nowhere to hide |
| A criterion that could not pass over any tree — greps coloured output, asserts a path that moved | Your acceptance command is unsatisfiable | Read the command's own log first. A broken criterion and a broken implementation look identical from the verdict |
| Empty diff, `files` 0, ends in **seconds** on a few hundred tokens, often a report claiming success | Infrastructure failed; the plan was never exercised | **Re-run the same plan once**, then fix the adapter. Do not re-specify |
| Empty diff, `files` 0, ends on the **turn limit** after many searches and repeated identical reads | The model was asked and could not reach the target | Read the tool arguments. Do not re-run, and do not re-specify until you know what it could not reach |
| Empty diff, `files` 0, but the log shows writes that **succeeded** | Something else edited the tree mid-round | Nothing to diagnose about the plan. Find the other writer; the verdict is void |

Those two rows look identical in the verdict — no writes, no diff — and their remedies are
opposite. The clock separates them. Infrastructure that never asked the question finishes in 35
seconds on 1,336 output tokens; a model that was asked and could not answer burns its whole turn
budget. Check `.handoff/runs/<slug>/stdout.log` for tool-call format errors before concluding
anything about the plan.

**When it is the second row, read the tool ARGUMENTS, not the counts.** A round that searches 66
times looks like a model flailing, and the same log read one level down showed it was not: the same
`read_files` call returning the same 20,028 bytes three times, and searches for a declaration the
tool had already reported at line 914. Both anchors were past the read cap, so no available tool
could show them; the model's own reasoning asked for the missing capability by name. Three rounds
and ~25 minutes of GPU went to a loop that could not terminate, and two of those rounds were spent
because the table above said to re-run.

```bash
python3 - .handoff/runs/<slug>/stdout.log <<'PY'
import json, sys
for line in open(sys.argv[1], errors="replace"):
    if not line.startswith("{"): continue
    e = (json.loads(line).get("event") or {})
    if e.get("contentType") == "tool" and e.get("type") == "content_end":
        print(e.get("toolName"), json.dumps(e.get("args"))[:120])
PY
```

The tell is **repetition with no progress**: the same arguments, or a search whose answer the model
already has. A model repeating itself is telling you a tool did not give it what it asked for.

**Re-specify, do not re-ask.** Write a *new, smaller* plan covering only what failed — often a
single criterion. If step 3 of 5 failed one of its four criteria, the retry is a one-criterion step,
not step 3 again.

**Turn the diagnosis into a command, never into more prose.** If your instinct is to add "remember
to register the route before the catch-all", that instinct is the signal that a criterion is
missing. A constraint stated twice in prose was still violated; an acceptance command returning 404
caught it. Every retry should leave the plan with more executable checks, not more emphasis.

**Decide what happens to the failed attempt's changes**, and say so — the tree still holds them,
and every plan asserts how many files changed:

- **Revert and re-run** when the attempt was mostly wrong: `git checkout -- <files>`, then run the
  sharpened plan from a clean base. Usually correct.
- **Keep and follow up** only when the attempt was right as far as it went. The follow-up must then
  describe the *remaining* delta, and its file-count criterion must match what will actually change.
  This earns its keep: one round produced a complete, correct 162-line template whose PHP component
  block was malformed, and reverting would have thrown all of it away. When you keep work, protect
  it with a command rather than an instruction — "do not regenerate the template" is prose, while a
  criterion counting the bars it must still contain is enforcement.

**After two failures on the same step, split the step rather than attempting a third.** Two rounds
failing the same way is evidence about the task's shape, not about the model. This is where a
service-and-view step becomes a service step and a view step.

**This part is designed, not measured.** The rest of this skill rests on runs; the hosted-diagnosis
loop does not yet. Treat it as the best available reasoning, and be ready to find it wrong — two
other plausible improvements to the retry path already were.

## Quote what the step needs; do not point at where it lives

A plan that says "read `CrawlHost.php` for the columns" has bought the model a round trip. A plan
that writes the four column names down has not. This is the cheapest change measured here and it is
invisible until you look at the per-step numbers.

One run, three steps, one feature, same model and same afternoon:

| step | what the plan gave it | wall | iterations | input tokens |
| --- | --- | --- | --- | --- |
| 1 — the service | 3 files to go and learn from | **467s** | **81** | **1,937,495** |
| 2 — the page | 1 pattern to copy, rest inlined | 150s | 14 | 152,278 |
| 3 — the route | the exact line, quoted | **70s** | **18** | **103,729** |

Step 1 was **88% of the run's GPU tokens** and it wrote forty lines. The difference was not
difficulty. Its plan pointed at `CrawlHost`, `CrawlUrl` and `HostHealthService` so the model could
find out what the columns and the frontier states were called; steps 2 and 3 were told, and step 3 —
which was handed its one line verbatim — finished in seventy seconds.

Every fact the model must fetch is a read, a round trip, and the entire context re-sent. You already
know the four column names. Writing them costs you a line and saves it a file.

```markdown
## Files to read, not modify

| Path | Why |
| --- | --- |
| `tests/…/DeadHostReportTest.php` | written by the reviewer; it judges this change |
| `app/…/Models/CrawlHost.php`     | the table this reads          ← a round trip
```

```markdown
`crawl_hosts` carries `host`, `status` (`ok` / `unreachable`), `consecutive_failures`,
`last_reason`, `last_probed_at`. `CrawlUrl::STATE_PENDING` and `STATE_LEASED` are the two
frontier states that count as waiting.                                ← no round trip
```

Keep the file listed if the model should still see it. Listing it is not the cost; needing it is.

**The judge test is the exception and must never be inlined.** It is named so the model does not
edit it, and quoting the assertions into the plan would hand it the answers.

`plan-lint` notes this: a "Files to read, not modify" entry whose stated reason is a schema, a set of
states, a pattern or a signature gets flagged, while one that hands over a finished artifact
("step 1's output") does not. It is a note rather than a warning because it rests on a single run —
and it is keyed on the REASON rather than the file count, because counting rows fired on all three
steps above and told you nothing.

## Hand the plans over, then stop

Writing the plans and driving them are different jobs, and doing both in one session is measurably
expensive — not because supervising is hard, but because every turn re-sends the whole conversation,
and yours is the one carrying the research.

One comparison measured it directly. The session that wrote plans and then watched the harness run
them ended holding **369k of context per turn** against **166k** for the session that simply built
the feature itself. It was still carrying both skill files, 54K of project documentation, three
plans and three test files — none of it needed once the sequence was running, all of it charged to
every remaining turn. Combined with polling, that phase alone cost **146,571 output tokens and 307.7M
cache reads**, which is 7.2x more of the expensive model than the other session spent writing all
the code.

So when the plans pass `check-plan` and `prepare`:

    hand off the slugs and the repository path — to a subagent, or to a separate session
    stop

The driver needs the plans, not the reasoning that produced them. Give it the slugs and nothing
else, and let your own session end. If you want the result back, one turn of waiting is enough —
every verdict, score and attempt is in the journal when the sequence exits.

This is why there are two skills rather than one. The seat that decides a rejected round is fine
must not be the seat that wrote the criterion it failed — and keeping them in one context loses that
separation as well as the tokens.

## Assert the thing, not a number about it

Never write a criterion that counts occurrences. It has now cost two runs of the same benchmark,
and it fails three ways at once:

```bash
test "$(grep -c 'dead-hosts' routes/crawler.php)" -eq 3     # cost 81 minutes and 6.07M tokens
grep -qF "Route::livewire('crawler/dead-hosts', 'pages::crawler.dead-hosts')"   # what worked
```

**`grep -c` counts LINES, not occurrences.** A correct one-line route containing the pattern three
times returns 1. No dry run reveals this — `prepare` reports "fails now, count 0", exactly what a
not-yet-built step should report. Only reading `grep -c`'s semantics catches it, and the author who
wrote it had read them.

**A count is satisfiable by text that is not code.** Asked for three occurrences, the local model
appended `// dead-hosts route` and `// dead-hosts comment` — filler whose only purpose was to reach
the number. That is not obtuseness. A criterion IS the specification, it is stricter than your
prose, and it will be obeyed past the point where the prose stops. The plan said "one line, nothing
else moves"; the criterion said "three of these"; the criterion won.

**A count fights a shape bound.** The same step carried `patch-shape --max-added 2`. Reaching three
occurrences on three lines needed three added lines. The two were mutually unsatisfiable, and the
run proved it from both directions: roll 1 wrote the correct single line and failed the count, roll
2 split it across three lines and failed the shape. No tree could pass both, including a perfect one.

`plan-lint` now warns on any `grep -c ... -eq N` for N of 2 or more. `-eq 1` gets a note instead:
filler would BREAK it rather than satisfy it, so the gaming route is closed, though it is still
line-vs-occurrence confused.

The general rule, which covers more than grep: **a criterion should assert the thing you want, not
a measurement of it.** An exact-string check cannot be forged by a comment, does not compete with a
shape bound, and says in the plan exactly what the implementer is being asked for.

## Criteria are executed, twice, and nothing asks you first

An acceptance criterion is not a description of a check. It is a command, and two different parts
of the harness run it against the live tree with approval disabled:

- `handoff prepare` runs every one of them as a dry run **before the model does anything**;
- the gates run them again afterwards.

So a criterion is the most dangerous line in a plan. A reviewer wrote `php artisan migrate:fresh`
as one, on a repository whose `.env` pointed at a live Postgres database holding 977,526 crawled
pages. `prepare` would not have warned about it — prepare's job is to run each criterion and report
what it saw, so the more careful half of the workflow would have destroyed the database first and
then reported, accurately, that the criterion passed.

`check-plan` now refuses a plan containing one, and so do `handoff prepare`, `handoff sequence` and
the gates themselves. But the refusal list is a denylist and cannot be complete, so **read your own
criteria for what they will do, not only for what they assert.** The test is whether anything is
lost that the tree, git, or a re-run cannot bring back.

Assert the same thing without the damage:

| instead of | write |
| --- | --- |
| `php artisan migrate:fresh` | `php artisan migrate --pretend`, plus a test that the migration file exists |
| `git commit -am wip` | `git status --porcelain` shows the expected files — the reviewer commits |
| `rm -rf <path>` | assert what should be absent, rather than making it absent |

`HANDOFF_ALLOW_DESTRUCTIVE=1` exists for the case where every such command genuinely points at a
throwaway database. Setting it because a refusal is in the way is how the database goes.

## Acceptance commands that read tool output must not grep for colour

The harness runs every acceptance command with `NO_COLOR=1`, `TERM=dumb` and `CLICOLOR=0`. **That
is a reduction in risk, not a guarantee, and you must not rely on it.** Those variables are a
convention, and a tool that ignores them still colours its output — Laravel's test runner is
exactly such a tool, because it prints through Collision, which honours none of them. A reader who
trusted this paragraph in its earlier, stronger form dropped their own `sed` guard and lost a round
to it.

**So: pass the tool's own flag whenever it has one.** `artisan test --colors=never`,
`pytest --color=no`, `rg --color never`, `git --no-pager`. Then confirm with
`handoff check <slug> --dry-run`, which runs every criterion against the current tree and shows you
the output it is matching against.

The failure this produced is worth seeing, because it is the most confusing kind:

```
php artisan test | grep -qE 'Tests:[^0-9]*77 passed'
```

That criterion could not pass over **any** tree. artisan colours its output, and the escape
sequences between `Tests:` and the number contain digits:

```
^[[90mTests:^[[39m    ^[[32;1m77 passed^[[39;22m
```

so `[^0-9]*` can never span them. The tree was perfect, the suite really was at 77, and the round
was rejected. **A broken criterion and a broken implementation are indistinguishable from the
verdict alone** — which is why the first move on a failure is to read the command's own log, not
the diff.

Prefer counting to pattern-matching where you can: `test "$(… | grep -c …)" -eq 0` survives
formatting changes that a shape-matching regex does not.

## A criterion stricter than your prose is an instruction, and it will be followed

This is not the familiar "your acceptance command is wrong" case, where a broken criterion rejects
good work. It is worse: **the model reads the criterion as the specification and obeys it past the
point where your prose stops.**

The reported round described renaming two `div`s and asserted:

```bash
test "$(grep -c 'div' page.blade.php)" -eq 0
```

The file had a third `div` — the tagline — that the prose had never counted, and `div` matches
`</div>` as readily as `<div`. The model did what the criterion said: it changed an opening tag and
left the closing one. The result was malformed HTML, and the project's own 85 tests passed over it.
The plan caused the defect.

**A zero-assertion is a claim about every occurrence in the file, and you almost always mean the
ones you had in mind.** So, for any pattern you assert to zero:

- Count it first. `handoff prepare` does this for you and prints what the pattern matches today.
- Anchor it to what you mean — `'<div class="wrapper"'`, not `'div'`.
- If the count and your prose disagree, one of them is wrong, and it is usually the prose.

The general rule: your prose and your criteria are two statements of the same requirement, and
where they differ, the criteria win — because the criteria are what the model is graded on and
what it can check itself against. Read them together and make sure they say the same thing.

## A follow-up plan must name the files it is KEEPING

When a round half-works and you keep the good part, the next plan covers only what is left — and
the scope gate then charges the kept work as "modified out of scope", because those files changed
against the base commit and the new plan does not name them. Reported from real use: a follow-up
passed 6 of 6 criteria and was still `patch-damaged` for four deletions the reviewer had
deliberately kept.

**List them under `## Files to touch` with the action `keep`,** or the gate is measuring the
previous round rather than this one. The rule is that the plan's file list describes the tree's
whole diff from the base commit, not just the increment you are asking for.

## Size a step by what it must READ, not by how many files it writes

File count is the obvious heuristic and it is the wrong one. A step of four one-line deletions plus
"find two passages inside a 468-line file" looks tiny — five files, five trivial edits — and it
blew the turn limit, because the cost was never the writing. It was holding 468 lines of context
while looking for two things in it.

Bundling a surgical edit with trivial deletions is the specific trap: **the deletions make the step
look small and the surgical part sets the real depth.** Split the reading-heavy edit into its own
round.

## Views: the two gates that CAN see, and the one thing that cannot

The old wording here warned that a stub can fake a text assertion. That is true and it is the
smaller half. The observed failure was the opposite shape — substantial, correct-looking output
where every property that mattered sat outside what any command reached. The page was good. It
scored 6/6. It had a 1.7:1 wordmark, a 3.0:1 link, an unscrollable overflow and no heading element.

Two of those three are arithmetic, so they are commands now. Put them in the plan:

```bash
handoff contrast resources/views/pages/thing.blade.php --min 4.5
handoff view-lint resources/views/pages/thing.blade.php
```

**`handoff contrast`** resolves the cascade — selectors, specificity, inheritance, the nearest ancestor
background, alpha, and `prefers-color-scheme` layered on top of the base sheet — and computes the
WCAG ratio for every text/background pair it can reach. It catches the specific defect that a dark
block overrode `body` and `.card` and forgot the two colours declared elsewhere. It reports what it
could **not** resolve on every run; read that part.

**`handoff view-lint`** checks tag balance. Unbalanced HTML renders and passes everything, which is why the
malformed page above survived 85 tests. It also reports the `align-items: center` +
`min-height: 100vh` trap, which clips the top of an over-tall card with nothing to scroll to, the
heading outline, and siblings indented to different columns.

That last one arrived the way most of this tool's rules do: found by eye on real work, after both
gates and 345 tests were green — a drag handle at 16 spaces among siblings at 8. `pint` does not
format Blade, tag balance is unaffected, and every `assertSee` passes over it. It is advisory
unless you pass `--strict`, because indentation that is wrong is a review comment and a cosmetic
rule able to reject correct work would be the worse bug.

**A view plan must ask for a heading element.** The missing `<h1>` was a spec gap, not a model
error — the plan said "a centred card" and never said "heading", and the model was right to build
what was asked. That is the kind of gap a checklist prevents and blame does not.

**What is still ungated: whether it looks right.** Spacing, rhythm, whether the palette is pleasant,
whether the layout holds at 320px. Declare those under `## States to handle` as
`- [unverifiable] …` so the round-up says so, and budget for looking at the page yourself. The
value in specifying a palette is not that the gates check it; it is that writing down the exact
hex pairs forces the arithmetic that finds a 1.7:1 wordmark before it ships.

## Two things the gates cannot see

**Assert whitespace in BOTH directions.** A criterion counting *added* blank lines does not catch a
*removed* one, and removal is just as common: a heading came back flush against the paragraph above
it because the blank line that separated them was eaten. If you assert on blank lines, pin the
exact count rather than an upper bound — and check the count against the current tree first, since
a file that already violates it makes the criterion unsatisfiable.

**Whitespace scarring — a risk of EDIT steps, not delete steps.** This tells you which rounds need
the manual read: a step that only deletes whole files has no surviving edited file to scar, and a
pure-deletion round can be reviewed from the file list alone. A step that edits inside an existing
file is where it happens. A deletion leaves the blank line that surrounded it, and an edit inside a
nested block can come back re-indented. No acceptance command catches either — `grep -c` counts
occurrences, not blank lines, and a re-indented span still satisfies every functional test. In a
project with a formatter this is invisible because the formatter fixes it; in one without, it lands
in the commit. **Budget for reading the diff for whitespace by hand, and say so in the round-up
rather than pretending the gates covered it.**

**A file the model did not create can still be charged to it.** Anything already untracked in the
tree used to be reported as invented; that is fixed, and `handoff do` now records the untracked set
before the run. It is still worth having a clean tree, because a verdict over a dirty one is a
verdict about more than this round — which is what `doctor`'s warning is for.

## Setup

`tools/install-local` from the agent-handoff checkout — it links `handoff` into `~/.local/bin` and
writes `~/.config/agent-handoff/config.sh`, so any repository works with no per-project setup and
no `HANDOFF_PROVIDER` on the command line. `tools/install-local --check` reports it the way a
non-interactive shell sees it, which is the case a PATH export in `~/.bashrc` does not cover.

`llama-server` does not survive a reboot: `tools/llamacpp-serve start gpt-oss-20b 98304`.

**Say the context out loud, and assert it.** A server left running at 32768 while every document
said 98304 cost a benchmark night its first hour, and nothing objected — `doctor` only complained
*below* 32768. `HANDOFF_EXPECT_CTX=98304` makes it a failure rather than a line of output. On a
machine whose GPU also drives a desktop, `CALIBRATE_MARGIN_MIB=1500 tools/llamacpp-serve calibrate`
picks the largest window that stays resident; llama.cpp spills to host RAM rather than refusing,
which ends in swap thrashing and an OOM kill. Full guide: `docs/START-HERE.md`.
