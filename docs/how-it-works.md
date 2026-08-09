# How it works

The shape of the system, why each boundary exists, and which parts are load-bearing. Written for
someone picking this up cold — including me in six months.

---

## The idea

A hosted model is good at deciding what to build and at judging whether it was built correctly. It
is expensive to use for typing. A local model is free to run and fast enough, but cannot be
trusted to report on its own work.

So the hosted model writes a specification and reviews evidence; a local model does the work; and
a harness — not the model — decides whether the result is acceptable.

```
  hosted model
      │  writes a plan: exact steps, scope contract, acceptance criteria
      ▼
  agent-handoff harness
      ├── isolated git worktree from a fixed commit
      ├── operational rules (short, task-independent)
      ├── client tool loop  ──► serving engine ──► local model
      ├── gates: syntax, scope, litter, patch-only, acceptance commands
      ├── repair loop, capped, fed the failing commands
      └── evidence bundle: every claim tied to a command and its exit code
      ▼
  hosted model
         reads evidence, accepts or rejects, owns the commit
```

The hosted model never sees the implementer's own report. It reads evidence the harness produced.

---

## The four layers, kept apart on purpose

1. **Benchmark findings** (`docs/local-models.md`, `bench/COMPARISON.md`) — for the maintainer.
   Never shown to a model under test. Telling a model which mistakes it is expected to make
   contaminates the measurement.
2. **Operational rules** (`templates/agent-rules.md`) — short, task-independent, sent as developer
   instructions. Only the rule headings travel; the rationale table stays behind.
3. **The plan** — the task, and only the task. Exact signatures, a scope contract, acceptance
   criteria that each map to one executable command.
4. **The evidence** — what comes back. Commands, exit codes, digests.

---

## Why the plan has that shape

A plan is executable data, not prose. Three sections are parsed:

| Section | Parsed into | Enforced as |
| --- | --- | --- |
| `## Files to touch` | allowed-path list | scope and litter gates |
| `## Acceptance criteria` | the score denominator | one checklist item per command |
| `## Verification` | the score numerator | commands run against the tree |

`bench/run` refuses a plan whose checklist and command counts disagree. That is not pedantry:
`surgical-discount` shipped with six criteria and two commands, making 2/6 unreachable by
construction, and every model measured on it was understated until someone noticed.

**Difficulty means more work, not more decisions.** The implementer executes a specification; it
does not design. A harder plan has more files and more tool calls, not more ambiguity.

---

## The gates, and the failure each one exists for

Every gate was added after something specific went wrong. None are speculative.

| Gate | The failure it caught |
| --- | --- |
| syntax | A migration written as one line of literal `\n` characters, reported as complete |
| empty diff scores zero | Two fabricated successes scoring a middling `complete 1/6` |
| `false-success` label | `status: complete` with invented file paths over an untouched tree |
| patch-only | A 421-line service replaced by an 11-line fragment whose code was correct and whose destination was not |
| scope | Files changed that the plan never named |
| litter | Files *invented* — including one created and deleted across attempts, invisible in the final diff |
| byte-identical regions | A correct patch that deleted the declaration next to its insertion point, passing every functional test |
| criteria/command parity | A plan that capped every model below its real score |

**The report is never an input.** Status, summary and `files_changed` are recorded as untrusted
metadata and scored separately.

---

## The repair loop

Up to three attempts. After each, the harness runs the acceptance commands and, on failure, hands
back **its own list of commands that exited non-zero** — not the model's opinion of what went
wrong.

It works: a run that broke the fixture on attempt 1 and littered on attempt 2 came out correct on
attempt 3. It is also expensive — that run cost 1048s and 180 tool calls against a 182s median.
Which is why first-pass rate and time-to-green are different numbers and both matter.

---

## The serving stack is part of the result

The engine is a gate, discovered late and the hard way.

The same official gpt-oss weights scored **1/3 through ollama** and **4/4 through llama.cpp**,
then 15/15 on a four-file architectural task. Ollama's harmony path returns HTTP 500 for tool calls
its own model generated (`tools/repro-ollama-toolcall-500.py`), and the error surfaces through the
client, so it reads as a client bug. It cost a long investigation in which four confident
explanations were measured and discarded.

Consequently every result records its stack in `manifest.json`: engine and build, model-file
digest, context, KV type, GPU layers, client and version, reasoning level. Without it, "gpt-oss"
names several stacks that behave differently and the next provider regression gets blamed on the
model.

**Known-good pairing today:**

```
gpt-oss-20b (ggml-org MXFP4)  →  llama.cpp b10331, --jinja, 64k, q8_0 KV, all layers
                              →  Cline, openai-compatible provider
                              →  agent-handoff worktree + gates + evidence
```

`tools/llamacpp-serve start|stop|status` pins it; the adapter refuses to run if the server is
serving a different model, because one card holds one model and a leftover server would silently
benchmark the wrong weights.

---

## The verificator

`tools/verify-round <worktree> <plan> <base-commit>` produces `evidence.json` and `evidence.md`:
every gate with its command, exit code, an output excerpt and a sha256 of the full log — plus an
explicit list of gates that **did not run**, under the heading that absence of a failure there is
not evidence of correctness. Silent non-coverage is how a verifier turns missing evidence into
apparent proof.

It runs the project's own tooling — pint, phpstan, the test suite — only when already present.
A verifier that installs things to verify them is not a verifier.

> **Open:** `verify-round` and `bench/run` both implement "is this acceptable". Scoring still comes
> from `bench/run`. Two implementations will drift — they already disagreed once, and the verifier
> was wrong, counting a harness-staged plan file as something the model invented.

---

## Running things

```bash
tools/llamacpp-serve start gpt-oss-20b 65536      # pin the serving stack
bench/run --plan wide --providers lcgptossl --repeat 5 --force
bench/report                                       # every run individually, no aggregate score
tools/verify-round <worktree> <plan> <base>        # evidence bundle on demand
```

Plan slugs are short, ideally one word: a long hyphenated slug was mis-transcribed with
underscores and reported as a missing file.

---

## The rule that matters most

**A run blocked by the harness, the adapter, the configuration or the machine is void.** Not a
model result, not scored, re-run after fixing the cause.

The test: *could a different harness, configuration or machine have produced a different outcome
for the same model and prompt?* If yes, void it.

Nine harness defects have been found here, and most of the confident conclusions in this project's
history turned out to be one of them. The rule is what keeps the record honest.
