FEATURE = 3

<!-- ^^^ THE ONE LINE TO EDIT. 1, 2, 3 or 4. Nothing else changes between runs. ^^^ -->

---

# Does planning amortize? Four panels, one shape, four measurements

Four features are built **in order, in one worktree**, each on top of the last. They deliberately
share an architecture and differ only in content. The question is not whether they work — it is
whether the SECOND one is cheaper to plan than the first, and the fourth cheaper still.

That single number decides whether the local-implementer route is ever cheaper than writing the
code directly. Measured over four runs of a one-off feature it costs **2.0x the Claude output
tokens and 4.3x the wall clock**, and **84% of that is planning**. Planning is a fixed cost paid
once. If it amortizes across features of the same shape, the route wins on repeated work; if every
feature needs it rewritten, the 2.0x is permanent and the route is for special cases only.

So `T_plan` is the measurement. Everything else is bookkeeping.

## Use the local-implementer skill

You are the reviewer. **gpt-oss-20b writes the implementation, through the handoff harness.** You
write the plan and the judging tests; you do not write implementation code. Invoke the skill:

    /local-implementer

and follow it. If a step cannot be landed by the model, report that — it is a result, not a failure,
and implementing it yourself destroys the measurement.

## The worktree — created once, for feature 1 only

    cd /home/fabbs/dev/monolith/local-implementer
    TREE="$(bench/monolith-worktree machine-panels master)"
    cd "$TREE"

**Features 2, 3 and 4 reuse that same worktree.** They build on the previous feature's commits;
that is what "amortize" means here. Do not create a new one and do not reset it. If
`/home/fabbs/dev/bench-trees/machine-panels` already exists, you are not feature 1 — check
`git log --oneline` to see which panels have landed and confirm you are the next one.

**Start each feature in a FRESH session, and inherit through the files rather than the
conversation.** Reuse that only works because one session still remembers is not amortization — it
is one long session, and it does not survive someone else building feature 3 next week. So the
first thing feature 2, 3 and 4 do is read what the previous feature left on disk:

    ls .claude/plans/machine-panels-*.md          # the plans, including the re-specified ones
    ls tests/Feature/Machine/                     # the judging tests
    git log --oneline                             # what landed, and in what order

Those are the artifacts under test. Say in your report which of them you opened, which you copied
from, and which turned out to be useless — that is the finding, and it is more informative than
`T_plan` alone.

## Four clocks, and the ISO stamps that make the token split possible

    date +%s                      # durations
    date -u +%Y-%m-%dT%H:%M:%SZ   # for bench/token-report --impl-start

| number | what it is |
| --- | --- |
| `T_plan` | **the measurement.** Design, the judging tests, the plans, `check-plan`, `prepare` |
| `T_impl` | the harness running the plans |
| `T_verify` | the shared verification below |
| `T_wait` | queueing for the model lock; report separately, it is not the model's time |

Reading is preparation and is excluded — but say how long it took, because for features 2-4 it
should collapse, and that collapse is part of what amortizes.

## What is already true, so you do not go and look it up

Inlined deliberately. A plan that points at a file buys the model a round trip; measured on this
harness, a step given three files to learn from cost **467s and 81 iterations** where a step handed
its facts cost **70s and 18**. The same applies to you: none of the below needs opening.

**`machine_minutes`** — one row per host per minute:

    host, bucket_start, samples, covered_seconds
    cpu_util_avg, cpu_util_max, cpu_power_avg_w, cpu_power_max_w, cpu_energy_wh, cpu_power_samples
    load1_avg, load1_max
    ram_used_avg_mib, ram_used_max_mib, ram_total_mib, swap_used_max_mib
    cpu_temp_avg_c, cpu_temp_max_c, nvme_temp_max_c
    dram_power_avg_w, dram_power_max_w, dram_energy_wh, dram_power_samples
    disk_busy_avg_pct, disk_power_avg_w_est, disk_energy_wh_est
    psys_power_avg_w, psys_power_max_w, psys_energy_wh, psys_power_samples

**`gpu_minutes`** — one row per host per GPU per minute:

    host, bucket_start, gpu_index, samples, covered_seconds
    util_gpu_avg, util_gpu_max, util_mem_avg, util_mem_max
    mem_used_avg_mib, mem_used_max_mib, mem_total_mib
    power_avg_w, power_max_w, power_limit_w, energy_wh
    temp_avg_c, temp_max_c, clock_sm_avg_mhz, fan_max_pct

**`gpu_process_minutes`** — one row per host per GPU per command per minute:

    host, bucket_start, gpu_index, command, samples, pids_seen
    sm_avg, sm_max, sm_seconds, mem_avg, fb_avg_mib, fb_max_mib, energy_wh_est

Models are `App\Domains\Machine\Models\{MachineMinute,GpuMinute,GpuProcessMinute}`.

**The read side** is `App\Domains\Machine\Services\MachineMetrics`, whose public methods today are
`host()`, `hosts()`, `series()`, `totals()`, `periods()`, `processes()`, `latest()`.

**The page** is `resources/views/pages/machine/⚡monitor.blade.php` — 597 lines, no partials, whose
sections today are "GPU & power", "Where the power goes", "Last measured minute", and "What was on
the GPU". Route `machine`, name `machine.monitor`.

**The section-registry pattern to copy** is `resources/views/pages/local-model/⚡usage.blade.php`:
a `private const SECTIONS = ['key' => 'Label', …]` map, a `sectionOrder()` that drops unknown keys
and appends ones the stored order has never seen, and one `_section-<key>.blade.php` partial per
entry beside the page.

**Two project rules that bite here**, both from `docs/features/machine-metrics.md` and `CLAUDE.md`:

- **Average power is energy over hours, never the mean of `power_avg_w`** — a one-sample minute
  must not weigh the same as a full one. Where a panel reports an average of anything sampled,
  weight it by `covered_seconds`.
- **NULL is not 0.** CPU and DRAM wattage are NULL when RAPL is unreadable; a gap in coverage is
  absence, not zero. `MachineMetrics::PAYLOAD_VERSION` is `3` and **must be bumped when a cached
  return shape changes** — payloads are cached on the newest stored minute, which does not move
  when code adds a field.

## Before you spend a round: prove the criteria can pass

`handoff prepare` is a negative control — it shows every criterion failing now, which is what a
not-yet-built step should do. It cannot distinguish "fails because the work is not done" from
"fails because no tree could pass". That second case took **8 of feature 1's 9 rejected rounds**.

So for every step, also run the positive control:

    bench/audit-criteria <a tree holding the finished work> .claude/plans/<slug>.md

Every criterion MUST pass there. Make that tree by applying your own dictated recipe by hand, then
reverting — two minutes. The run that did this landed 3 of 3 steps first-roll; feature 1, which did
not, lost 9 of 13 rounds and 8 were criteria written wrong.

Three specific traps feature 1 paid for, all now checkable:

- **No shell variables in a `## Steps` recipe.** A criterion is run by the harness as an argv list
  where `$VAR` is safe; a recipe is run by the MODEL, which wraps it in `bash -lc "…"` and the
  variable expands to nothing first. Cost: 3 rolls, 1.9M tokens. `plan-lint` now warns.
- **Splice at a line number; never "insert before X".** Splicing landed first-roll in 84-128s;
  "insert ~90 lines before the `energy()` docblock" took 3 rolls, 2,580s and 3.49M tokens — 42% of
  the run — and never landed.
- **`patch-shape` forbids removing an original line.** A step that must move lines cannot also
  carry a no-deletion bound. Two rolls scored 16 of 17 against a criterion no tree could satisfy.

## The feature — read the FEATURE number on line 1

**FEATURE = 1 — Pressure.** Introduce the section registry into `/machine`, and ship the first panel
with it: swap, load average and RAM headroom. `swap_used_max_mib`, `load1_avg`, `load1_max`,
`ram_used_max_mib` against `ram_total_mib`. This is the panel that would have shown last night's
incident, when swap sat at 8191 of 8191 MiB, the machine OOM-killed a process, and this page — whose
job is machine health — said nothing. Swap in use at all is the signal; swap full is the alarm.

**FEATURE = 2 — Thermals.** `cpu_temp_avg_c`, `cpu_temp_max_c`, `nvme_temp_max_c`, and from
`gpu_minutes` `temp_max_c` and `fan_max_pct`. The honest pairing is average beside maximum: a
minute's average hides the spike that throttles, so a panel showing only one of them is worse than
none.

**FEATURE = 3 — Disk.** `disk_busy_avg_pct` beside the `disk_power_avg_w_est` the page already
shows. Today it presents a wattage *derived from* a measurement it never displays; this makes that
estimate auditable.

**FEATURE = 4 — Per-process detail.** `pids_seen` and `fb_max_mib` per `command` in
`gpu_process_minutes`, extending what "What was on the GPU" reports. One command that is forty
processes and one that is a single long-lived server read identically today — which is exactly the
question a resident `llama-server` raised last night.

Stop at the feature named. Do not build ahead.

## Verification, identical every time

    cd "$TREE"
    php artisan test --compact --parallel --exclude-testsuite=Browser
    vendor/bin/pint --test --format txt <your changed files>

    H=/home/fabbs/dev/monolith/local-implementer
    FILES=$(git diff --name-only master...HEAD -- '*.php')
    python3 $H/tools/invisible-characters $FILES
    python3 $H/tools/process-commentary   $FILES
    python3 $H/tools/blade-balance        $(git diff --name-only master...HEAD -- '*.blade.php')

## Report

    FEATURE          <n>
    reading          <mm:ss>   (excluded from the total; report it anyway)
    T_plan           <mm:ss>   <-- THE MEASUREMENT
    T_impl           <mm:ss>
    T_verify         <mm:ss>
    T_wait           <mm:ss>
    impl started at  <ISO-8601 UTC>
    ------------------------------------
    TOTAL (excl wait) <mm:ss>

    steps planned    <n>
    steps landed     <n>
    rounds/attempts  <n>  (per-step seconds from the journal)
    tests            <pass/fail>
    pint             <clean | n, and whether any are yours>
    invisible chars / edit narration / blade balance
    diff             implementer <n files, +n>; whole feature <n files, +n>

Then run the token report and paste it verbatim:

    /home/fabbs/dev/monolith/local-implementer/bench/token-report machine-panels --impl-start <ISO>

Then, in prose:

- **What of the previous feature's plan you reused, and what you had to write fresh.** For feature 1
  this is "nothing, it is the first". For 2-4 it is the finding: name the sections you copied
  wholesale, the ones you edited, and the ones that had no counterpart.
- **What the implementer got wrong**, quoting rejected rolls' scores. Read the diff by hand — the
  gates have missed a transcribed instruction, a half-written empty state that still scored 6/6, and
  a paginator `count()` that reports rows on the page rather than rows in total.
- **What you had to decide that the requirements did not settle.**

## Rules

- Do not write implementation code. The model does that or it does not get done.
- Do not commit to `master`, do not push.
- **Drive from a subagent, and tell it explicitly not to return until the sequence has exited.**
  Both halves matter. The subagent is CONTAINMENT: you will probably poll despite being told not
  to, and inside a subagent that costs ~36k a turn instead of ~321k. Measured across two features
  of one series — with subagents, 257 parent turns and 66.1M cache reads; without, 1,877 turns and
  603.6M, nine times the cost. The no-early-return half is separate: a driver that returns as soon
  as it has backgrounded the sequence reports "finished" while step 1 is still running. Produce
  nothing yourself while it runs, and do not arm a per-step monitor — the journal has every verdict
  afterwards.
- Report the unflattering numbers. A feature that does not land is the most useful result here.
