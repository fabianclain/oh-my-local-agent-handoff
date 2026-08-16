#!/usr/bin/env bash
#
# nativelfm — the native loop against LFM2.5-8B-A1B instead of gpt-oss-20b.
#
# Hybrid convolution + attention MoE: 8.3B total, ~1.5B active per token, 128k context, served
# from LiquidAI's own Q8_0 GGUF through the same llama-server as gpt-oss.
#
# ONE VARIABLE. Same loop, same tools, same prompt layers, same engine, same harness commit. Only
# the weights differ. That is the whole reason this is a three-line overlay rather than a separate
# stack: every earlier attempt to compare models here also changed the engine, and every one of
# those results had to be thrown away.
#
# SAMPLING IS DELIBERATELY NOT CHANGED, and this is the one thing to know before reading a result.
# LiquidAI ships temperature 0.2 for this model; the harness runs 0.8 because that is what every
# gpt-oss number here was measured at. Matching keeps the comparison to one variable, at the cost
# of running LFM2.5 off its recommended profile. If it underperforms, a temperature 0.2 arm is the
# first follow-up and costs one more run -- do NOT read a poor result here as a verdict on the
# model until that has been tried.
#
# NOT COMBINABLE WITH nativeraw. parse_harmony reads gpt-oss's channel format; on non-harmony
# output it returns an empty message with no tool calls and no error, which would look exactly
# like a model that stopped talking. Measured, not assumed.
#
# provider_preflight refuses if llama-server is serving anything other than lfm2.5-8b, so the two
# arms cannot silently run against the same weights -- a 16 GB card holds one of these at a time
# and `llamacpp-serve start` stops whatever was running.
# shellcheck disable=SC1090
source "$(dirname "${BASH_SOURCE[0]}")/native.sh"

provider_name() { echo "nativelfm"; }
# After the source, deliberately: native.sh defaults HANDOFF_MODEL to gpt-oss-20b and this must win.
export HANDOFF_MODEL=lfm2.5-8b
