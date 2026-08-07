---
description: Have Codex attack a design decision, then synthesize both positions
argument-hint: <the decision or design to stress-test>
allowed-tools: Bash(consult:*), Read, Write, Edit, Grep, Glob
---

Stress-test a design decision by making Codex argue against it. Two models, opposed on
purpose. Nothing is implemented in this command.

Topic: `$ARGUMENTS`

## 1. Commit to a position first

Investigate the codebase and decide what **you** actually think. Do this before involving
Codex — a position formed after hearing the objections is not an independent one, and the
whole value here is that the two views are formed separately.

Write it to `.handoff/think/<slug>/position.md`:

- The decision, stated plainly enough to be wrong.
- The concrete alternatives you considered and why you rejected each.
- The assumptions it rests on — this is what Codex will go after hardest, so list them
  honestly rather than burying them.
- The relevant files, so Codex reads the real code and not a description of it.

Show the user your position before sending it. If they correct you, revise it first — sending
a position you have already abandoned wastes the round.

## 2. Send it

```bash
consult think <slug>
```

Read-only sandbox, so nothing can be modified. Run with `run_in_background: true`.

## 3. Read the verdict honestly

`.handoff/think/<slug>/verdict.json` gives `verdict`, `strongest_objection`,
`objections[]` (each with `severity` and `confidence`), `missed_considerations`,
`what_it_gets_right`, `recommended_change`.

Go through the objections one at a time and sort them into three piles:

- **Correct** — it found a real problem. Say so plainly. Do not defend the original design
  because it was yours.
- **Wrong** — verify why in the actual code before dismissing it. Cite the file and line that
  refutes it. "I don't think that's right" is not a refutation.
- **Depends on something Codex could not know** — a product constraint, a deployment fact, a
  decision the user already made. These are not really objections, but they often reveal that
  the position file left out something load-bearing.

Weight by `confidence` as well as `severity`: a low-confidence fatal objection is usually
worth checking, and a high-confidence minor one is usually worth just fixing.

## 4. Optional second round

Only if there is genuine unresolved disagreement worth resolving:

1. Write your answer to `.handoff/think/<slug>/rebuttal.md` — concede what's correct,
   and for what you're holding, give the evidence.
2. `consult think <slug> --again`

**Stop after two rounds.** If you still disagree, the disagreement is about something
neither model can settle — a value judgement or a fact only the user has. Escalate it to them
with both positions stated fairly, rather than going another round.

## 5. Synthesize

Give the user a verdict of your own, not a transcript:

- What you now believe, and what changed your mind.
- Where Codex was wrong, and the evidence.
- What remains genuinely open, framed as a decision for them.

If the outcome is a revised design worth building, offer to turn it into a plan for
`/codex-do`. Do not start implementing from inside this command.
