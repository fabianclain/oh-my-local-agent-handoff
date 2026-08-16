# The report channel: stop repairing the envelope and try preventing the damage.
#
#   handoff overnight bench/queues/report-channel.sh --until 08:00
#   handoff overnight bench/queues/report-channel.sh --list
#
# WHAT IS BEING ASKED
#
# Every defence this harness has against a malformed completion report is post-hoc. A lenient
# harmony parser, a brace-balanced scan that descends into string values, schema-key scoring, a
# second ask. All repair; none prevention.
#
# Two of these arms go further than prevention: they fix what the model is TOLD, rather than how
# its answer is read. One settles a comparison that already exists but cannot be read.
#
#   1. nativeraw against native, UNDER ONE TREE. This comparison already has 12 runs on `wide`
#      and bench/compare refuses to read them: control b91dc3b, treatment 6bbd0cd. As it stands
#      nativeraw looks WORSE at the thing it was built to fix -- 4/6 no-report against 1/6 -- at
#      p = 0.24 and confounded, which is not a finding in either direction. Re-running both arms
#      under today's tree is the cheapest real result on this list: it converts existing data
#      rather than gathering new.
#
#   2. nativeharmony against NATIVERAW -- OpenAI's own renderer instead of llama.cpp's template.
#      Measured on identical conversations, llama.cpp's template loses two things the spec
#      requires. Every nested tool argument collapses to `any[]`: read_files.files, and
#      submit_report's files_changed, tests_run and deviations. The `start`/`end` window -- the
#      change that turned three dead rounds into an accepted one -- is not in the type the model
#      is shown at all. And tool results are JSON-quoted, so a seven-line file arrives with ZERO
#      newlines and seven literal \n sequences: the model has never seen the line structure of
#      anything it was asked to edit.
#
#      The control is nativeraw, not native. Both parse harmony locally and differ only in who
#      builds the prompt; comparing against native would fold the parser change in with it.
#
#   3. nativecot against NATIVEHARMONY -- the chain of thought carried between tool calls, which
#      docs/format.md's worked example does explicitly and this harness never has. Every turn has
#      started its reasoning from nothing. That is a candidate cause for rounds that re-read a
#      file they already read, and for the circling tools/repeat-guard exists to detect.
#
#      Not free: analysis is the bulk of what gpt-oss generates, so carrying it grows the context
#      it is meant to help, on a plan that already reaches 14-33k. It may cost more than it
#      returns, which is what the arm is for.
#
#   4. WHAT IS DELIBERATELY ABSENT. nativesym on `ledger` was in an earlier draft and is dropped:
#      tools/symbols exists because locating a declaration was hard, and one reason it was hard is
#      that files arrived with no newlines. Measuring it on the old renderer produces a number that
#      goes stale the moment arm 2 is settled. nativejson, nativetype and nativersp are built and
#      also absent -- none of them sits on this ladder, and four arms at eight waves buys n=24
#      where six arms would buy n=16 and the noise floor would eat the difference.
#
# WHAT THIS QUEUE CANNOT ANSWER
#
# Report loss is a proportion and this repository's noise floor on `wide` is about 17 points at
# n=6 -- bench/compare says so itself in the attempt-1 control. Detecting 30% -> 10% needs n near
# 60 per arm. Six waves buys n=18, which is enough to see a large effect and NOT enough to call a
# small one. The continuous measures -- generated tokens, seconds, turns -- are far better powered
# at this n and are where a real difference will show first. Read them first, and do not let a
# 4/18-against-2/18 be reported as a result.
#
# nativejson, nativetype and nativersp are BUILT and are deliberately NOT in this queue. Five arms
# at six waves buys n=18 each; four buys the same n on the questions most likely to move. The
# renderer defects are mechanical and measured, so they are the ones worth the night. nativersp
# in particular should wait: it costs +145 tokens per request against submit_report and its case
# is adherence, which is only readable once the renderer question is settled.
#
# THE LADDER. Every adjacent pair differs by exactly ONE thing, which is what makes each rung
# readable, and the whole thing readable against native -- the arm every published number here was
# measured on.
#
#   native          llama.cpp parses, llama.cpp renders, chain of thought dropped
#   nativeraw       WE parse            llama.cpp renders          -> isolates the parser
#   nativeharmony   we parse            WE render                  -> isolates the renderer
#   nativecot       we parse            we render      CoT CARRIED  -> isolates the chain of thought
#
# SIZING, from measured medians rather than hope
#
#   wide/native 204s   wide/nativeraw 222s
#
# A wave is 3 reps x 4 arms, roughly 44 minutes. Eight waves is about 7.5 hours and n=24 per arm.
# That is still short of the ~60 a proportion needs, and long enough to see a large effect on the
# continuous measures, which is where a real difference will show first.
#
# Waves rather than arms-in-sequence, for the reason the last two queues established: an
# interruption at any point leaves a balanced comparison rather than one complete arm and nothing
# to compare it against.

CLONE="${BENCH_CLONE:-$HOME/dev/agent-handoff-bench}"
HANDOFF="${HANDOFF_HOME:-$PWD}"

export BENCH_TIMEOUT_SECONDS=1200
export BENCH_MAX_ATTEMPTS=2

# The stack, stated once and asserted rather than assumed: b10331, gpt-oss-20b MXFP4, 98304,
# default sampling. doctor fails the queue before any GPU time is spent if the server is serving
# anything else -- which it silently was for forty minutes of the native-night queue.
export HANDOFF_EXPECT_CTX=98304

# --- before any GPU time is spent ----------------------------------------------------------------

job doctor --no-gpu --timeout 120 -- "$HANDOFF/tools/doctor"

job selftest --no-gpu --timeout 900 -- "$HANDOFF/tools/selftest-all"

job conformance --timeout 900 -- \
    "$HANDOFF/tools/engine-conformance" --engine llamacpp --model gpt-oss-20b --repeat 3

# The clone is what actually runs, and today's arms exist only in the working checkout until this
# runs. Without it every arm below would resolve to a provider the clone has never heard of.
job sync-clone --no-gpu --timeout 300 -- "$HANDOFF/tools/sync-bench-clone" "$CLONE"

# --- the waves -----------------------------------------------------------------------------------

for wave in 1 2 3 4 5 6 7 8; do
    flag="--append"
    [[ "$wave" == 1 ]] && flag="--force"

    # native FIRST in every wave. It is the control for all three comparisons, so if the night is
    # cut short the arm that survives is the one every reading depends on.
    for arm in native nativeraw nativeharmony nativecot; do
        job "w$wave-$arm" --cwd "$CLONE" --est 660 --timeout 3600 -- \
            ./bench/run --plan wide --providers "$arm" --repeat 3 "$flag"
    done

    job "w$wave-readout" --no-gpu --cwd "$CLONE" --timeout 300 -- \
        ./bench/compare wide nativeraw nativeharmony --acts-on first-attempt
done

# --- the morning ---------------------------------------------------------------------------------

# The one that settles an existing question rather than opening a new one.
job final-raw --no-gpu --cwd "$CLONE" --timeout 300 -- \
    ./bench/compare wide native nativeraw --acts-on first-attempt
# nativeraw is the control for the renderer, NOT native: both parse harmony locally and differ
# only in who builds the prompt. Comparing against native would fold the parser change in with it.
job final-harmony --no-gpu --cwd "$CLONE" --timeout 300 -- \
    ./bench/compare wide nativeraw nativeharmony --acts-on first-attempt
job final-cot --no-gpu --cwd "$CLONE" --timeout 300 -- \
    ./bench/compare wide nativeharmony nativecot --acts-on first-attempt

job final-summary --no-gpu --cwd "$CLONE" --timeout 300 -- ./bench/summary

# Which channel each report arrived through, and -- new tonight -- whether the extractor had to
# repair it to get there. A round rescued from inside a mangled tool call counts as reported and
# was previously indistinguishable from one the model simply answered.
job final-report-audit --no-gpu --cwd "$CLONE" --timeout 300 -- "$HANDOFF/tools/report-audit"

# The fault rate the whole nativejson hypothesis turns on. If constraining the report turn raises
# it, this is where that shows.
job final-peg-audit --no-gpu --timeout 120 -- "$HANDOFF/tools/peg-audit" --show 1
