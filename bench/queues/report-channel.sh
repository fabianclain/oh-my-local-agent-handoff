# The report channel: stop repairing the envelope and try preventing the damage.
#
#   handoff overnight bench/queues/report-channel.sh --until 08:00
#   handoff overnight bench/queues/report-channel.sh --list
#
# WHAT IS BEING ASKED
#
# Every defence this harness has against a malformed completion report is post-hoc. A lenient
# harmony parser, a brace-balanced scan that descends into string values, schema-key scoring, a
# second ask. All repair; none prevention. Three of these four arms ask whether prevention is
# available, and the fourth settles a comparison that already exists but cannot be read.
#
#   1. nativeraw against native, UNDER ONE TREE. This comparison already has 12 runs on `wide`
#      and bench/compare refuses to read them: control b91dc3b, treatment 6bbd0cd. As it stands
#      nativeraw looks WORSE at the thing it was built to fix -- 4/6 no-report against 1/6 -- at
#      p = 0.24 and confounded, which is not a finding in either direction. Re-running both arms
#      under today's tree is the cheapest real result on this list: it converts existing data
#      rather than gathering new.
#
#   2. nativejson -- response_format: json_schema on the report turn. llama.cpp has accepted this
#      on this server the whole time and nothing here ever sent one. Probed against the real
#      schema before the arm was written: 7 of 7 required keys, valid JSON. Against a bare
#      json_object the same request answered {"status":"completed"} -- not a value the enum admits
#      -- and `message` for `summary`.
#
#      It cannot be a cure. Of the four recorded report-turn failures at depth, a grammar
#      precludes two (prose; a tool call emitted as text with the report nested inside) and is
#      powerless against two (truncation; an empty response). Expect half.
#
#      It may also BACKFIRE, which is why it is an arm. 18 of the 99 completions llama.cpp
#      discarded in one night were a `final` message tagged `<|constrain|>json` -- the marker
#      harmony emits when told to produce JSON. Asking for constrained JSON may raise the rate of
#      the fault that eats reports. That is a mechanism, and it is measurable here.
#
#   3. nativetype -- the report's shape shown as a type definition rather than JSON Schema. 762
#      tokens to 339 on the real schema, measured with this model's tokenizer, every property,
#      enum value and description preserved.
#
#      The reason is not the tokens. --report-tool-max-depth exists because the schema costs so
#      much context that the chosen fix was to stop offering the report TOOL past a depth -- the
#      tool whose absence is this project's largest non-success outcome. This relieves that
#      pressure instead of trading the report away to relieve it.
#
#   4. nativesym on `ledger` -- the symbols tool, which has never been measured. Its bench was
#      launched, archived one directory, and died at a reboot. `ledger` rather than `wide`
#      because symbols addresses big-file anchoring, which is what ledger exercises.
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
# nativejson and nativeraw are NOT combinable and are not combined here. A json_schema grammar
# constrains the whole completion, and the raw path's completion begins with harmony channel
# tokens rather than `{`; native-agent refuses the pairing rather than producing nonsense.
#
# SIZING, from measured medians rather than hope
#
#   wide/native 204s   wide/nativeraw 222s
#
# A wide wave is 3 reps x 4 arms, roughly 3*(204+222+215+215) = 43 minutes. Six waves is 4.3
# hours and n=18 per arm. The ledger blocks add about 40 minutes each and run on waves 2 and 4, so
# a short night still leaves them balanced.
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

for wave in 1 2 3 4 5 6; do
    flag="--append"
    [[ "$wave" == 1 ]] && flag="--force"

    # native FIRST in every wave. It is the control for all three comparisons, so if the night is
    # cut short the arm that survives is the one every reading depends on.
    for arm in native nativeraw nativejson nativetype; do
        job "w$wave-$arm" --cwd "$CLONE" --est 660 --timeout 3600 -- \
            ./bench/run --plan wide --providers "$arm" --repeat 3 "$flag"
    done

    job "w$wave-readout" --no-gpu --cwd "$CLONE" --timeout 300 -- \
        ./bench/compare wide native nativejson --acts-on first-attempt

    # ledger, for the symbols arm. Waves 2 and 4 so a short night still leaves it balanced.
    if [[ "$wave" == 2 || "$wave" == 4 ]]; then
        lflag="--append"; [[ "$wave" == 2 ]] && lflag="--force"
        for arm in native nativesym; do
            job "l$wave-$arm" --cwd "$CLONE" --est 600 --timeout 3600 -- \
                ./bench/run --plan ledger --providers "$arm" --repeat 3 "$lflag"
        done
    fi
done

# --- the morning ---------------------------------------------------------------------------------

# The one that settles an existing question rather than opening a new one.
job final-raw --no-gpu --cwd "$CLONE" --timeout 300 -- \
    ./bench/compare wide native nativeraw --acts-on first-attempt
job final-json --no-gpu --cwd "$CLONE" --timeout 300 -- \
    ./bench/compare wide native nativejson --acts-on first-attempt
job final-type --no-gpu --cwd "$CLONE" --timeout 300 -- \
    ./bench/compare wide native nativetype --acts-on first-attempt
job final-sym --no-gpu --cwd "$CLONE" --timeout 300 -- \
    ./bench/compare ledger native nativesym --acts-on first-attempt

job final-summary --no-gpu --cwd "$CLONE" --timeout 300 -- ./bench/summary

# Which channel each report arrived through, and -- new tonight -- whether the extractor had to
# repair it to get there. A round rescued from inside a mangled tool call counts as reported and
# was previously indistinguishable from one the model simply answered.
job final-report-audit --no-gpu --cwd "$CLONE" --timeout 300 -- "$HANDOFF/tools/report-audit"

# The fault rate the whole nativejson hypothesis turns on. If constraining the report turn raises
# it, this is where that shows.
job final-peg-audit --no-gpu --timeout 120 -- "$HANDOFF/tools/peg-audit" --show 1
