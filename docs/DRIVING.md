# Driving it: who does what, and how to approach a task

Three seats, three different jobs. The whole arrangement exists because they are genuinely
different kinds of work, and because a model that does two of them is checking itself.

| Seat | Runs as | The job | Why not one of the others |
| --- | --- | --- | --- |
| **Planner** | Claude Code, `/local-implementer` | Turn a request into a specification whose every claim is mechanically checkable | This is the measured bottleneck. 48 of 48 plans written for human review were unrunnable, and every defect that shipped in ~30 real rounds came from a specification |
| **Operator** | Codex, `/local-drive` | Get those plans through the gates; repair, narrow, commit accepted steps, report | Cheap per hour, patient across a long loop, and it did not write the plan — so it has no stake in defending it |
| **Implementer** | the local model, `HANDOFF_PROVIDER=local` | Write the code | Free at inference. Reliable when the specification is mechanical, unreliable at deciding anything |

The gates decide. Not the planner, not the operator, and never the implementer's own report.

---

## The short version

```bash
# 1. Plan — in Claude Code, in the project you are changing
/local-implementer add a rankings page that shows position changes over 30 days

# 2. Hand over — Claude writes .handoff/plans/*.md and checks them, then stops

# 3. Run — in the same project, in Codex
codex --sandbox workspace-write -c sandbox_workspace_write.network_access=true
/local-drive rankings-1-service rankings-2-view

# 4. Read the report, and the branch it left behind
handoff log
git log --oneline
```

**The network flag is not optional.** Codex sandboxes the workspace by default, and the local
implementer is reached over HTTP on `127.0.0.1` — so without it every round fails to contact a
model server that is running perfectly well. `handoff doctor` reports this as "nothing answering",
which is true from inside the sandbox and misleading from outside it.

Codex also needs `handoff` on PATH. An agent's shell does not always inherit an interactive PATH,
so either export it before launching Codex, or let the skill use the absolute path to `bin/handoff`
in the checkout.

You can run every seat yourself with plain commands; the skills are a convenience, not a
requirement. `docs/usage.md` has the full command surface.

---

## Before anything else

```bash
handoff doctor
```

Ten seconds, read-only, and it answers the question that otherwise gets answered wrong: is this a
model failure or an environment failure? It checks that `handoff` is on PATH, that the project is
initialised, that the tree is clean, that llama-server is up and how much context it has, that
Cline is pointed at it, whether the model is actually GPU-resident, and which hosted planners are
available.

Six harness defects in this project were mistaken for model behaviour before anyone checked. The
evidence bundle cannot tell the difference; `doctor` can.

---

## Approaching a task

### Decide whether this is a job for a local model at all

It is a good fit when the change is mechanical against code that already exists, the signatures can
be dictated, and success is a command's exit status. Measured on that shape: 78% first attempt, 93%
within three.

It is a poor fit for greenfield design, for anything where a plausible wrong answer looks like a
right one, and for work that needs judgement about what the code should do. Measured on that shape:
**0 accepted in 7 rounds** on one real feature, where the reviewer then wrote the same service by
hand and it passed 8/8 first run.

Between those, the useful move is to split the task rather than to abandon it. Write the part that
needs judgement yourself; hand over the mechanical remainder.

### Write a sequence of small steps, not one plan

A step is one to two files, three to six criteria, one coherent behaviour. Write the whole sequence
up front and run them one at a time.

Smaller steps are **not** measurably more likely to succeed on their own — a six-file plan scored
87% against a four-file plan's 80%. What they buy is cheap failure, localised diagnosis, banked
progress, and criteria a stub cannot fake. Narrow scope is what lets a criterion assert something
specific.

Cut pure logic away from anything that renders. A service class is close to an ideal fit; a view is
the easiest thing in a codebase to satisfy with three lines that mean nothing.

### Write the tests yourself, before the run

The highest-leverage rule here. If the implementer writes both the code and the test that judges
it, they agree with each other and are wrong together. A hand-written expectation of `fresh: 6,
stale: 1` caught an invented freshness rule; a model-authored test would have asserted `7/0` and
passed green.

List those files under `## Files to read, not modify` and the harness fails any round that modifies
them.

### Make every criterion a command

One acceptance criterion, exactly one executable command, same order. The harness refuses a plan
where the counts disagree, because six criteria against two commands caps the score at 2/6 by
construction.

Anything you are tempted to repeat, bold, or say twice needs a command instead. A route-ordering
constraint stated in two sections was violated anyway; an acceptance command returning 404 caught
it. If you find yourself writing "remember to", you have found a missing criterion.

---

## Running it

### Isolate first

```bash
git worktree add ../project-featurename -b featurename
```

The implementer runs arbitrary commands against a live tree with approval disabled, and nothing in
the harness isolates that. One session lost its development database with no backup; the leading
candidate is a scratch script that booted the whole application against the real one.

A worktree is not isolation if the database is not. Copying `.env` brings an absolute
`DB_DATABASE` with it and points the worktree straight back at the live file.

### Commit between steps

Every plan asserts how many files changed, and that count includes whatever step 1 left
uncommitted. The operator commits accepted steps for exactly this reason — and never pushes,
amends, or commits a rejected round.

### Let the ladder handle the retrying

```bash
handoff auto <slug> --planners glm --escalations 1
```

Local implements, repairs once against the exact failing commands, and if it is still rejected a
hosted planner writes a narrower plan and the local model tries that. It stops the moment the gates
accept, and leaves `.handoff/runs/<slug>/ladder.md` as the handover when they do not.

---

## Reading a failure

`handoff log <slug>` first. The **writes** column decides everything that follows.

| What you see | What it is | What to do |
| --- | --- | --- |
| `writes` 0, adapter errors | The round never happened | Re-run the same plan **once**. Do not re-specify |
| `context-overflow` | The task did not fit the window | Split the step. More instructions make this worse |
| `output-token-limit` | The turn was cut off mid-write | Expect a truncated file. Split the step |
| Score dropped from last round | The repair is damaging the tree | Stop resuming. Revert to the last good state |
| A specific criterion failed | The model got it wrong | Repair once, then narrow |

That first row matters more than it looks. Two of seven rounds in one real feature never reached
the model at all, and both were scored as model failures. Re-specifying a plan that was never asked
is the most expensive way to make no progress.

### When to take over

- **Two rounds failing the same way.** That is evidence about the task's shape, not the model's
  ability. Split it, or write it yourself.
- **The fix would change what the feature does.** That is a planning decision, and it goes back to
  the planner.
- **A criterion keeps failing and you are tempted to loosen it.** Loosening a criterion until the
  tree passes produces a green verdict that means nothing.

---

## The rules that are enforced, not requested

Worth knowing, because they shape what the other seats can do to you:

- The planner in a ladder **may not be the implementer**. The ladder refuses to start.
- A planner may write its plan file and `.handoff/ladder-notes.md`. **If it edits source, or the
  harness that judges the work, the ladder stops** and hands you the diff. A model editing its own
  grader is self-approval by another route.
- A plan the planner produces **must pass `check-plan`** before the local model is sent at it.
- A round that scores **worse than the round before it** ends the repair loop immediately.
- Files listed under `## Files to read, not modify` must come back byte-identical.
- The implementer never commits.

---

## Cost, roughly

The local model is free at inference and costs about five minutes a round on a 16 GB card. The
hosted seats are where the money goes, and the design is aimed at keeping them out of the loop
until they are needed: a rejected round should never reach a hosted reviewer, because if every
attempt costs hosted tokens to triage, the case for a local implementer collapses.

That is why the harness verifies before anyone looks, why the operator is a cheaper model than the
planner, and why escalations are bounded and have to be asked for.

---

## Where to go next

| | |
| --- | --- |
| [START-HERE.md](START-HERE.md) | Setup, your first plan, reading the verdict |
| [usage.md](usage.md) | Full command surface, the journal, the ladder |
| [OVERNIGHT.md](OVERNIGHT.md) | Running a queue unattended, waves, and driving the model over Tailscale |
| [how-it-works.md](how-it-works.md) | The gates and the four prompt layers |
| [local-models.md](local-models.md) | Every measured finding, and the conclusions that turned out wrong |
