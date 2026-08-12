# Field report — 2026-08-10

One real feature, built with `/local-implementer` against `gpt-oss-20b` on a 16 GB card, over seven
model rounds. Nothing here is hypothetical: every claim below is traceable to an evidence bundle
under `.handoff/runs/`, a kernel log line, or a test run.

The task was a real feature in a private Laravel application: a new read-only dashboard
page, built as a service plus a Livewire view.

**Headline:** 8 model rounds, **1 substantively successful** — and that one was the narrowest
plan of the set, a single file with a single defect to fix, produced by re-specifying rather than
resuming. The other seven failed. The best of them reached 9 of 12 gates and then regressed to
3 of 14 by corrupting the file it had nearly finished. The service was ultimately written by the
reviewer and passed 8/8 tests first run; the view was written by the model across rounds 7 and 8
and is committed and green.

That 0/7 is against a documented 78% first-attempt / 93% within-three. Those figures come from a
six-file *refactor*; this was greenfield Laravel with aggregate SQL. The divergence is the single
most useful calibration datum in this report.

---

## 1. What was delivered

### Product work (a feature branch, in its own worktree)

| Commit | What |
| --- | --- |
| `760bf76` | Reviewer-authored `RankingDashboardTest` — the spec, written before any implementation |
| `29cfbe5` | Added assertions for the row field set the view consumes |
| `a3aed0c` | `RankingDashboard` service — 8/8 tests, 12/12 acceptance commands |
| `9eae28d` | Reviewer-authored `RankingsV2PageTest` — the spec for the view step |

Uncommitted in that worktree: the view and its route, from round 7, pending the follow-up round.

**The analysis that motivated the feature**, which is worth recording because it was the whole
point: `/search-log/rankings` renders almost entirely empty against real data, and the data is not
missing. All 45 tracked keywords are stored with `engine = 'google'`; `RankingReport::rankingMatrix()`
joins captures on `query_hash` **and** `engine`; only 3 keywords have a Google capture while 43
have a DuckDuckGo one. Real positions — `ssmatic.ro` at #1 on 30 keywords — were invisible. The v2
service joins on `query_hash` alone and reports the engine mismatch as its own fact.

### Infrastructure written during the session

| Path | Why it exists |
| --- | --- |
| `scripts/ops/backup-sqlite.sh` + systemd timer | The dev database corrupted with no backup. Online `.backup`, integrity-checked before keeping, 14 rotated, every 6h |
| `scripts/ops/resource-watch.sh` + service | A silent OOM froze the desktop and killed a run. Warns on *approach*, can stop the model server before the kernel picks a victim |
| a user systemd unit for llama-server | llama-server at 32k context, `MemoryMax=12G`, outside the terminal scope |

All four `scripts/ops/*` files are untracked in the main tree, awaiting a decision to commit.

---

## 2. Two incidents

### 2.1 Database corruption

`database/database.sqlite` became unreadable — every table including `sqlite_master`; header
intact; `.dump` recovered 243 bytes. Cause never established. Ruled out: the test suite, because
`phpunit.xml` sets `DB_DATABASE=:memory:`. Candidates that could not be separated: a scratch script
one round wrote which booted the real application against the real database, and six systemd
services writing to the same file continuously.

**Recovery worked because the snapshots are the durable record.** The gzipped SERP HTML under
`storage/app/private/search-log/snapshots/` identifies itself — query in `<title>`, engine in the
title suffix, `?q=` in the body for the DuckDuckGo HTML endpoint, `searched_at` from file mtime.
Reconstructing the snapshot rows and running `search-log:parse` restored **87 of 95 queries and
804 of 829 results**. The ~8 lost were extension client-entries that never had stored HTML.

**Lesson for the harness:** the implementer runs arbitrary commands against a live tree with
approval disabled. Nothing in the harness isolates that. The skill now says to use a worktree; it
is worth saying explicitly that a copied `.env` with an absolute `DB_DATABASE` points the worktree
straight back at the live database and buys nothing.

### 2.2 OOM, load 128, frozen desktop

```
Out of memory: Killed process 1329360 (llama-server)  anon-rss:8151060kB
task_memcg=/…/snap.zellij.zellij-…scope
snap.zellij…scope: Failed with result 'oom-kill'
```

llama-server was running **inside the zellij scope**, so the kill failed the whole scope and took
the terminal — and the run inside it — with it.

The load figure was swap thrashing, not CPU: swap hit 7.0 of 8.0 GB, and processes blocked on
page-in count toward load average.

**Root cause was the context size.** Measured before and after:

| | 64k context | 32k context |
| --- | --- | --- |
| llama-server host RSS | 8.9 GB | **0.80 GB** |
| GPU used | 2.5 GB (model absent) | **13.8 GB** (model resident) |

`providers/local.sh` documents 64k as "the largest window that keeps this model fully GPU-resident
on 16 GB". **That is wrong on a machine whose GPU also drives a desktop** — ~2.5 GB was already
held, leaving ~13.8 GB, and an 11.3 GB model plus a 64k q8_0 KV cache does not fit. It silently
fell back to host RAM.

Two suggestions: correct that comment to say "16 GB *free*", and have `llamacpp-serve start` read
back llama-server's own layer-offload report and warn when the model is not fully resident. A
partial offload is currently invisible until it takes the machine down.

---

## 3. The seven rounds

| # | Plan | Files | Gates | What broke |
| --- | --- | --- | ---: | --- |
| 1 | `rankingsv2` | 6 | 4/10 | Placeholder view; `Route::view`; invented 1-day + 30-day thresholds; scratch file |
| 2 | `rankingsv2` | 7 | 5/17 | **File truncated** (parse error L26); route below catch-all; wrong column name |
| 3 | `-1-service` | 1 | 4/11 | `?->` on an array; coverage conditioned on state; two aggregates redefined |
| 4 | `-1-service` resume | 1 | **9/12** | Signed `diffInDays`; rows unsorted; 3 fields missing, 1 misnamed |
| 5 | `-1-service` resume | 1 | 3/14 | **File truncated** (parse error L191); scratch file |
| 6 | `-2-view` | 2 | 5/15 | **Zero writes** — tool-call format errors; empty diff; fabricated report |
| 7 | `-2-view` | 2 | 7/15 | Wrote both files; template correct; PHP block malformed → Livewire 500 |
| 8 | `-2a-component-block` | 1 | **9/9 acceptance** | Fixed exactly the specified block, touched nothing else |

Reviewer-written service after round 5: **8/8 tests, 12/12 acceptance**, first run.

**Round 8 is the one success, and it is the strongest evidence in this report for §9.** After
round 7 left a correct 162-line template behind a malformed PHP block, the response was *not* a
resume with feedback but a **new one-file plan describing only the remaining delta**. Every
acceptance command passed, `read-only` confirmed all three reviewer files came back untouched, and
`patch-only` confirmed it patched rather than regenerated. Contrast rounds 4→5, where resuming with
a detailed account of the failure took 9/12 to 3/14. Two data points, opposite directions,
consistent with the skill's claim that diagnosis belongs on the reviewer's side.

### Failure taxonomy

| Mode | Rounds | Note |
| --- | ---: | --- |
| File corruption / truncation | 2 of 7 | Both fatal, both on files >150 lines, both on a *later* edit of a file it had already written |
| Tool-call format errors | 2 of 7 | `peg-native format`; 3 occurrences in each step-2 round |
| Invented conditions | 3 of 7 | Thresholds and guards the plan never mentioned |
| Scratch files left behind | 2 of 7 | Despite explicit prose forbidding it in rounds 3–7 |
| Placement errors | 2 of 7 | Route below the catch-all, after two prose warnings |
| Named dependency ignored | 1 | Injected `RankingReport`, never called it, bypassing deduplication |
| Silent contract drift | 1 | Three row fields dropped, one renamed |
| Test gaming | 1 | A three-line template whose own comment said it only needed to render the asserted string |

---

## 4. What worked

**Reviewer-written tests caught every numeric error.** Rounds 3 and 4 would both have shipped
green against model-authored tests — round 4 produced `fresh: 7, stale: 0` where the truth was
`6/1`, and a model writing its own assertions would have written `7/0` and passed. This is the
highest-leverage rule in the skill and it earned its place twice over.

**Splitting produced the best round.** 9/12 on one file versus 4–5 on six. Narrow scope let each
criterion assert something specific.

**Worktree isolation held.** After it was set up, no further incidents, and it was possible to
confirm mid-run that edits were landing in the worktree and the main tree was untouched.

**Both gate bugs reported earlier in the session are fixed** and confirmed gone in rounds 6 and 7:
the `⚡` path-quoting false positive and the read-only-file false positive no longer fire.

**`tools/smoke-e2e` passes all six sections** and is a good addition.

---

## 5. Recommendations, ranked

### Adapter — highest leverage

**A1. Force whole-file writes for files under ~400 lines.** Two of seven rounds died to
mis-anchored partial edits producing a docblock running into a method body. Rewriting the file
wholesale eliminates the class entirely. This is the change I would make first.

**A2. Run the syntax check inside the loop, not only at verification.** The `syntax` gate fires at
the end, after the round is spent. Round 5 spent its whole budget building on a file that had not
parsed since its first edit. A post-write hook running `php -l` (or the project's linter) and
feeding the error straight back gives the model a chance to repair a truncation immediately.

**A3. Give it a sanctioned REPL and a disposable scratch dir.** Both litter incidents were the
model wanting to inspect a value with no legitimate way to do it, and both were scripts that
bootstrapped the whole application — which is also the most plausible route to the database
corruption. Prose telling it not to has now failed twice across five rounds where it was present.

**A4. Investigate the `peg-native format` error.** It occurred three times in each step-2 round.
In round 6 the model never recovered: 44 tool calls, all `read_files` and `search_codebase`, zero
`apply_patch` or `run_commands`, run over in 35 seconds and 1336 output tokens, empty diff. In
round 7 it recovered and wrote both files. So it is intermittent tool-call corruption the adapter
sometimes survives — and when it does not, an entire round is spent producing nothing. Worth a
repro alongside `repro-ollama-toolcall-500.py`.

### Harness

**H1. `handoff resume` exits 0 without verifying.** `do` verifies automatically; `resume` does not,
and leaves the previous round's evidence in place. A stale `REJECT` bundle sat next to `exit=0`
and was nearly reported as a pass. Either verify, or exit non-zero with "not verified".

**H2. Flag regressions in the evidence header.** Round 5 went 9/12 → 3/14. The bundle reports the
absolute number; a "regressed from 9/12" line would say plainly *stop resuming and take over*,
which is a decision currently left to the reviewer to notice.

**H2b. The scope gate makes "keep and follow up" awkward.** §9 offers keeping a partly-correct
attempt and writing a follow-up for the remaining delta — which worked (round 8). But the previous
round's files stay modified in the tree, and the scope gate compares against **HEAD**, not against
the run's start. Round 8 changed exactly one file and was still failed for `routes/search-log.php`,
modified by round 7 and deliberately kept. The follow-up plan therefore has to list files it will
not touch, purely to satisfy the gate — which then weakens the gate. Comparing against a run-start
snapshot would fix it, and is the same change H1-adjacent to the read-only gate's earlier bug.

**H3. `smoke-e2e` cannot catch A4.** It exercises the `stub` provider, so it never asks the real
model to emit a write. `setup-local-implementer` already probes the stack with a real tool call —
running that same probe inside `smoke-e2e`, or before each `handoff do`, would have turned round 6
from a wasted round into an upfront error.

**H4. Reports keep misrepresenting reality.** Round 6 returned `"status": "partial"` with the
summary *"No final text was provided in the previous response"* over a tree it had never touched.
Third instance this session. The "reports are never an input" rule is correct and should stay
prominently documented, because the failure is not rare.

### Skill

**S1. Assert the full shape of anything a later step consumes.** My step-1 tests gated what the
aggregates read; three fields the *view* needed went unguarded and were silently dropped. Step 1
would have been accepted and step 2 would then have failed on a gap step 1 was meant to guarantee.
Worth a line: when step N produces a structure step N+1 consumes, assert the complete shape in
step N.

**S2. Any named API that must be used deserves a grep criterion.** "Use `deduplicatedQueries()`"
was prose. The model injected the dependency and never called it, querying the table directly —
which against real data would have inflated every count, since that deduplication exists precisely
to remove the extension's re-captures. `grep -q 'deduplicatedQueries'` catches it in a second. The
same applies to "no scratch files", which prose failed twice.

**S3. Record the greenfield calibration.** The skill now warns that greenfield differs from the
measured refactor. This session gives it a number: 0 of 7 on greenfield Laravel service + view,
versus 78%/93% on a six-file refactor.

**S4. §9's four-cause table needs a fifth row.** Round 6 fits none of them — the plan was not
ambiguous, the commands were not wrong, there was no stub, and the model did not attempt the work
and get it wrong. It never ran. An "infrastructure failed; the plan was never exercised" row,
whose action is *re-run once, then fix the adapter* rather than *re-specify*, would close the gap.
This matters because §9's default instruction is "never re-run the same plan", which is exactly
wrong when the plan was never asked.

**S5. The keep-vs-revert guidance proved its worth.** Round 7's template was complete and correct
and only its PHP block was broken. Reverting would have thrown away a working 162-line view.
Keeping it and writing a one-file follow-up describing only the remaining delta is the right
shape — and the follow-up turns "do not regenerate the template" into an acceptance command that
counts the bars, rather than trusting an instruction.

---

## 6. Open items

- Step 3 (`rankingsv2-3-nav`) is written and checked, not yet run. The page itself is done and
  committed (`eeebd3a`); step 3 only adds the sidebar entry and the docs paragraph.
- A tracked-keywords table was left empty by the rebuild; restoring it needs an upstream
  re-auth and a sync command. Recorded because the rebuild looked complete and was not.
- A tracked `.env` was found in the product repository. Any secret committed once is in the
  history until the history is rewritten, so rotation comes first and `git rm --cached` second.
- A storage directory holds 295 `example.test` files — the `PageFetch` tests
  write to the real local disk. A test-isolation leak, harmless but worth fixing.
