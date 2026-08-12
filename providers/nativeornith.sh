#!/usr/bin/env bash
#
# nativeornith — the native loop, driving ornith-9b instead of gpt-oss-20b.
#
# ornith:9b, pulled with `ollama pull ornith:9b` and served through llama.cpp rather than ollama,
# because ollama returns HTTP 500 for tool calls its own model generated and that is why every
# ollama-served result in this project is void.
#
# It passes the gate the Qwen family has always failed here: tools/engine-conformance reports
# 21 of 21 turns returning well-formed tool calls, 18 of them apply_patch. Its template uses the
# `<tool_call>` XML convention and llama.cpp maps it to real tool_calls.
#
# Speed, measured from llama-server's own timing records over 400-token generations: 47.0 tk/s,
# range 46.9-47.1. gpt-oss-20b runs near 60. That is the expected ordering rather than a fault —
# gpt-oss is a mixture of experts with roughly 3.6B active parameters per token against ornith's
# 9B dense, and generation tracks active parameters, not total.
#
# It is also far lighter: 8.8 GiB resident at 98304 against gpt-oss's 14.3, leaving 7 GiB free.
# shellcheck disable=SC1090
source "$(dirname "${BASH_SOURCE[0]}")/native.sh"

HANDOFF_MODEL=ornith-9b
export HANDOFF_MODEL
provider_name() { echo "nativeornith"; }
