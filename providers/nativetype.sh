#!/usr/bin/env bash
#
# nativetype — the native loop, showing the report's shape as a type definition.
#
# schemas/handoff.schema.json is 762 tokens rendered as JSON Schema, and the model reads it twice:
# once in submit_report's parameters, which ride in the tools block of every request, and again in
# full on every report-turn attempt. The same information as a type definition is 339 tokens.
#
# 2.2x, measured here with this model's tokenizer against the real schema. Not the 6x first
# reported from a hand-written version that had quietly dropped most of the descriptions --
# tools/schema-typedef-selftest exists to make that mistake impossible to repeat, and the honest
# number is the smaller one.
#
# The reason to care is not the tokens. --report-tool-max-depth exists because the schema costs so
# much context that the chosen fix was to STOP OFFERING the report tool past a depth -- the tool
# whose absence is this project's largest non-success outcome. A cheaper rendering relieves that
# pressure instead of trading the report away to relieve it.
#
# BAML's claim is 6% -> 0% failure on a small model. That is their number on their task; this arm
# exists to find ours, not to repeat theirs.
#
# An environment variable, not an edit, so harness_tree is identical to the control.
# shellcheck disable=SC1090
source "$(dirname "${BASH_SOURCE[0]}")/native.sh"

provider_name() { echo "nativetype"; }
export NATIVE_TYPEDEF=1
