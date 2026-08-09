#!/usr/bin/env bash
#
# Bench label: clgptossnt — the clgptoss configuration with reasoning switched off.
#
# The paired label exists to vary exactly one thing. Cline's ollama path reported hitting an
# output-token limit mid-write, and reasoning is the obvious competitor for that budget; running
# the same model, plan and client with --thinking none is what distinguishes "the cap is consumed
# by reasoning" from "the cap is simply too small".
: "${HANDOFF_MODEL:=gptoss-32k}"
: "${HANDOFF_CLINE_THINKING:=none}"
export HANDOFF_MODEL HANDOFF_CLINE_THINKING
# shellcheck disable=SC1090
source "$(dirname "${BASH_SOURCE[0]}")/cline.sh"
provider_name() { echo "clgptossnt"; }
