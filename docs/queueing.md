# Several projects, one model

Two rounds against the local model at once do not fail. That is the problem.

`llama-server` here runs four slots, so a second `handoff do` is served rather than rejected —
both rounds finish, both print a verdict, and both verdicts are about a machine that was doing
something else at the same time. What breaks is quieter than a crash, and `providers/lcpp.sh` had
already written down what it is:

> The mark is a byte offset into the server log, and the count is taken over the region appended
> between two marks. That attribution is only sound because **exactly one benchmark runs at a time
> on this machine**… A second client talking to the same server would be counted into whichever
> run happened to be open.

So the lock is not protecting the GPU from saturation. It is protecting the **measurement**.

---

## What happens now when the model is busy

```
==> the local model is busy — waiting
    holder:   02c-2-view in /home/fabbs/dev/devize (pid 12345, 3m12s so far)
    you are:  #2 of 2 waiting
    estimate: ~9m47s (median round 5m30s over the last 12)
    (Ctrl-C to give up; nothing has been written yet)
==> still waiting (120s)
    ...
==> the model is free — starting
```

Nothing is written to your tree until the round actually starts, so Ctrl-C during the wait costs
nothing.

**Where the estimate comes from.** Every completed round appends its duration to
`~/.cache/agent-handoff/durations.tsv`, tagged with the provider. The estimate is the median of the
last twenty for *that provider*, plus one round for each person ahead of you, minus however long
the current round has already been running.

**When it has too little history it says so and gives no number:**

```
    estimate: no estimate — 1 recorded round for native, 3 needed
```

That refusal is the point. "About four minutes" over a single prior data point is the same fault
this project keeps finding in its own gates — see [answerability.md](answerability.md).

**When the model is free, none of this prints.** A queue that announces itself when there is no
queue is noise, and noise is how a real message gets skimmed past.

---

## Handing off from several projects at once

The wait above is enough when you are sitting there. For fire-and-forget:

```bash
cd ~/dev/projectA && handoff queue 03-service     # enqueue, don't run
cd ~/dev/projectB && handoff queue 01-model
handoff queue                                      # what's waiting
handoff drain                                      # run them, one at a time
handoff drain --once                               # just the next one
handoff drain --until 07:00                        # stop starting jobs after that
```

Jobs run oldest first, each in its own repository. The drainer calls `handoff do`, so it takes the
same lock — an interactive round and a drain serialise against each other correctly, and you can
start one while the other is running.

**A typo is refused when you queue it**, not when it runs. The same mistake found at 2am is a job
that silently did nothing.

**A rejected job is a result, not a wedge.** The queue records it and moves on. It is not retried:
the harness already retried it internally up to three times, and the response to a rejection is a
new, smaller plan written by a person.

---

## Telling something else that a round finished

```bash
export HANDOFF_CALLBACK='my-notify-script'
```

The command receives the event as JSON on stdin, and `$1` `$2` `$3` as verdict, slug and repo:

```json
{"event":"ai-run-end","slug":"03-service","repo":"/home/you/dev/a",
 "verdict":"accepted","exit":0,"seconds":331,"started":"2026-08-13T18:04:11Z"}
```

`ai-run-end` carries **the verdict the gates reached**, never the model's own claim — the same rule
as everywhere else here. A provider that exited cleanly over a rejected tree ends `rejected`.

It is best-effort by construction and deliberately outside the verdict. A webhook that is down must
not turn an accepted round into a failed one.

---

## Knobs

| | |
| --- | --- |
| `HANDOFF_GPU_WAIT` | seconds before the backstop `flock` gives up (default 7200) |
| `HANDOFF_CALLBACK` | command run when a round ends |
| `HANDOFF_STATE` | where the register, history and spool live (default `~/.cache/agent-handoff`) |
| `tools/gpu-queue status` | who holds it, who is waiting, what the estimate is |
| `tools/gpu-queue history` | what the estimate is drawn from |

---

## What this deliberately does not do

**No parallelism.** One round at a time is the whole point; running two would restore the bug.

**No priorities, no scheduling.** Oldest first. A queue that needs configuring to be understood is
a worse tool than a list.

**It does not lock out cloud providers.** Only providers that drive the local server take the lock
— `lcpp`, `ollama`, and everything built on them. A GLM or Codex round does not queue behind a
local one, because it is not competing for anything.

**It cannot stop a person editing the tree mid-round.** The repository lock stops a second
`handoff` process; nothing stops an editor. That rule stays where it has always been: nothing
should touch the tree between `handoff do` and its verdict.
