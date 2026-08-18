# What the local implementer costs, measured

Five runs of two features, August 2026. Every number here came off a journal, a session transcript
or a git log; none is an impression.

## The short answer

**On a one-off feature of a few hundred lines, this route costs about twice the Claude tokens and
four times the wall clock of simply writing the code.** It is not a way to save tokens. It is a way
to move *implementation* off the paid model at the price of paying more to *specify* it — and for
small features the specification costs more than the implementation would have.

It pays when the specification is amortised across several features of one shape, when the
implementation is large relative to its spec, when you would write the tests anyway, or when the
big model cannot touch the repository at all.

## The runs

One feature — a crawler dead-hosts page, three files — built four times.

| run | route | T_plan | T_impl | total | rounds | Claude output |
| --- | --- | --- | --- | --- | --- | --- |
| cmp-claude | Claude writes it | 0:38 | 2:03 | **4:20** | 2 cycles | **59,418** |
| cmp-local-1 | harness | 9:04 | 81:29 | 91:45 | 7 | 289,009 |
| cmp-local-2 | harness | 8:51 | 12:07 | 21:38 | 3 | 124,836 |
| cmp-local-3 | harness | 8:20 | 8:57 | **18:34** | 3 | **118,555** |

A second Claude run of the same feature took 24:22, of which ~17 minutes was a hung test runner
(`php artisan test` without `--exclude-testsuite=Browser`). The 4:20 is the clean figure; the 24:22
is what a single environmental trap costs, and it is documented in CLAUDE.md now.

The improvement from 91:45 to 18:34 was not the model getting better. It was three defects removed
from the harness and the plans: a criterion counting lines where it meant occurrences, a regression
gate running the suite serially on every round, and a reviewer emitting 1,064 turns to say it was
waiting.

**Best case measured: 4.3x the wall clock and 2.0x the Claude output tokens.**

## Where the tokens actually go

Claude output by phase, best local run against the direct one:

| phase | claude direct | harness route |
| --- | --- | --- |
| reading | 20,988 | included below |
| **planning** | **10,991** | **99,630** |
| implementing | 20,279 | 17,321 *(supervision only)* |
| driving | — | 1,604 |
| verifying | 7,160 | included above |
| **total** | **59,418** | **118,555** |

**Planning is 84% of the route's cost and 9x what the direct run spent planning.** Supervision is
solved — 1,604 tokens for the driver — and was only ever expensive when a reviewer polled.

Within planning, roughly **89% is deciding rather than writing**: the artifacts come to 712 lines
(≈11k tokens) against 99,630 output. Reading the schema, spiking the query, working out that hosts
tie on count and so pagination needs a tie-break — that is the cost, and writing it down afterwards
is the cheap part.

## Why: the specification is bigger than the thing

```
reviewer authored    439 lines of plan  +  273 lines of judging tests  =  712
model shipped         87 lines
claude direct        290 lines total, including its own test
```

**712 lines specified to get 87 built.** That ratio decides the economics, and it is the worst
possible one: specification cost is set by the *shape* of the work, implementation cost by its
*size*. A feature shipping 87 lines can never repay a 712-line spec. A feature shipping 2,000 lines
from a spec of the same shape would.

## The levers, in order of what they are worth

### 1. Decide once, build many

The only large lever. Four panels sharing a registry share every decision that costs anything — the
panel shape, the fixture shape, how averages weight by `covered_seconds`, what NULL means. Paying
for those four times is the waste.

```
4 features planned separately   ~4 x 100k        =  400k
4 features, one design pass     ~100k + 4 x 15k  =  160k
claude direct, 4 features       ~4 x 59k         =  236k
```

The middle row is the only arrangement measured or projected in which this route wins on tokens.
Sequential features inheriting through files is the weaker form of it and is being measured now.

### 2. Make each step dense

A step adding **one line to a route file** still costs a plan, a criteria block and a round. A step
producing 300 lines costs about the same to specify. "One file per step" does not mean "small file"
— merge the wiring into the substantial steps.

### 3. Template the judging tests

273 lines per feature, differing across same-shape features only in fixture values and column names.
The second-largest block after the decisions themselves.

### 4. The small ones

Stop re-verifying what `verify-round` already verified. Skip the write-up in production. Together
these are 10-20%, not more.

### What does NOT work

**Delegating the decisions.** Measured: a greenfield feature with the design left to the model went
**0 accepted in 7 rounds**; the same model on a greenfield task with every decision dictated went
**30 accepted of 32**. Confirmed again by every defect in every run since — the specified parts came
back right and the unspecified parts came back wrong, four times running:

- a paginator `count()` reporting rows on the page, on an out-of-range page nobody listed
- a subheading *described* rather than quoted, transcribed into ungrammatical prose
- an empty state half-written, and scoring 6/6 anyway

**Shrinking the written plan.** The artifacts are ~11% of planning output. Halving them moves 2.0x
to about 1.9x.

**A smaller model for supervision.** Supervision is 1,604 tokens. There is nothing there to save.

## The reframe that changes the answer

Per-feature token accounting misses the thing this is actually good for: **a sequence costs Claude
about two turns end to end.** Fire it, work on something else for the 30-90 minutes the GPU grinds,
collect the verdict.

Two things get done for roughly 1.2x the tokens of one. That is the only framing under which the
route pays today, and the constraint is the machine-wide model lock: it buys one extra worker, not
many.

## When to use which

**Use the harness for** repetitive work of one shape; implementations that are large against a
stable spec; work you would write tests for regardless; anything you want running while you do
something else; and anything where the big model cannot touch the repository, where the comparison
is not 2x versus 1x but 2x versus impossible.

**Write it yourself for** one-off features under a few hundred lines; anything decision-heavy; and
anything you would finish by hand in under an hour. The skill said this from intuition before any of
it was measured. It is now measured: **4.3x the wall clock and 2.0x the tokens for a three-file
feature.**

## Amortisation: tested, and it did not appear

Two `/machine` panels built in sequence in one worktree, the second inheriting the first's registry,
plans, tests and four hard-won facts. Normalised by what each actually shipped:

| | feature 1 (pressure) | feature 2 (thermals) |
| --- | --- | --- |
| wall | 2:42:50 | 2:01:11 |
| lines shipped | 618 | 153 |
| rounds | 13 (9 rejected) | 9 (7 rejected) |
| **seconds per shipped line** | **15.8** | **47.5** |
| **Claude output per line** | **610** | **2,578** |
| **GPU input per line** | **29,062** | **99,890** |

The raw totals fell and the unit costs tripled. Feature 2 had the hard part built for it and was
still **3.0x the wall clock, 4.2x the Claude tokens and 3.4x the GPU tokens per line**.

**What did amortise** — and this part is real: the plan skeleton, the inlined-context tables, the
"Output discipline" section, the splice primitive, the shell-quoting rule, and the whole architecture
of the service test (a helper defaulting every measured column to NULL, a fixture with out-of-window
and other-host rows, a worked example whose two wrong answers straddle the right one). Reading the
previous feature's artifacts collapsed to about a minute, and reading them caught two defects
feature 1 had shipped before any GPU time was spent.

**What did not** is the thing that costs: writing a plan whose RECIPE survives execution. Both
features lost their rounds the same way — plan, three rejected rolls, re-specify as `b`, land it —
and in feature 2 both re-specifications were recipe mechanics again, not design.

The decisive observation is feature 2's, and it is sharper than anything the tooling had:
`bench/audit-criteria` passed 27 of 27 on a hand-built tree before the first round, **and the first
round still failed.** A criterion audit proves the destination is reachable. Nothing proved the
route was.

## Executing the recipe does not catch recipe defects — tried, twice

Every re-specification across two features was a `## Steps` recipe defect, so the obvious fix is a
tool that runs the recipe in a scratch tree before spending a round. It was built and it does not
work. Recorded here because it will be proposed again.

**As an idempotence test** it flagged all four plans of one feature — including the one that landed
14/14 on the first roll. `sed -i <N>r<file>` is deliberately not idempotent and it is the primitive
this project recommends, so the check fires on the correct case. (It is also unnecessary: `--reroll`
restores the tree, so a recipe always runs once on a clean one.)

**As an execution test** — do all commands exit 0, do the touched files still parse — it missed both
plans that actually failed and fired on one that landed:

    plan     outcome                    executes cleanly?
    6        3 rolls lost, 2,450s       yes
    6b       14/14 first roll           yes
    7        3 rolls lost               yes
    7b       rejected once, then 17/17  no

The reason is the same in both cases: these recipes execute perfectly. Plan 6's damage happened
because the MODEL wrote the temp block twice, so three lines went in where the plan assumed one and
every line below moved. Plan 7's happened because the model ran a `sed` twice. Neither is a property
of the recipe you can observe by running it — both are properties of how a model reads it.

So the best available check is structural, not empirical: `plan-lint` warns on more than one absolute
line number and on non-splice non-idempotent edits, and that caught 3 of these 4. The fourth is
model behaviour and no static check reaches it.

## What is still unmeasured

Whether planning amortises across MORE than two features, or under a recipe discipline that did not
exist while these two ran. Every run above measured a single one-off feature, which is the worst
case the route has. Four `/machine` panels are being built in sequence to answer it; the number to
watch is `T_plan` across features 2, 3 and 4, and the qualitative half is which artifacts a later
feature actually reuses.

Feature 1 of that series cost 2:42:50 and answered nothing by design — it introduced a section
registry into a 597-line monolith, which is the local model's weakest measured shape. Nine of its
thirteen rounds were rejected and eight of those were criteria the reviewer wrote wrong, which is
the standing finding of this whole exercise: **the specification is the failure surface, not the
model.**
