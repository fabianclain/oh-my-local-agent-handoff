# Session prompt — the invoicing ladder: can Codex hold the planner seat?

> Transport document. Written by the Claude planner session on 2026-08-10, to be read by the
> harness-development session. Everything below is traceable to a file path, a commit, or a
> command that was actually run. Where something was not measured, it says so.

---

## 1. What this actually is

A 27-step greenfield Laravel module (invoicing) is being used as the **workload for a harness
experiment**. The module is real and wanted, but the question being asked is about the harness:

> **Can the operator seat (Codex) hold the planner seat for a long sequence — authoring plans,
> writing the reviewer tests, and driving the local model — with Claude escalated to only when
> a decision is genuinely load-bearing?**

Today the three seats are:

| Seat | Runs as | Job |
| --- | --- | --- |
| **Planner** | Claude Code, `/local-implement` | Turn a request into a mechanically checkable specification |
| **Operator** | Codex, `/local-drive` | Get plans through the gates; repair, narrow, commit, report |
| **Implementer** | gpt-oss-20b, `HANDOFF_PROVIDER=local` | Write the code |

`docs/DRIVING.md` is explicit that these are separate because *a model that does two of them is
checking itself*. `/local-drive`'s own skill file says, in its second paragraph, **"You are not the
planner"**, and gives a table of allowed narrowing vs forbidden redesign.

**The proposed change breaks that boundary on purpose, and the experiment is whether it survives.**
Codex would author plans 4–27 *and* the reviewer tests that judge them. The implementer is still a
different model, so author≠judge still holds — but planner≠operator no longer does.

### This is not hypothetical — the harness already permits half of it and forbids the other half

`tools/escalate` (untracked, new) enforces three rules rather than trusting them. Read its header;
it is the most relevant thing in the repo to this question. Two of them decide the experiment:

> 1. *The planner may not be the implementer.*
> 2. *The planner may write the new plan and its notes file. **Nothing else.** If it touches source,
>    or the harness that judges the work, the ladder stops and says so — a model editing its own
>    grader is self-approval by another route, and no automation here gets to do it.*

Rule 1 says nothing about planner-vs-operator. So `handoff auto <slug> --planners codex` against a
local implementer **is already exactly the configuration being proposed**, and it is legal today.

Rule 2 is where it breaks. **Reviewer tests are source.** A planner that writes the judge is doing
precisely what rule 2 exists to prevent — except that here it is not editing *its own* grader, it
is writing the grader for a *different* model's work. The rule cannot currently tell those apart.

So the sharp question for this session is not "should Codex plan?" but:

> **Is rule 2 about authorship or about self-interest?** If it is about self-interest, a planner
> writing tests for an implementer it is not is fine, and rule 2 needs to say so. If it is about
> authorship, then Codex cannot write the judges, and steps 4–27 need their reviewer tests from
> Claude even when Codex writes everything else — which is a much narrower and cheaper handover
> than it sounds, because the tests are the small part.

Everything else below is in service of answering that.

---

## 2. Current state — exact, checkable

**Product repo:** `/home/fabbs/dev/monolith`, branch `invoicing`, commit `0a131df`
**Harness checkout:** `/home/fabbs/dev/monolith/agent-handoff` (its own git repo, at `5983c58`)
**Plans dir:** `.claude/plans/` — *not* `.handoff/plans/`; `.handoff/config.sh` overrides it
**`handoff` is not on PATH:** `export PATH="$PWD/agent-handoff/bin:$PATH"`

### Committed and green-gated

| Path | What |
| --- | --- |
| `.claude/plans/invoicing-1-money.md` | 9 criteria / 9 commands — `check-plan` ok, no advisories |
| `.claude/plans/invoicing-2-vat-rates.md` | 9 / 9 — ok |
| `.claude/plans/invoicing-3-totals.md` | 12 / 12 — ok |
| `tests/Unit/Invoicing/MoneyTest.php` | reviewer-authored judge, 3 files listed read-only |
| `tests/Unit/Invoicing/VatRatesTest.php` | " |
| `tests/Unit/Invoicing/DocumentTotalsCalculatorTest.php` | " |

Committed with `--no-verify` (a Husky pre-commit hook runs the full suite; these tests fail by
design until their plan lands). Working tree is clean: `git status --porcelain -uall` excluding
`.handoff` and `.omc` returns **0**.

### Verified by execution, not by reading

A throwaway reference implementation of steps 1–3 was written, **all 40 assertions passed**, all
30 acceptance commands were run exactly as the harness will run them (all exit 0 except the three
file-count gates, which correctly failed with all four files present at once), and the
implementation was then deleted. So: the plans are known-satisfiable and the hand-computed numbers
are known-correct. **This is the one thing a planner can do that removes an entire class of wasted
rounds, and it is not currently in the `/local-implement` procedure.** See §6.

---

## 3. The workload — all 27 steps

Ordered so pure logic comes first and alone. Steps 1–3 are fully specified; 4 is the last
purely-computational step; 5+ need the database.

### Pure logic — no DB, no models, no views

| # | Slug | Outline |
|---|---|---|
| 1 | `invoicing-1-money` | ✅ Integer bani arithmetic — `divRound`/`mulDiv`/`format`, half away from zero |
| 2 | `invoicing-2-vat-rates` | ✅ `config/invoicing.php` rate table + `VatRates` resolver; no percentage literal in code |
| 3 | `invoicing-3-totals` | ✅ `DocumentTotalsCalculator` — per-line net/VAT/total, document totals, VAT breakdown |
| 4 | `invoicing-4-status` | `InvoiceStatus` enum + pure `derive()` over scalars: cancelled › draft › paid › overdue › partially paid › issued |

### Persistence

| # | Slug | Outline |
|---|---|---|
| 5 | `invoicing-5-schema` | Seven migrations + register `database/migrations/invoicing` in `loadDomainMigrations()` |
| 6 | `invoicing-6-models` | Eloquent models, `HasOwner`, relationships, factories |
| 7 | `invoicing-7-numbering` | `NumberAllocator` — atomic per-series increment inside the caller's transaction, unique index as backstop |

### Document lifecycle

| # | Slug | Outline |
|---|---|---|
| 8 | `invoicing-8-snapshots` | Freeze issuer + client details onto the document as JSON at issue time |
| 9 | `invoicing-9-issue` | `IssueDocumentAction` — allocate, snapshot, persist totals, stamp `issued_at`, one transaction |
| 10 | `invoicing-10-immutability` | Model guard: an issued document rejects update, renumber and delete |
| 11 | `invoicing-11-payments` | Payment recording + `settled`/`outstanding` aggregation feeding step 4's resolver |
| 12 | `invoicing-12-proforma` | Proforma type + conversion to invoice; the proforma survives unchanged |
| 13 | `invoicing-13-storno` | Credit note referencing the original, never modifying it; nets into outstanding |
| 14 | `invoicing-14-receipt` | Chitanță against a cash payment, own series |
| 15 | `invoicing-15-exchange-rate` | Non-RON documents capture the rate at issue; RON stays null |

### Reporting

| # | Slug | Outline |
|---|---|---|
| 16 | `invoicing-16-reports` | Outstanding, overdue, revenue by month, VAT collected per period |
| 17 | `invoicing-17-csv-export` | Accountant CSV export |

### Surface

| # | Slug | Outline |
|---|---|---|
| 18 | `invoicing-18-routes` | `routes/invoicing.php` + `require` in `web.php` + nav entry |
| 19 | `invoicing-19-clients-page` | Clients CRUD Livewire page |
| 20 | `invoicing-20-catalogue-page` | Products/services CRUD Livewire page |
| 21 | `invoicing-21-documents-list` | Documents list with status/type/client filters |
| 22 | `invoicing-22-document-editor` | Draft editor with line items, live totals |
| 23 | `invoicing-23-document-show` | Issued document detail, VAT breakdown, payments |

### Delivery

| # | Slug | Outline |
|---|---|---|
| 24 | `invoicing-24-renderer-interface` | `InvoiceRenderer` interface + Blade print template, no PDF library |
| 25 | `invoicing-25-pdf-impl` | Concrete PDF renderer — **blocked on a user decision** |
| 26 | `invoicing-26-email` | Mailable with the document attached |
| 27 | `invoicing-27-reports-page` | Reporting Livewire page |

---

## 4. Decisions already pinned — Codex must NOT re-decide these

These are the ones where a plausible wrong answer is indistinguishable from a right one. They are
already encoded in committed tests, so re-deciding them shows up as a failing gate rather than as
a silent divergence — but a planner that does not know they are settled will burn rounds fighting
them.

| Decision | Settled as | Enforced by |
| --- | --- | --- |
| Money representation | integer minor units (bani); no float, no `decimal:2` | `MoneyTest` bans `float`/`round(`; asserts exactness past 2^53 |
| Rounding mode | **half away from zero**, per line, then summed | 4 cases where banker's differs; 1293-not-1292; 652-not-651 |
| Quantity unit | integer thousandths (`1500` = 1.5) | `DocumentTotalsCalculatorTest` |
| VAT percentage unit | integer hundredths of a percent (`2100` = 21%) | `VatRatesTest` |
| VAT rates | RO post-Aug-2025: standard 2100, reduced 1100, zero 0 — **in config, never in code** | test swaps the whole rate table at runtime |
| Issuer model | a table, several issuers, numbering scoped per issuer | user decision |
| Zero rate | a real, selectable rate — not falsy, not absent | explicit test |
| Result shape | exact key set for `lines` / `vat_breakdown` / totals | `returns the exact shape` test |

**Deliberately left open, and they are user calls, not Codex calls:**

1. **PDF library** — nothing installed; `CLAUDE.md` forbids adding dependencies without approval.
   Step 24 (interface + Blade template) is unblocked; step 25 is not.
2. **Does a credit note change an invoice's status?** Current assumption: **no** — status derives
   from payments alone, and storno nets into *outstanding* only. Consequence: a fully-stornoed
   invoice reads `overdue` forever. This is the weakest call in the sequence and is cheap to change
   while step 4 is unwritten.

---

## 5. What the run is supposed to teach

Three measurements, in descending order of value to the harness:

**M1 — Does the ladder work on greenfield when the logic is isolated?**
The calibration datum is `docs/field-report-2026-08-10.md`: the same local model went **0 accepted
in 7 rounds** on greenfield Laravel (service + Livewire view + aggregate SQL), best round 9/12,
against a documented 78%/93% on a six-file refactor. The reviewer then wrote the service by hand
and it passed 8/8 first run. Steps 1–4 here are the deliberate mitigation: pure functions, dictated
signatures, hand-computed judges, one file each. **If step 1 or 2 needs two escalations, the
mitigation failed and the finding is bigger than the module.**

**M2 — Can Codex author a plan that passes `check-plan` *and* carries a judge it computed itself?**
`check-plan` acceptance is cheap and says nothing about quality. The real test is whether Codex
produces reviewer tests with correct hand-computed numbers for steps 4, 7, 11, 13 (status ladder,
numbering concurrency, payment aggregation, storno netting) — all stateful or numeric, all in the
"plausible wrong answer" class.

**M3 — Where does the plan→gate loop leak?**
Every plan Codex writes that the implementer fails for a reason the plan never mentioned is a
harness finding, not a model finding. That is the feedback the improvement session wants.

---

## 6. Harness gaps found while specifying steps 1–3

These were hit doing the work, not theorised. Each is a concrete candidate change.

### 6.1 The journal is new, empty, and this run is its first dataset

Corrected after checking the tree — the first draft of this document got it wrong, and the truth is
more useful.

```
$ handoff stats            →  "no runs recorded yet"
$ handoff log rankingsv2   →  "no runs recorded yet"
$ ls .handoff/runs | wc -l →  23
$ ls -la tools/journal     →  exists, untracked, written 2026-08-10 20:16
```

`tools/journal` is **not missing — it is hours old and unreleased**, part of the uncommitted work
now sitting in this repo. It is empty because no run has executed since it landed. It reports "no
runs recorded yet" correctly; that is the tool working, not failing.

Its own header explains why it exists, and it is the same problem this document is about:

> *Seven rounds of one real feature left three surviving logs. `.handoff/runs/<slug>` is reused, so
> each round overwrote the one before it, and by the time anyone wrote the round up the evidence for
> four of them was gone. The single most useful diagnostic in this project — comparing a round with
> the round before it — was impossible on the runs that most needed it.*

So the 23 directories on disk are **last-round survivors only**, not 23 rounds. The rankingsv2 0/7
is not recoverable at round granularity; the design that would have captured it was written after
it happened.

**What this means for the run: invoicing steps 1–27 are the journal's first real exercise, and the
first round-level dataset this project will ever have.** That is worth more than the module.

The tool is reachable and working — `handoff log` executed and answered, it simply has nothing to
report. The actual risk is that `tools/journal` is **untracked**: a `git clean` or a stash in this
repo deletes it mid-sequence, and the run silently reverts to the overwrite-in-place behaviour that
lost the rankingsv2 evidence. Commit it before step 1, or accept that risk knowingly.

Worth preserving as a fixture: `.handoff/runs/rankingsv2/result.json` reads
`{"status": "complete", "summary": "No changes performed.", "files_changed": []}` — the
false-report pattern, intact, and a ready-made regression case for anything that reads reports.

### 6.2 `check-plan` cannot see the two file-count traps that actually bite

It advises *"nothing asserts how many files changed"* if no `git status|diff` appears. It does not
check whether the command is **correct**, and both natural spellings are wrong:

- **Untracked directories collapse.** `git status --porcelain` prints `?? app/Domains/Invoicing/`
  as **one line** regardless of how many files are inside. A brand-new domain folder is therefore
  completely unconstrained by the criterion that exists to constrain it. Needs `-uall`.
- **Operational churn inflates the count.** `.omc/state/**` is tracked and rewritten constantly —
  it added 6 phantom files here. Needs `':(exclude).omc'`.

The spelling that works, and that all three plans use:

```bash
test "$(git status --porcelain -uall -- . ':(exclude).handoff' ':(exclude).omc' | wc -l)" -eq N
```

**Proposed:** `check-plan` should advise when a `git status` criterion lacks `-uall`. This is a
one-line grep and it closes a gap that silently voids the scope gate on exactly the greenfield
shape the harness is worst at.

### 6.3 A bare `--filter` scans the whole suite — 3 minutes vs 0.95 seconds

```
php artisan test --compact --filter="rounds halves away from zero"          → >180s (timed out)
php artisan test --compact tests/Unit/.../MoneyTest.php --filter="…"        → 0.95s
```

A plan with 9–12 per-criterion filter commands is the natural shape, and unscoped it costs ~30
minutes per verification pass — enough to look like a hang. **Proposed:** a `check-plan` advisory
when a test command carries `--filter` without a path argument. Project-specific to Laravel/Pest,
so possibly better as a `PROJECT_RULES` line in `.handoff/config.sh`.

### 6.4 Verified good: a filter matching nothing exits 1

Checked explicitly, because a false pass here would void every per-criterion gate:

```
php artisan test --compact tests/…/MoneyTest.php --filter="this does not exist"
→ "No tests found."  exit=1
```

So a typo'd or drifted filter fails closed. **No change needed — record it so nobody re-derives it.**

### 6.5 Reviewer tests + a pre-commit hook that runs the suite

`.husky/pre-commit` runs `php artisan test --compact`. Committing a judge before its implementation
therefore *requires* `--no-verify`, and so does every implementation commit until the last test in
the batch goes green. The `/local-implement` skill says "commit the tests before the run" without
mentioning this, and `/local-drive` step 6 says `git add -A && git commit` with no `--no-verify`.
**An operator following the skill literally will be blocked and will not know why.** Either the
skill should name it, or the guidance should be to commit judges one step at a time.

### 6.6 The missing procedure step: prove the plan is satisfiable before spending a round

Writing a throwaway reference implementation, running every acceptance command, then deleting it,
cost ~10 minutes here and would have caught: a wrong hand-computed number, an unsatisfiable
assertion, a filter that matches nothing, a Pint disagreement, and both file-count traps above.

Against a documented 0/7 on greenfield, a planner-side dry run is cheap. **Proposed:** add it to
`/local-implement` as an explicit step, or as `handoff dryrun <slug>` that runs a plan's
verification block and reports which commands can pass at all.

---

## 7. The escalation contract

Most of this is already mechanised — `tools/escalate` runs rung 1 (local implements), rung 2 (local
repairs against the exact failing commands), rung 3 (a hosted planner writes a new, narrower plan
and never writes code), then loops, stopping the moment the gates accept or a round scores worse
than the one before it. `handoff auto <slug> --planners codex --attempts 2 --escalations 1` is the
whole of it.

What follows is only the part the ladder cannot decide: which failures are *questions* rather than
retries. Below, "escalates to Claude" means stop the ladder and report — not another rung.

**Codex decides alone:** step decomposition and slug naming; acceptance-command spelling; which
files a step touches; narrowing a failing step; reviewer-test *structure*; commit messages;
whether a round was an adapter fault (writes=0) or a model failure.

**Codex escalates to Claude (planner):**
- Any reviewer-test number it cannot verify by execution.
- A plan that is *wrong* rather than unclear — wrong approach, missing dependency, impossible
  requirement.
- Two escalations on the same step (that is evidence about the task's shape).
- Any of §4's pinned decisions appearing to be wrong.
- A step whose criteria it cannot make stub-proof — especially views, where a three-line template
  satisfied 4 of 10 criteria in the field report.

**Codex escalates to the user:** the PDF library (§4.1); the storno/status semantics (§4.2); any
new dependency; anything touching production data or the phone/ADB services.

**Never:** loosen a criterion until the code passes; edit a file listed under
`## Files to read, not modify`; commit a rejected round; push, amend or rebase.

---

## 8. How to start the run

```bash
cd /home/fabbs/dev/monolith
git checkout invoicing                       # already at 0a131df, tree clean
export PATH="$PWD/agent-handoff/bin:$PATH"
handoff doctor                               # settles environment-vs-model before anything runs

codex --sandbox workspace-write -c sandbox_workspace_write.network_access=true
/local-drive invoicing-1-money invoicing-2-vat-rates invoicing-3-totals
```

The network flag is not optional — the implementer is reached over HTTP on `127.0.0.1`, and
without it `handoff doctor` reports "nothing answering" about a server that is running fine.

Steps 1 and 2 need `git commit --no-verify` (§6.5). Step 3's commit should pass the hook clean; if
it does not, that is a finding.

**Then stop and report before authoring step 4.** Steps 1–3 are the calibration. If they land at
or near first attempt, the mitigation in §5/M1 works and Codex can take the planner seat for 4–27.
If step 1 or 2 needs two escalations, the finding is that the planner seat does not transfer, and
the right move is for Claude to hand-write the money/VAT/status logic and give the local model the
mechanical remainder — which is exactly what happened in the field report, and what made the one
successful round successful.

---

## 9. Open questions for the harness session

Ordered by how much they change, not by effort.

1. **Is `escalate` rule 2 about authorship or about self-interest?** (§1) It forbids a planner from
   touching anything but the plan file, on the grounds that a model editing its own grader is
   self-approval. But a planner writing the judge for a *different* model's work is not that, and
   the rule cannot currently distinguish them. This decides whether Codex can author reviewer tests
   for steps 4–27 or whether those stay with Claude. **Everything else in this document is
   downstream of it.**

2. **Is planner≠operator load-bearing, or was it only ever author≠judge?** `handoff auto --planners
   codex` already makes Codex both planner and operator, so the harness permits this today while
   `/local-drive`'s skill text forbids it in prose. One of the two should change. This run is the
   evidence: if Codex starts defending its own plans against the gates, the skill's table becomes a
   hard rule; if it does not, the seat model simplifies by one seat.

3. **Should `check-plan` gain the `-uall` and `--filter`-without-path advisories?** (§6.2, §6.3)
   Both are one-line greps. The first closes a gap that *voids* a gate rather than weakening it —
   on greenfield specifically, which is the shape the harness is already worst at.

4. **Does "prove the plan is satisfiable" belong in the procedure or in the tool?** (§6.6) It cost
   ~10 minutes here and pre-empted five distinct failure modes. `escalate --dry-run` exists but
   answers a different question (what the ladder would do, not whether the plan can be passed).

5. **Should reviewer tests be committed per-step rather than per-batch**, given a pre-commit hook
   that runs the suite? (§6.5) Neither skill mentions `--no-verify`, and an operator following
   `/local-drive` step 6 literally will be blocked with no explanation.

6. **Is the 23-run history worth backfilling into the journal?** (§6.1) Probably not at round
   granularity — the data was overwritten before the journal existed — but the *last* round of each
   is still 23 real data points about final outcomes.
