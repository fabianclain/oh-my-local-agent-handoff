#!/usr/bin/env bash
#
# nativeqwen35 — the native loop against Qwen3.5-9B-Claude-Code, Q8_0.
#
# One variable: same loop, tools, prompts, engine and harness commit as `native`; only the weights
# differ.
#
# THE FORMAT GATE, which this build was expected to fail. Its model card states it "calls tools
# with XML-style <tool_call> blocks", which is the exact shape that got qwen2.5-coder,
# Qwen3-Coder-30B-A3B, JanusCoder-14B and gemma-4-12B-coder-fable5 rejected here -- correct calls
# emitted as TEXT, never executed, with one of them recorded twice as fabricating a blocker when
# it was telling the truth.
#
# It passes. Probed before any round: native tool_calls, correct name and argument, 56 tokens, 3.0s.
#
# The difference is the ENGINE, not the model. Those four were probed at ollama's API; llama.cpp
# with --jinja carries format-specific parsers and promotes this build's XML into tool_calls. That
# is gate 0 in docs/local-models.md -- "know which engine served it before concluding anything
# about a local model" -- and it is the reason a card describing XML tool calls is not, by itself,
# a rejection.
#
# SERVED AT 49152. 8.9 GB of weights leaves ~5.4 GB for KV. That headroom is the thing
# gemma4-agentic did not have at 12.67 GB, where two rounds of three overflowed a 16384 window and
# were scored as model failures until bench/compare called them configuration results.
# shellcheck disable=SC1090
source "$(dirname "${BASH_SOURCE[0]}")/native.sh"

provider_name() { echo "nativeqwen35"; }
export HANDOFF_MODEL=qwen35-cc-9b
