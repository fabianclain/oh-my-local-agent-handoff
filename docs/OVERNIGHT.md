# Running it overnight

The GPU is free for eight hours a night and the harness is the only thing that can use it without
supervision. This is how that time is spent, and how to read what it produced.

```bash
handoff overnight bench/queues/tonight.sh --until 07:00
handoff overnight bench/queues/tonight.sh --list          # what would run, and for how long
handoff overnight bench/queues/tonight.sh --resume <dir>  # after a crash, a kill, or a fix
```

---

## Waves, not rounds

The obvious schedule is one arm to n=20, then the next. Do not use it.

A wave is four repetitions of **every** arm, then a readout, repeated. Two properties follow, and
both matter more than they sound:

- **The arms stay balanced at every moment.** Whenever the night stops — a deadline, a dead server,
  you waking up early — there is a usable comparison at whatever n it reached. Sequential arms give
  you one complete arm and nothing to compare it against.
- **The feedback interval is under an hour.** By morning there is a *progression* of comparisons
  rather than a single verdict. At this plan's noise floor — roughly 20 percentage points at n≈15 —
  a single verdict quite often says "chance", and a progression at least shows whether the arms are
  drifting apart or sitting on top of each other.

The statistics at the end are identical. Only the failure mode differs, and only one of the two is
survivable.

`bench/run --append` is what makes this possible: it continues a provider's numbering instead of
refusing to touch an existing directory or deleting it. `--force` and `--append` together are
refused, because a queue that passed both would silently delete the arm it meant to extend.

## What the runner adds

`tools/overnight` runs no model. It sequences things that do, and supplies the discipline an
unattended run needs and an interactive one gets from the person watching:

| | |
| --- | --- |
| One at a time | Concurrent jobs share one GPU and measure contention, not the model |
| `doctor` before every job | A dead server is caught in seconds instead of recorded as eight hours of model failure |
| A deadline | `--until` refuses to *start* a job that cannot finish. A job killed half way has cost its whole runtime and produced nothing |
| Resume | A crash at 02:00 skips forward instead of ending the night |
| A log per job | Plus a summary written incrementally, so a `kill -9` still leaves a record |
| PATH | The harness is put on PATH before anything looks for it — cron and agent shells do not inherit yours |

A failed job does not abandon the queue; each is independent. A failed *preflight* does, because
the rest would record hours of failures that say nothing about the model.

The queue file is bash, sourced twice — once to collect jobs, once to run them. No parser, a job
line is a command line, and `--list` shows exactly what will run before anything does.

```bash
job wave1-control --cwd "$CLONE" --est 1500 --timeout 4200 -- \
    ./bench/run --plan wide --providers lcgptossl --repeat 4 --force
```

`--est` is what the deadline plans against; `--timeout` is when the job is killed. They are
separate because an estimate that doubles as a kill switch has to be pessimistic, and a pessimistic
estimate empties the queue by refusing to start anything.

## Sizing the night

Estimate from measured per-run time, not from hope. `wide` runs at roughly a 300s median, so a
four-repetition wave of two arms is about 50 minutes.

Two settings are lowered from their defaults for a queue, and both are about not wasting the night:

```bash
export BENCH_TIMEOUT_SECONDS=900   # default 3600 — one wedged run would cost twelve normal ones
export BENCH_MAX_ATTEMPTS=2        # default 3 — the third attempt mostly buys wall-clock
```

Drop to `BENCH_MAX_ATTEMPTS=1` when the variable under test acts on the first write. Then attempts
2 and 3 measure the repair loop, which is a different question from the one being asked.

## Reading it in the morning

```bash
cat .overnight/<date>/summary.md          # every job, its status, its wall time
cd "$CLONE" && ./bench/compare wide lcgptossl lcgptossllint --acts-on first-attempt
tools/peg-audit                           # what the parser threw away, and at what context depth
handoff stats                             # across every real run, not just the bench
```

Read `summary.md` first and specifically look for `skipped` and `blocked`. A night that ran twelve
of twenty-two jobs and a night that ran all twenty-two produce comparisons that look equally
confident, and only one of them is.

## Before trusting any of it

Two failure modes have each cost real GPU time here, and both are invisible from a results
directory.

**A prompt-layer arm that never applied.** An arm whose whole variable is a prompt — a different
rules file, an extra instruction — can be a silent no-op: the file missing, an export landing after
the read, an overlay not sourced. Every artifact looks identical to a working arm. Every run now
records the prompt it was actually sent, so check it:

```bash
grep -c '<the phrase that defines your arm>' "$CLONE"/bench/results/<plan>/<arm>/1/prompt-attempt-1.md
```

**An arm that is not committed.** Each attempt runs in a `git worktree` cut from HEAD, so the
harness a run uses is the *committed* one. An uncommitted provider file produces
`provider adapter not found` and a directory full of `status=skipped`. `tools/sync-bench-clone`
rsyncs the working tree into the clone and commits it there, which is why the queue syncs before
the first wave.

## Running the model on another machine

The harness runs where the repository is; only the model has to be near the card. Two variables,
kept separate on purpose:

```bash
# on the GPU machine — bind the Tailscale address specifically, never 0.0.0.0
LLAMACPP_BIND="$(tailscale ip -4)" tools/llamacpp-serve start gpt-oss-20b

# on the machine with the repository
export LLAMACPP_HOST=gpu-box.tail1234.ts.net
handoff doctor
```

`llama-server` has no authentication. Binding every interface publishes an unauthenticated model to
whatever network the machine is on, which is why `LLAMACPP_BIND` defaults to loopback and the
documented remote form names one address.

`doctor` probes `LLAMACPP_HOST`, so it tells you whether *this* machine can reach the model — which
is the question that matters, and not the same as whether the server is up. A sandboxed agent on
the same box can fail this while the server runs perfectly; Codex needs
`-c sandbox_workspace_write.network_access=true`.

## Context: measure it, do not pick it

```bash
tools/llamacpp-serve calibrate gpt-oss-20b
```

Ascends through candidate sizes, keeps the largest that stays fully GPU-resident with a margin, and
restarts the server on it. Both errors here are expensive and look nothing alike: too little
context and real rounds die with "exceeds the available context size"; too much and the KV cache
spills to host RAM, which does not fail — the server answers, slowly, until it fills swap and is
OOM-killed along with whatever terminal started it.

Run it whenever the weights, the llama.cpp build, or what else uses the card changes. It replaces
benchmarking a context size, which was the wrong shape of question: whether 96k fits is a property
of this card, answered in four minutes by trying it.
