#!/usr/bin/env bash
#
# Bench label: lcgptossnt — gpt-oss 20B served by llama.cpp, driven by Cline, reasoning off.
#
# Paired with its opposite so reasoning is the only variable. Under ollama that comparison was
# meaningless for this model: 2 of 3 runs died on malformed tool calls regardless of the setting,
# so any difference was buried in engine noise. On llama.cpp the tool-call path is clean, which is
# what makes the reasoning question measurable at all.
: "${HANDOFF_MODEL:=gpt-oss-20b}"
: "${HANDOFF_CLINE_THINKING:=none}"
export HANDOFF_MODEL HANDOFF_CLINE_THINKING
# shellcheck disable=SC1090
source "$(dirname "${BASH_SOURCE[0]}")/lcpp.sh"
provider_name() { echo "lcgptossnt"; }
