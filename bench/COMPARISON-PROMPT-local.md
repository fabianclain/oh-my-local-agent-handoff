IMPLEMENTER = local

<!-- ^^^ THE ONE LINE TO EDIT. Set it to `local` or `claude`. Nothing else changes. ^^^ -->

---

# Timed comparison: who implements, Claude or the local model

Read the `IMPLEMENTER` value on the first line of this prompt. It selects which of the two roles you
play, and it is the only difference between this run and the other one:

- **`IMPLEMENTER = claude`** — you write the implementation code yourself.
- **`IMPLEMENTER = local`** — gpt-oss-20b writes it, through the handoff harness, and you do not
  write implementation code at all.

Everything else below — the feature, the base commit, the verification, the reporting — is identical
in both runs, so any difference in the numbers is the implementer and nothing else.

If `IMPLEMENTER` is not exactly `local` or `claude`, stop and say so rather than guessing.

Derived from it, so you do not have to decide anything:

    FEATURE = a dead-hosts page for the crawler   (same in every run)
    BASE    = 015d078                             (same in every run — pinned, see below)
    NAME    = cmp-<IMPLEMENTER>-<N>

`<N>` is the first integer that does not already have a worktree. Check before you start:

    ls -d /home/fabbs/dev/bench-trees/cmp-<IMPLEMENTER>-* 2>/dev/null

If `cmp-local-1` exists, you are `cmp-local-2`. **Never reuse an existing worktree** — earlier runs
of this same experiment left finished trees with the feature already implemented and the plans
already written, and starting in one would measure nothing at all. If in doubt, pick a higher
number.

`BASE` is pinned to a commit rather than `master` so every run of this experiment builds from the
identical tree. `master` moves, and a run whose base differs from the runs it is being compared
against is not comparable to them. Confirm it with `git log --oneline -1` after creating the
worktree and put the SHA in your report — if it is not `015d078`, stop and say so.

Say which role you are running, and the NAME you derived, in your first message — so a glance at the
transcript shows the two instances are not both doing the same thing.

---

## 0. Read these first

Every path here exists; if one does not open, say so rather than working around it. Read in this
order and do not start the clock until you are done — reading is preparation, not the measurement.

Both runs:

- `/home/fabbs/dev/monolith/CLAUDE.md` — project conventions. The parallel-testing section matters:
  every worker's first `User::factory()` row is id 1, and a helper declared in one test file is
  invisible to another under `--parallel`. Those are the two failure modes that look like a runner
  problem and are not.
- `/home/fabbs/dev/monolith/docs/crawler.md` — the crawl's own documentation. Long; read the parts
  about hosts, the frontier, and skip reasons. "Throughput is not coverage" explains why dead hosts
  are tracked at all, which is the feature you are about to surface.
- The existing crawler code: `app/Domains/Crawler/`, and the one view that exists today,
  `resources/views/pages/crawler/⚡status.blade.php`. Match its conventions rather than inventing
  new ones — inline Livewire class syntax, user-scoped queries.

**`IMPLEMENTER = local` only** — you are writing a plan for another model to execute, which is a
different skill from implementing:

- `/home/fabbs/.claude/skills/local-implementer/SKILL.md` — how to write a machine-verifiable plan:
  what a criterion must look like, why each one needs a command that exits non-zero on failure, how
  to split a feature into one-file steps, and the failure modes of getting it wrong. This is the
  document that decides whether your run B is a fair test or a wasted afternoon.
- `/home/fabbs/.claude/skills/local-drive/SKILL.md` — how to run the plans and read a verdict.

**`IMPLEMENTER = claude` only** — do not read the two skill files. They describe how to write plans
for a local model, and reading them would push you toward a plan you would not otherwise write,
which is the exact cost this comparison is trying to measure.

## 1. Work in your own worktree, never in /home/fabbs/dev/monolith

Two instances editing the same tree would destroy each other's work, and the second one's timings
would be meaningless. Use the project's own tool rather than `git worktree add` — a plain worktree
boots a broken app for three separate reasons the tool documents (vendor must be hardlink-copied or
Composer resolves its base directory to the wrong repo and every test dies with "A facade root has
not been set"; `public/build` is gitignored so every page render throws ViteException; `storage/`
needs its framework subdirectories).

    cd /home/fabbs/dev/monolith/local-implementer
    TREE="$(bench/monolith-worktree <NAME> 015d078)"
    cd "$TREE"
    git log --oneline -1        # MUST print 015d078; if it does not, stop and say so

Do all work in `$TREE`. Do not commit to master. Do not touch the other run's worktree.

## 2. Start the clock, and keep four numbers apart

Record each boundary **twice**: as an epoch for arithmetic and as an ISO-8601 UTC stamp for the
token report.

    date +%s                      # for the durations below
    date -u +%Y-%m-%dT%H:%M:%SZ   # for bench/token-report --impl-start

Put the ISO stamps in your report. They are not decoration: `bench/token-report` splits your own
session transcript into planning and implementing at that instant, and it is the only boundary that
exists — a session is named by uuid and carries no clock, so a guessed split silently drops every
token on one side and reads exactly like a real answer. Without your stamp nobody can ever recover
what the planning half cost.

Report these four durations separately — lumping them together is what makes this kind of
comparison useless:

| number | what it is | why it must be separate |
| --- | --- | --- |
| `T_plan` | writing the plan | a cost run B pays in full and run A barely pays |
| `T_impl` | the implementer producing code | the number you actually came for |
| `T_verify` | running the acceptance checks | identical work in both runs; should cancel out |
| `T_wait` | queueing for the local model lock | **run B only.** Not the model's time. Excluding it is the whole point |

`T_wait` matters: `handoff do` takes a machine-wide lock, and other work on this machine may hold
it. That wait is a scheduling artefact, not a property of the implementer, and folding it into
`T_impl` would make the local model look arbitrarily slow depending on what else was running. The
harness prints `still waiting (Ns)` lines while it queues — sum them, or read `tools/gpu-queue`.

## 3. The feature — identical in both runs

Build a **dead-hosts page for the crawler**. Dead-host tracking already exists in
`app/Domains/Crawler/` (the most recent commit added it); what does not exist is any way to see it.
There is exactly one crawler view today, `resources/views/pages/crawler/⚡status.blade.php`, and the
routes are `crawler` and `crawler/status`.

Requirements, and stop at these — do not improve on them, because run A and run B must build the
same thing to be comparable:

1. A route `crawler/dead-hosts` and a Livewire page, following the conventions already in this
   repository (inline class syntax in the blade file, as every page in `resources/views/pages/` does).
2. The page lists hosts recorded as dead, showing for each: the host, why it was marked dead, when,
   and how many URLs are affected.
3. Sorted by affected-URL count, descending, and paginated.
4. Honest empty state: "no hosts have been marked dead" is a different fact from a page that failed
   to load, and must read as such.
5. Respects the existing multi-tenancy — the crawler models are user-scoped; do not bypass it.
6. A feature test covering: the page renders, a dead host appears with its reason and count, a live
   host does NOT appear, and the empty state.

Read the existing crawler code before designing anything. Follow `CLAUDE.md`.

## 4. Write the plan, and time it

Both runs write a plan first. Do not skip this in run A — the point is to measure the difference in
total cost, and a plan you would genuinely write for yourself is part of run A's cost.

**Run B (local) requires a machine-verifiable plan** in the harness's format: one file touched per
step, acceptance criteria each backed by a shell command that exits non-zero on failure, an explicit
out-of-scope section. It must pass:

    cd /home/fabbs/dev/monolith/local-implementer
    tools/check-plan "$TREE"/.claude/plans/<slug>-*.md

Split it the way the harness wants — data before presentation, each layer gated on its own tests,
roughly 3 steps for this feature. Name them `deadhosts-1-...`, `deadhosts-2-...`.

**Run A (claude) writes whatever plan you would actually write** to implement this yourself. It does
not need to pass `check-plan`. Do not artificially inflate or deflate it; write the plan you would
write if nobody were measuring. Save it to `$TREE/.claude/plans/` anyway so both plans can be
compared afterwards.

**`IMPLEMENTER = local`: dry-run every criterion before you start the sequence.** Not some of them.

    cd "$TREE"
    /home/fabbs/dev/monolith/local-implementer/bin/handoff prepare <slug>   # for EVERY step

This is the check that separates "the model got it wrong" from "this criterion could never pass",
and those two are indistinguishable from a verdict alone. A criterion that fails here because the
feature does not exist yet is expected and fine — that is the point of the step. What you are
hunting is a criterion that fails for a reason the step will never change: a lint or a test run
scoped wider than the plan's own files, so it trips on debt that predates the branch.

That is not hypothetical. A previous run of this exact experiment wrote

    vendor/bin/pint --test --format txt app routes resources

as a criterion for a one-line route change. It fails on pre-existing violations in `app/Domains/
Drive` and `app/Domains/Seap` — unsatisfiable over any tree, including a perfect one. It rejected a
correct attempt, triggered a re-roll that came back **worse**, and cost about twelve minutes.
`prepare` on that one step would have taken two. Scope every lint and test criterion to the files
the step actually touches.

Count `prepare` inside `T_plan`, not `T_impl` — it is part of getting the plan right.

Stop the `T_plan` clock when the plan is written, `check-plan` passes, and `prepare` has been run
on every step.

## 5. Implement, and time it

**Run A — IMPLEMENTER = claude.** Implement it yourself, in `$TREE`, following your plan. Normal
work: read, write, run the tests, fix what fails. Commit each step as you complete it.

**Run B — IMPLEMENTER = local.** Hand it to the harness and do not write any implementation code
yourself:

    cd "$TREE"
    /home/fabbs/dev/monolith/local-implementer/bin/handoff sequence --reroll 2 \
        deadhosts-1-<...> deadhosts-2-<...> deadhosts-3-<...>

`--reroll 2` asks a rejected step again from a restored tree. Let it run. Your job in run B is to
write the plan and report what the harness decided — not to fix the model's code. If a step is
rejected on all three rolls, record that as the outcome; do not implement it yourself, because
"the local model could not do this" is a result and papering over it destroys the measurement.

Stop the `T_impl` clock when the last step is committed or the sequence stops.

## 6. Verify both runs the same way

This is what makes the two runs comparable at all: the same checks, run against both trees.

    cd "$TREE"
    php artisan test --compact --parallel --exclude-testsuite=Browser
    vendor/bin/pint --test --format agent

And the three gates that catch what tests do not — all three found real defects in shipped,
human-reviewed code, and the first one fired in 72% of rounds the harness ACCEPTED:

    H=/home/fabbs/dev/monolith/local-implementer
    FILES=$(git diff --name-only master...HEAD -- '*.php')
    python3 $H/tools/invisible-characters $FILES
    python3 $H/tools/process-commentary   $FILES
    python3 $H/tools/blade-balance        $(git diff --name-only master...HEAD -- '*.blade.php')

## 7. Report

Print exactly this table, then the notes below it.

    IMPLEMENTER      <claude|local>
    base SHA         <sha>
    T_plan           <mm:ss>
    T_impl           <mm:ss>
    T_verify         <mm:ss>
    T_wait           <mm:ss>   (local only; 00:00 for claude)
    impl started at  <ISO-8601 UTC>   (the T_plan -> T_impl boundary)
    ------------------------------------
    TOTAL (excl wait) <mm:ss>

    steps planned    <n>
    steps landed     <n>
    rounds/attempts  <n>        (local: rounds run, from the journal. claude: your edit-test cycles)
    tests            <pass/fail counts>
    pint             <clean | n files>
    invisible chars  <clean | n files>
    edit narration   <clean | n files>
    blade balance    <clean | n>
    diff             <n files, +n/-n lines>

Then run the token report and paste its output verbatim:

    /home/fabbs/dev/monolith/local-implementer/bench/token-report <NAME> --impl-start <your ISO stamp>

It reads the harness journal for what the implementer spent per round, and your own session
transcript for what planning cost. It deliberately refuses to add the two together when the arms
differ: Claude tokens are billed and gpt-oss tokens are electricity, and a combined total erases
the only economic difference between the arms. Compare **output tokens**, which are work actually
done and counted the same way on both sides.

Then, in prose:

- **What the implementer got wrong, and how you found out.** Be specific and do not round in its
  favour. For run B, quote the rejected rolls' scores.
- **Anything you had to decide that the plan did not settle.** This is where the two runs diverge
  most and it is the least visible cost.
- **One thing that would have made this faster.**

## Rules that keep the two runs comparable

- Do not read the other run's worktree, plan, or report. If you know what the other instance built,
  you are no longer measuring a cold start.
- Do not change anything under `/home/fabbs/dev/monolith/local-implementer` — that is the harness
  being used to measure, not part of the work.
- Do not `git push`. Do not commit to `master`.
- If you get blocked, record the blocker and the elapsed time and report it. A blocked run is a
  finding. Silently switching approaches is not.
- Report the numbers you measured, including the unflattering ones. If run A took twenty minutes and
  produced something with a failing test, that is the result.
