# The report that never arrives

The largest non-success outcome this project has: a round that produces a correct tree and no
completion report. Measured across 182 archived runs, **40 of them — 22% — produced no report at
all**, and it gets worse with depth:

| conversation depth | n | reported |
| --- | ---: | ---: |
| below 9k | 16 | 16 (100%) |
| 9k–20k | 62 | 50 (81%) |
| above 20k | 104 | **76 (73%)** |

This is the record of finding out why, on 2026-08-16. Two causes account for 88% of it, and the
second one had been hidden behind a label in our own diagnostic.

---

## 1. What the causes actually are

`tools/report-audit` derives a reason for every lost report. Run over the archive:

| cause | n | share |
| --- | ---: | ---: |
| peg fault ended the call | 21 | 53% |
| **reasoned, and emitted no final message** | 14 | 35% |
| turn limit reached | 2 | 5% |
| fallback carried no report | 2 | 5% |
| context budget / no fallback recorded | 2 | 5% |

### The second one was invisible until the tool was fixed

Before today the middle row read **"turn limit reached", 14 runs**, and every reader — including
this one — went looking at the turn cap. The reason ordering tested `turn-limit` before looking at
what the fallback had actually returned, so a round whose fallback ran **twice and came back empty**
was filed under the turn budget.

The fallback had run in all 14. What it returned:

```
ledger/native/1      finish='stop'  chars=0  out_tokens=858
ledger/native/1      finish='stop'  chars=0  out_tokens=1937
wide/nativeraw/3     finish='stop'  chars=0  out_tokens=1435
site-dark/native/20  finish='stop'  chars=0  out_tokens=1091
```

**858 tokens generated, zero characters of content.** The model spent the report turn in the
analysis channel and never emitted a `final` message. That is the behaviour `docs/roadmap.md`
recorded as "33–40% of first attempts end with a reasoning block, a tool call, and no text block" —
still present, still the dominant remaining cause, and mislabelled in the tool built to find it.

Fifteen of the twenty-four failed report turns examined were empty this way. The rest: five long
replies with no JSON in them, four short ones.

---

## 2. Both dominant causes are removed by the harmony stack

### Peg fault (53%) — the parser never gets the chance

llama.cpp discards a completion whose header it cannot map and answers HTTP 500 with the text gone.
It is **stricter than the harmony specification**: `docs/format.md` says the recipient "might be
defined in the role or channel section of the header" and that `<|constrain|>` is optional, which
are exactly the shapes it rejects.

On the raw path (`nativeraw`, and everything built on it) the harness parses harmony itself, so
that parser is not in the loop. On the first real round of the new stack: **zero discarded
completions**, and eleven tolerances fired — eleven completions the spec permits that llama.cpp
would have thrown away.

### Reasoning without answering (35%) — the grammar makes it unrepresentable

`providers/nativegrammar.sh` constrains the report turn with a GBNF built from the schema and
wrapped in the harmony envelope:

```
root     ::= analysis? final
analysis ::= "<|channel|>analysis<|message|>" thought "<|end|><|start|>assistant"
thought  ::= ([^<] | "<" [^|])*
final    ::= "<|channel|>final<|message|>" report "<|return|>"
```

The model **may** think first. It **cannot** stop after thinking: the sampler cannot reach
end-of-sequence without emitting a `final` message whose body satisfies the schema.

Measured on the first real round: five report turns, five reports, every one
`candidates=1 score=7/7 repaired: false` — one JSON object, all seven schema keys, the extractor
never working.

**The limit, stated because it is real.** The grammar prevents *choosing* not to answer. It does
not prevent *running out of context* mid-thought: `thought` is unbounded. A round that exhausts its
window while reasoning still loses the report, and `RESERVE_FOR_REPORT` is what addresses that.

---

## 3. What was missing from the evidence, and now is not

Every diagnosis above worked from **token counts**, because the text was never written down. The
log recorded that a turn produced 1,435 tokens and 0 characters; it did not record what those
tokens were. A turn with 1,435 output tokens and 1,400 characters of reasoning is a model that
thought and never answered. One with 1,435 output tokens and no reasoning either is something else
entirely. Those two were indistinguishable in every artefact this project produced.

Two additions close it:

- `report_turn` now carries **`reasoningChars`**, so the split between thinking and answering is in
  the log for every report turn, successful or not.
- A failed report turn emits **`report_lost`**, carrying the tail of the content, the tail of the
  reasoning, and the raw harmony when the raw path is in use. Bounded, because a reasoning channel
  runs to thousands of tokens and this is a diagnostic rather than an archive.

`tools/peg-capture` closes the other half: each attempt saves the completions llama.cpp discarded
into `discarded-attempt-N.txt`, bracketed by the same byte offset the token accounting uses. Before
it existed, **99 archived samples — the entire evidence base for the harmony fault — were lost to
log rotation**, and three survived by accident and overturned a model verdict the same day. While
the tool was being tested, the rotation holding those three was pruned as well.

---

## 4. Trying to trigger it

`tools/replay-final-turn` re-asks the report question against a conversation that really happened,
at about ten seconds a sample instead of the forty minutes a wave costs.

Replaying `wide/nativeraw/3`, whose report turn produced 1,435 tokens and nothing: **4 of 4 samples
produced a report.** The tool's own warning explains why that is not a refutation —

```
depth: replay 33,626 against the original's 19,388 (173%); bands 32k-48k and 16k-32k
       — NOT COMPARABLE, different fault-rate band
```

— the rebuilt conversation does not carry Cline's system prompt and tool schemas, so it lands in a
different depth band from the round it came from. At an ~8% per-round base rate, four clean samples
is also what you would expect from a fault that is simply intermittent.

**So the fault is not reproduced on demand yet.** That is worth stating plainly rather than
implying the grammar is proven to fix it: what is proven is that the grammar makes the shape
impossible, and that five report turns under it came back clean. The absence of a trigger is a gap
in the evidence, not a result.

---

## 5. What changed, in one place

**Fixed**

- `report-audit` blamed the turn limit for 14 rounds whose fallback ran and returned empty. It now
  names the fault and quotes the token count, with a regression case for the mis-attribution and a
  control so a 12-token empty reply is not called reasoning.
- The nested GPU-lock deadlock: `bench/run` held the lock and never told its rounds, so every round
  waited on its own parent, with no deadline.
- `llamacpp-serve` measured residency with `VmRSS`, counting the mmapped GGUF's page cache as a
  spill; served a different model than asked for whenever a systemd unit existed; and corrupted the
  context file on a failed start.
- Both skills hardcoded `HANDOFF_PROVIDER=native`, silently overriding a configured choice.

**Built**

- `tools/capability-baseline` — eight probes, 0/1/2 exit codes, so a model change cannot quietly
  break tool calls, the report channels, or stop-discipline.
- `tools/harmony_render.py` — OpenAI's renderer instead of llama.cpp's template, because the
  template collapses every nested tool argument to `any[]` and JSON-quotes tool results, so a
  seven-line file reached the model with **zero newlines**.
- `tools/schema_grammar.py` — a GBNF from a JSON Schema that refuses rather than approximates.
- `tools/peg-capture` — each round keeps the completions the stack discarded.
- Arms: `nativeharmony`, `nativecot`, `nativersp`, `nativegrammar`, `nativelow`.

**Refactored**

- The grammar admits an analysis message rather than forbidding one. Forbidding it was justified by
  a truncation failure, which is a budget problem — a much smaller warrant than the intervention.
- Only the primitives a schema references are emitted.
- Two selftest checks were testing their own formatting: one pinned an assertion to line 1, another
  matched the literal `"root ::="` and reported "more than one root rule" when it found none.
