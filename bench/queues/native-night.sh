# Ten hours on the native loop: does it beat the rented one, and which of its choices matter.
#
#   handoff overnight bench/queues/native-night.sh --until 08:00
#   handoff overnight bench/queues/native-night.sh --list
#
# WHAT IS BEING ASKED
#
# Three questions, all of which need n that a day of interactive runs cannot buy.
#
#   1. native against lcgptossl on the same plan, under the SAME harness commit. Today's native
#      numbers (wide 2/4, surgical 2/2, semantic 4/4) are against a control measured under a
#      pre-scratch-fix harness, which bench/compare flags and which makes the damage counts
#      incomparable. Re-running the control is the only way to fix that.
#
#   2. nativewhole — every edit a whole-file write. This is round 15, which sat unrunnable for
#      months because it needed a client that would offer a different tool set, and is now a
#      three-line overlay. Does rewriting wholesale kill mis-anchored edits, or trade them for
#      truncation?
#
#   3. nativemsg — no submit_report tool, so the report can only come from the no-tools final turn.
#      The fallback already removes the tools; this asks whether offering the tool as well adds
#      anything. Round 10 measured the tool channel at 1/12 against 4/15, but through Cline, which
#      confounded the channel with the client.
#
# SIZING, from measured medians rather than hope
#
#   wide/native 183s   wide/lcgptossl 258s   semantic/native 80s   semantic/lcgptossl 179s
#
# A wide wave is 3 reps x 4 arms — roughly (3*183 + 3*183 + 3*183 + 3*258) = 40 minutes. Six waves
# is four hours and n=18 per arm. The semantic waves add about an hour, and the closing analysis
# needs no GPU at all.
#
# Waves rather than arms-in-sequence, for the reason last night established: an interruption at any
# point leaves a balanced comparison rather than one complete arm and nothing to compare it to.

# A CONFOUND TO DECLARE, found while launching this.
#
# The queue aborted on its first attempt because `doctor` reported cline missing. The package was
# present; its bin symlink was not. The file is dated 22:10 tonight and reports 3.0.53, where
# doctor saw 3.0.52 this morning — cline upgraded mid-session and the upgrade did not recreate the
# link. So tonight's lcgptossl runs are on 3.0.53 and today's are on 3.0.52.
#
# Within tonight the comparison is clean, because every arm runs under one client. Against today's
# numbers it is not, and the client version now belongs in the same list as the harness commit and
# the llama.cpp build: things that change underneath a measurement and are recorded nowhere.
#
# It is also the reason doctor's cline check earns its keep. Without it the control arm would have
# failed every round for a missing binary, and the native arms would have looked better for it.
# A SECOND CONFOUND, and the reason this queue was restarted at 23:35.
#
# The first launch ran for forty minutes against a server started with `-c 32768`. Every document
# involved -- this file, the handoff prompt, the roadmap -- said 98304. The server was a leftover
# from an afternoon of report probing and nothing objected: doctor prints the served context but
# only complains BELOW 32768, provider_preflight checks /health which cannot report settings, and
# native's provider_manifest replaced the inherited one, which is the only place server_props is
# recorded. The Cline arms had carried n_ctx in every result file all along. The native arms, which
# were the three that ran, carried nothing.
#
# It was found by reading a context-budget message that named the wrong window, not by any check.
# HANDOFF_EXPECT_CTX below is that check, and it now fails the queue before any GPU time is spent.
#
# Those forty minutes are in bench/archive/wide-*-ctx32768 rather than deleted. They are the only
# measurement of this loop against a window it can exhaust -- nativewhole stopped on the context
# budget in three of three provider calls at ~28.8k -- and at 98304 that will not reproduce. Read
# as whole-file writes exhausting the window, it would have answered round 15 wrongly.
#
# A THIRD THING CHANGED, deliberately. The harness under test now includes tonight's fixes: the
# peg-fault retry, the post-write syntax check, and the report turn asked twice with a brace-
# balanced parser. The first two arms of the night measured the loop as it was; from here it is
# the loop as it should be. Question 1 is unaffected -- both arms still run under ONE harness
# commit, which is what it asks -- but nothing here is comparable with this morning's native
# numbers, which were taken under a different harness AND a different window.
CLONE="${BENCH_CLONE:-$HOME/dev/agent-handoff-bench}"
HANDOFF="${HANDOFF_HOME:-$PWD}"

export BENCH_TIMEOUT_SECONDS=1200
export BENCH_MAX_ATTEMPTS=2

# The stack, stated once and asserted rather than assumed. b10331, gpt-oss-20b, 98304, default
# sampling. doctor fails if the server is serving anything else.
export HANDOFF_EXPECT_CTX=98304

# --- before any GPU time is spent ----------------------------------------------------------------

job doctor --no-gpu --timeout 120 -- "$HANDOFF/tools/doctor"

# The stack is deliberately NOT recalibrated. Every number tonight must be comparable with today's,
# and context size is part of the stack: gpt-oss-20b on b10331 at 98304 with default sampling.
job conformance --timeout 900 -- \
    "$HANDOFF/tools/engine-conformance" --engine llamacpp --model gpt-oss-20b --repeat 3

job sync-clone --no-gpu --timeout 300 -- "$HANDOFF/tools/sync-bench-clone" "$CLONE"

# --- the waves -----------------------------------------------------------------------------------

for wave in 1 2 3 4 5 6; do
    flag="--append"
    [[ "$wave" == 1 ]] && flag="--force"

    for arm in native nativewhole nativemsg lcgptossl; do
        job "w$wave-$arm" --cwd "$CLONE" --est 700 --timeout 3600 -- \
            ./bench/run --plan wide --providers "$arm" --repeat 3 "$flag"
    done

    job "w$wave-readout" --no-gpu --cwd "$CLONE" --timeout 300 -- \
        ./bench/compare wide lcgptossl native --acts-on first-attempt

    # semantic is the only plan where correctness can be checked independently of the gates, and
    # today it caught an accepted implementation that was wrong on 2,283 of 4,000 fuzzed trials.
    # Two waves of it, placed early enough to survive a short night.
    if [[ "$wave" == 2 || "$wave" == 4 ]]; then
        sflag="--append"; [[ "$wave" == 2 ]] && sflag="--force"
        job "s$wave-native" --cwd "$CLONE" --est 340 --timeout 2400 -- \
            ./bench/run --plan semantic --providers native --repeat 4 "$sflag"
        job "s$wave-control" --cwd "$CLONE" --est 740 --timeout 2400 -- \
            ./bench/run --plan semantic --providers lcgptossl --repeat 4 "$sflag"
    fi
done

# --- the morning ---------------------------------------------------------------------------------

job final-compare-whole --no-gpu --cwd "$CLONE" --timeout 300 -- \
    ./bench/compare wide native nativewhole --acts-on first-attempt
job final-compare-msg --no-gpu --cwd "$CLONE" --timeout 300 -- \
    ./bench/compare wide native nativemsg --acts-on first-attempt
job final-compare-semantic --no-gpu --cwd "$CLONE" --timeout 300 -- \
    ./bench/compare semantic lcgptossl native --acts-on first-attempt
job final-summary --no-gpu --cwd "$CLONE" --timeout 300 -- ./bench/summary

# Correctness, not acceptance. Every semantic implementation fuzzed against the specification —
# the check that caught a 4/4-accepted arm hiding a wrong answer.
job fuzz-semantic --no-gpu --timeout 900 -- \
    "$HANDOFF/bench/checks/fuzz-all-semantic" "$CLONE/bench/results/semantic"

job final-peg-audit --no-gpu --timeout 120 -- "$HANDOFF/tools/peg-audit" --show 1
