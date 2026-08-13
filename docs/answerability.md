# When a check cannot answer

Every gate in this harness exits one of three ways:

| exit | meaning |
| --- | --- |
| `0` | checked, and it holds |
| `1` | checked, and it does not hold |
| `2` | **could not check** — and the reason is printed |

The third is the one this page is about, because it is the one that has been got wrong five times
in five different tools, and each time the bug looked like a passing check.

**Two is not a softer one.** "This fails" and "I could not tell" are different facts with different
remedies. A failing gate sends you to the code. An unanswerable gate sends you to the *input* — a
file that did not build, a stylesheet with no document, a parse error upstream. Collapsing them
loses the remedy, and collapsing either into `0` loses the finding entirely.

---

## The failure this prevents

> Absence of evidence, reported as evidence of absence.

Five instances, all real, all found by accident rather than by looking:

| tool | what it did | why it was worst there |
| --- | --- | --- |
| `search` | `grep` exits 2 on an invalid pattern and writes nothing to stdout; the tool returned `stdout or "no matches"` | a search that never ran came back as a confident absence, and the model believed it for ten turns |
| `read_files` | truncated a file past the output cap with a note naming the loss and no remedy | three rounds re-issued the identical call and wrote nothing |
| `docblock-anchor` | returned `pass` over a file that does not parse, and over a file with no docblocks | blind exactly when the syntax gate is red — which is when a displaced docblock is *most* likely |
| `css-contrast` | printed `0 colour pair(s) resolved` and exited `0` | an empty stylesheet and a build that emitted no markup were both green |
| `verify-round` | ran `pint`, `phpstan`, `pest` only if present | their absence was indistinguishable from their passing |

Only the last was designed correctly, and it is why `skipped` is a first-class status in the
evidence bundle rather than a gate being quietly omitted.

The pattern worth internalising: **four of these five printed the right thing in prose and the
wrong thing in their exit code.** `css-contrast` said "a bare stylesheet has no elements, so no
pair can be resolved" and then exited 0 underneath it. The tool knew. Nothing downstream could
find out, because prose is not a mechanism.

---

## Writing a gate

Three rules.

**1. Decide what you cannot answer, before deciding what you check.** The unanswerable cases are
usually: the input is missing, the input is empty, the input does not parse, or the thing you need
in order to compare — a base ref, a document, a tool on `PATH` — is not there.

**2. Say why, in words that name a remedy.** `2` on its own is a shrug. These are the messages the
tools actually print:

```
UNKNOWN  page.css — no colour pair could be resolved, so nothing was checked
         a bare stylesheet has no elements — point this at the HTML file that uses it
         This is not a pass.

UNKNOWN  Show.php — the file does not parse, so the docblocks cannot be checked
         Every declaration this gate can see may be wrong. Fix the parse error,
         then run it again. This is not a pass and it is not a finding.
```

**3. A definite finding outranks an unknown.** Over several files, exit `1` if anything actually
failed, `2` only if nothing failed and something could not be checked. Both reject, but only one
tells you where to go, and burying it under a `2` wastes the round.

```python
found, unknown = False, False
...
return 1 if found else (2 if unknown else 0)
```

---

## How it is enforced

`tools/answerability-selftest` feeds every gate an input it genuinely cannot answer and asserts
both halves of the contract: exit `2`, **and** a reason a person can act on. Covering a new gate
costs one line in its `UNANSWERABLE` list.

It also runs a control group. A gate that returned `2` for everything would pass every case above
and be useless, so each tool must still answer a question it *can* answer. That group is not
decoration — it is what stops the fix for this bug from becoming a worse one.

Every guard is mutation-tested: revert the fix, confirm the case fails. A check that has never been
watched failing is not known to work.

```bash
tools/answerability-selftest      # the contract
tools/selftest-all                # everything, this included
```

---

## Where it does *not* apply

**Acceptance commands in a plan.** A plan's `## Verification` block is ordinary shell: non-zero is
a rejection, and `2` rejects the same as `1`. That is correct — never accept on an unknown — but
the distinction is not preserved there. If you want it visible, gate on the tool directly and read
its output in the evidence bundle.

**Analysis tools.** `turn-economy`, `report-audit`, `peg-audit` and friends report *about* runs and
do not vote on them. They still must not invent numbers over missing data — `bench/summary` sets
`usage_unattributable` rather than printing a plausible figure — but they have no verdict to get
wrong.

**`selftest-all` itself** already uses the same three codes one level up: a suite exiting `2` is
reported `SKIP`, not `pass`, because a suite that could not run has not agreed with you.
