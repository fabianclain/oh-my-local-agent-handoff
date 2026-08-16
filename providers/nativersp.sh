#!/usr/bin/env bash
#
# nativersp — the report declared where gpt-oss expects it, instead of as a tool.
#
# docs/format.md defines structured output as a section at the END of the developer message:
#
#     # Response Formats
#
#     ## {format name}
#
#     // {description or context}
#     {schema}
#
# This harness has never used it. The schema goes into submit_report's `parameters`, which ride in
# the tools block of EVERY request, and is dumped again as a user message on the report turn. Both
# are places the model was not trained to look for an output format.
#
# It also reframes something already measured. Of the 99 completions llama.cpp discarded in one
# night, 18 were a `final` message tagged <|constrain|>json carrying the completion report --
# generated, complete, and thrown away. That IS the native structured-output path. submit_report
# may be a workaround for a channel that already existed.
#
# THE SPEC IS CANDID that the declaration alone is not enough: "This prompt alone will, however,
# only influence the model's behavior but doesn't guarantee the full adherence to the schema. For
# this you still need to construct your own grammar and enforce the schema during sampling." That
# grammar is providers/nativejson.sh. The two halves belong together and this project had only the
# second one; run them together once each is measured alone.
#
# ONE CHANGE, stated as one idea: the report moves from the tool channel to the native one.
# --no-report-tool is not a second variable, it is the other half of the same move -- declaring the
# format AND keeping the tool would be asking for the report twice.
#
# IT COSTS TOKENS, and the first draft of this file claimed the opposite. Measured on the real tool
# set and the real schema, through this renderer:
#
#     submit_report as a tool           865 tokens per request
#     as a # Response Formats section  1010 tokens per request   (+145)
#
# The tool is CHEAPER because harmony renders it as a compact TypeScript type, while the spec
# defines the response-format section as a raw JSON Schema and there is no typedef option there.
# So the case for this arm is adherence, not economy: it is the mechanism the model was trained to
# read, and 18 discarded completions suggest it is the one the model reaches for anyway. If it does
# not improve the report rate it is simply worse, and the measurement will say so.
# shellcheck disable=SC1090
source "$(dirname "${BASH_SOURCE[0]}")/native.sh"

provider_name() { echo "nativersp"; }
NATIVE_EXTRA_ARGS="${NATIVE_EXTRA_ARGS:-} --harmony-render --response-format-section --no-report-tool"
