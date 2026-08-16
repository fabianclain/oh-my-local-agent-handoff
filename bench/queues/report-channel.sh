# The report channel and the prompt: a SCREEN across nine arms.
#
#   handoff overnight bench/queues/report-channel.sh --until 08:00
#   handoff overnight bench/queues/report-channel.sh --list
#
# WHAT THIS IS, AND WHAT IT IS NOT
#
# This is a SCREEN, not a confirmation, and reading it as one would be the mistake this file exists
# to prevent. THIRTEEN arms in a night buys n=9 each; the four-rung ladder alone would have bought
# n=30. At n=9 a proportion resolves to roughly +/-30 points, so ACCEPT RATE WILL NOT SETTLE
# ANYTHING HERE -- not for one arm, and certainly not across thirteen, where testing that many
# comparisons at once makes a spurious "winner" likely by chance alone.
#
# What n=9 can do is rank the CONTINUOUS measures -- generated tokens, seconds, model requests --
# where a Mann-Whitney sees a ratio of about 1.4x. Read those, in that order, and treat the outcome
# counts as colour.
#
# The intended shape is two nights: screen wide tonight, then confirm whatever moves at n=30.
# Anything reported from tonight as "arm X is better" without that second night is a claim this
# data cannot support.
#
# THE LADDER, which is still the spine. Each rung differs from the one above it by exactly ONE
# thing, so each is readable against its own neighbour rather than against native.
#
#   native          llama.cpp parses, llama.cpp renders, chain of thought dropped
#   nativeraw       WE parse           llama.cpp renders          -> the parser
#   nativeharmony   we parse           WE render                  -> the renderer
#   nativecot       we parse           we render     CoT CARRIED   -> the chain of thought
#
# WHAT THE RENDERER RUNG IS ABOUT, since it is the one with mechanical evidence behind it. Measured
# against openai-harmony on identical conversations, llama.cpp's template loses two things the
# specification requires. Every nested tool argument collapses to `any[]` -- read_files.files, and
# submit_report's files_changed, tests_run and deviations -- so the `start`/`end` window, the change
# that turned three dead rounds into an accepted one, is not in the type the model is shown at all.
# And tool results are JSON-quoted: a seven-line file arrives with ZERO newlines and seven literal
# \n sequences. The model has never seen the line structure of anything it was asked to edit.
#
# THE FIVE HANGING OFF IT, each against the arm it actually varies from:
#
#   nativegrammar   vs nativeharmony. Both halves of docs/format.md's structured output: the schema
#                   declared in the developer message where the model expects to read it, AND a
#                   GBNF built from that schema wrapped in the harmony final-message envelope, so
#                   the sampler cannot emit anything else. The spec says the declaration alone
#                   "doesn't guarantee the full adherence to the schema"; this is the other half.
#                   Measured: 118 tokens, every required key, status inside the enum -- where the
#                   same turn under a generic JSON grammar answered "completed", which the enum
#                   does not admit.
#
#   nativersp       vs nativeharmony. The declaration WITHOUT the grammar, so the pair says how
#                   much of any effect is the prompt and how much is the sampler. Costs +145 tokens
#                   per request against submit_report, measured, so its case is adherence not
#                   economy.
#
#   nativejson      vs native. response_format on the chat path -- the enforcement half, on the
#                   branch that cannot reach the harmony renderer. Kept because if the ladder shows
#                   nothing, this is the cheap improvement that remains.
#
#   nativetype      vs native. The report schema rendered as a type definition, 762 tokens to 339,
#                   every property, enum value and description preserved.
#
#   nativesym       vs native. The symbols tool, which has still never been measured. NOTE it is on
#                   `wide` here rather than `ledger`, which is a weaker test of it: symbols exists
#                   for big-file anchoring and ledger is the plan that exercises that. Read a null
#                   result here as "not on this plan", not as "no effect".
#
# AND FOUR THAT PRE-DATE ALL OF IT, each built for a question and none ever measured against a
# control under one tree:
#
#   nativelean      three context changes together: pruned superseded reads, the report tool
#                   withdrawn past 10k, and a syntax-warning budget
#   nativemsg       no submit_report tool at all, so the report can only come from the final turn
#   nativeprune     read results replaced once the model has overwritten the file
#   nativewhole     no replace_in_file: every edit is a whole-file write
#
# Waves rather than arms-in-sequence, for the reason the last three queues established: an
# interruption at any point leaves a balanced comparison rather than one complete arm and nothing
# to compare it against. With nine arms a wave is about 105 minutes, so a night cut short loses a
# whole wave rather than a whole arm.
#
# SIZING, from measured medians rather than hope
#
#   wide/native 204s   wide/nativeraw 222s
#
# Three waves of thirteen arms is 9h13m including the preamble, against a 9-hour window from 23:00
# to 08:00. That is over by a quarter of an hour, deliberately: waves mean a deadline cuts a whole
# wave rather than a whole arm, so the arms stay balanced either way. What a cut WILL take is the
# morning readouts at the end -- they need no GPU and take a minute each, so run them by hand if
# the night runs out:
#
#   cd ~/dev/agent-handoff-bench && ./bench/compare wide nativeraw nativeharmony --acts-on first-attempt

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

for wave in 1 2 3; do
    flag="--append"
    [[ "$wave" == 1 ]] && flag="--force"

    # native FIRST in every wave. It is the control for all three comparisons, so if the night is
    # cut short the arm that survives is the one every reading depends on.
    for arm in native nativeraw nativeharmony nativecot nativegrammar \
               nativersp nativejson nativetype nativesym \
               nativelean nativemsg nativeprune nativewhole; do
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
# Each of these against the arm it actually varies from, not against native. nativegrammar and
# nativersp both imply the harmony renderer, so nativeharmony is their control; nativejson and
# nativetype are chat-path changes and belong against native.
job final-grammar --no-gpu --cwd "$CLONE" --timeout 300 -- \
    ./bench/compare wide nativeharmony nativegrammar --acts-on first-attempt
job final-rsp --no-gpu --cwd "$CLONE" --timeout 300 -- \
    ./bench/compare wide nativeharmony nativersp --acts-on first-attempt
job final-json --no-gpu --cwd "$CLONE" --timeout 300 -- \
    ./bench/compare wide native nativejson --acts-on first-attempt
job final-type --no-gpu --cwd "$CLONE" --timeout 300 -- \
    ./bench/compare wide native nativetype --acts-on first-attempt
job final-sym --no-gpu --cwd "$CLONE" --timeout 300 -- \
    ./bench/compare wide native nativesym --acts-on first-attempt
# The four that pre-date all of this and have never been measured under one tree with a control.
job final-lean --no-gpu --cwd "$CLONE" --timeout 300 -- \
    ./bench/compare wide native nativelean --acts-on first-attempt
job final-msg --no-gpu --cwd "$CLONE" --timeout 300 -- \
    ./bench/compare wide native nativemsg --acts-on first-attempt
job final-prune --no-gpu --cwd "$CLONE" --timeout 300 -- \
    ./bench/compare wide native nativeprune --acts-on first-attempt
job final-whole --no-gpu --cwd "$CLONE" --timeout 300 -- \
    ./bench/compare wide native nativewhole --acts-on first-attempt

job final-summary --no-gpu --cwd "$CLONE" --timeout 300 -- ./bench/summary

# Which channel each report arrived through, and -- new tonight -- whether the extractor had to
# repair it to get there. A round rescued from inside a mangled tool call counts as reported and
# was previously indistinguishable from one the model simply answered.
job final-report-audit --no-gpu --cwd "$CLONE" --timeout 300 -- "$HANDOFF/tools/report-audit"

# The fault rate the whole nativejson hypothesis turns on. If constraining the report turn raises
# it, this is where that shows.
job final-peg-audit --no-gpu --timeout 120 -- "$HANDOFF/tools/peg-audit" --show 1
