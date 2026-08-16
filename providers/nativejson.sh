#!/usr/bin/env bash
#
# nativejson — the native loop, with the report turn constrained by the schema.
#
# llama.cpp has accepted `response_format: {"type":"json_schema"}` on this server the whole time
# and nothing in this harness ever sent one. Every defence against a malformed report here is
# post-hoc: a lenient harmony parser, a brace-balanced scan, schema-key scoring, and a second ask.
# All repair. None prevention.
#
# Probed against the real schema before this arm was written: 7 of 7 required keys, valid JSON,
# sensible contents. Against a bare `json_object` the same request returned `{"status":"completed"}`
# -- not a value the enum admits -- and `message` instead of `summary`. That drift is what the
# extractor exists to survive, and what a grammar removes at source.
#
# WHAT IT CANNOT DO. Of the four report-turn failures recorded at depth, a grammar precludes two
# (62 characters of prose; a tool call emitted as text with the report nested inside it) and is
# powerless against two (reasoning truncated mid-sentence; an empty response), which are budget and
# transport. Expect half, not a cure.
#
# WHY IT MIGHT BACKFIRE, which is the reason this is an arm. 18 of the 99 completions llama.cpp
# discarded in one night were a `final` message tagged `<|constrain|>json` -- the marker harmony
# emits when it has been told to produce JSON. Asking for constrained JSON may raise the rate of
# the exact fault that loses reports. That is a hypothesis with a mechanism, and it is measurable.
#
# NOT COMBINABLE WITH nativeraw. The raw path's completion begins with harmony channel tokens, and
# a json_schema grammar would force `{` at the first token. native-agent refuses the combination
# rather than producing nonsense.
# shellcheck disable=SC1090
source "$(dirname "${BASH_SOURCE[0]}")/native.sh"

provider_name() { echo "nativejson"; }
export NATIVE_RESPONSE_FORMAT=1
