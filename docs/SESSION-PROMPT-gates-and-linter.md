# Session prompt — the plan linter, the ungated half, and one real defect

> Written 2026-08-12 from two field reports on real work. Everything below traces to a specific
> observed failure; nothing here is speculative. Ordered by leverage, which is not the order the
> items were reported in.

## The standing fact that decides the order

Across three reported sessions — roughly a dozen rounds — **one failure was a genuine model
defect.** Everything else was infrastructure, the harness, or the reviewer's own criteria. The
model does the work correctly whenever it runs to completion.

So effort spent making the model better is misdirected. Effort spent on **criteria** is where the
returns are, and that is what most of this is.

---

## 1. The plan linter — `handoff prepare <slug>` (highest leverage)

Everything learned about what makes a plan survive contact with the implementer is currently prose
in `integrations/procedure.md`. Prose drifts and is skipped. It is a checklist, and a checklist is
a tool.

Build `tools/plan-lint`, exposed as `handoff prepare <slug>`. It reads a plan and reports what will
bite. Each check below comes from a round it actually cost.

| Check | The failure it comes from |
| --- | --- |
| A file-count criterion using `git status --porcelain` **without** `--untracked-files=all` | `porcelain` collapses an untracked DIRECTORY to one line. A plan asserting `-eq 2` passed with five files inside a new directory. New-directory work is common and the scope guard silently stops guarding |
| A `## States to handle` section whose states have no matching criterion | Four viewport/theme states were named and none gated. 6/6 read as full coverage over a page with two contrast failures and an unscrollable overflow |
| A criterion greping output that is likely coloured (`artisan`, `pest`, `phpunit`, `npm`, `cargo`) with no `--colors=never`/`--color=no` | Cost a round. `NO_COLOR` is a convention Collision ignores |
| A whitespace assertion that is one-sided, or an upper bound rather than an exact count | A criterion counted ADDED blank lines; the damage was a REMOVED one |
| No `## Out of scope`, or no file-count assertion at all | Already warned by `check-plan`; fold it in rather than having two tools to run |
| A worked example symmetric in what it tests | Two wrong proration implementations passed every criterion: three identical lines cannot catch an ordering bug, one leftover cent cannot catch a mis-distribution |
| A plan that both creates files in a new directory **and** asserts a file count | The two interact; see the first row |

**Do not** make it refuse plans. `check-plan` already decides validity; this one advises. A linter
that blocks gets bypassed.

Mutation-test every check: a plan that trips it must fail, a plan that does not must pass.
`tools/plan-lint-selftest`, registered in `tools/selftest-all`.

---

## 2. States named in a plan must become criteria, or be declared unverifiable

The reviewer's own words, and the sharper half of item 1:

> I'd rather the skill forced that admission than let a 6/6 read as coverage.

Two parts:

- **`tools/plan-lint`** flags any state under `## States to handle` with no criterion (above).
- **`tools/roundup`** must print the declared-unverifiable states in the report, so a round-up
  never implies coverage the gates did not provide. A plan should be able to say
  `- [unverifiable] dark theme contrast` and have that surface at the end.

The principle already in the skill — *anything you are tempted to bold needs a command instead* —
extends to the states section, and currently does not.

---

## 3. A contrast gate, because contrast is arithmetic

The strongest item in the report, and the one the skill currently gets wrong by omission:

> Contrast ratios are arithmetic — a small script parsing declared colour pairs would have caught
> defect 1 mechanically. That's the skill's own "prefer counting to pattern-matching" principle
> applied to something it currently treats as unverifiable.

Build `tools/css-contrast <file.html|css> [--min 4.5]`. Parse declared colour pairs — including
inside `@media (prefers-color-scheme: dark)` — compute WCAG contrast, and exit non-zero below the
threshold. Then a plan can carry:

```bash
tools/css-contrast resources/views/landing.blade.php --min 4.5
```

The observed failure it must catch: a dark block overriding `body` and `.card` but not
`.wordmark .ro` (`#444444`) or link colour (`#0066cc`), giving 1.7:1 and 3.0:1 on `#1e1e1e`.

Scope it honestly. It cannot resolve cascade, inheritance or computed values, so it must report
what it checked and say what it could not — a gate that silently skips is worse than none. Start
with declared pairs in one file, which is where a self-contained landing page lives.

**Also worth a check it CAN do:** `align-items:center` with `min-height:100vh` and no
`overflow-y:auto` clips the top of an over-tall card unscrollably. That is a lint rule, not a
contrast one, but it is the same class — a visual defect reachable by parsing.

---

## 4. A real defect: the report turn is still losing reports on `native`

> `report turn 1: no JSON object in 4346 chars (finish_reason=stop)` — two of my recent rounds
> have lost it.

The skill says `native` recovers ~89% of parse faults and measured 18/18 reports overnight. Two
recent losses on real work contradicts that, and **this is the one item where the harness is
actively misleading the reader**.

4,346 characters came back with no JSON object. That is not a parse fault — the model answered at
length and the answer contained no object. Investigate:

- The full text is in the run's `provider.log` as a `content_end` text event. Read it first.
- `REPORT_ATTEMPTS = 2`, so a second ask should have followed. Confirm it did, and what it returned.
- If the model is returning prose or reasoning, the fix is in the ask, not the parser.
- `tools/report-audit <run-dir>` classifies the channel per round and is the right first command.

Do not change the extractor before reading the 4,346 characters. Two of today's fixes were wrong
first because the shape of the failure was assumed.

---

## 5. Skill text, once the tools exist

Only after the above, so the skill documents things that are true:

- **The visual half is ungated, and the current wording understates it.** It warns that a stub can
  fake a text assertion. The observed failure was the opposite: substantial output where every
  aesthetic and accessibility property — contrast, overflow, heading structure — sat outside what
  any command could reach. Say that plainly, and point at `tools/css-contrast`.
- **A view plan should require a heading element.** `<h1>`/`<main>` was a spec gap, not a model
  error, and it is the kind of gap a checklist prevents.
- Name the untracked-directory collapse next to the file-count criterion.

---

## Ground rules

- `tools/selftest-all` before any commit. Every new check mutation-tested — a guard that cannot
  fail is worse than none, and this repository has shipped four.
- Commit on `main`, push freely. Never force-push.
- Additive work only while the harness is in use: `roundup`, `plan-lint` and `css-contrast` are
  read-only and safe. Item 4 touches the hot path — smoke-test it live before landing.
- Before reporting any number, ask what would make it wrong and check that. Seven confident numbers
  in one day turned out to be instruments rather than the model.

## What is already done, so it is not redone

Landed and verified today: the scope gate no longer charges pre-existing untracked files; the
`files` column counts the tree rather than tool names; acceptance commands run with colour
disabled; `handoff check --dry-run` pre-flights criteria and reveals what a silent pipeline
matched; `handoff roundup` files the end-of-session report centrally; `tools/setup` installs
everything; `/local-implement` was renamed `/local-implementer` and was driving Cline rather than
the native loop.
