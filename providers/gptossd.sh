#!/usr/bin/env bash
#
# Bench label: gptossd — gpt-oss 20B Coding-Distill Q3_K_M, repackaged with the official harmony template at 32k.
#
# The GGUF as published is unusable: its chat template renders the user turn as `tart|>user` --
# the leading `<|s` is missing -- and ollama derives stop strings from that template, so the stop
# list contains `<|message|>` and generation halts after three tokens. Rebuilt from the raw blob
# with gpt-oss:20b's template, because `PARAMETER stop` appends and a model derived FROM the
# ollama model inherits the broken list.
: "${HANDOFF_MODEL:=ollama/gptossd-32k}"
export HANDOFF_MODEL
# shellcheck disable=SC1090
source "$(dirname "${BASH_SOURCE[0]}")/ollama.sh"
provider_name() { echo "gptossd"; }
