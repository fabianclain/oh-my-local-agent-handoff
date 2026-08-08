#!/usr/bin/env bash
#
# Bench label: Qwen 2.5 Coder 14B, served locally by Ollama.
#
# This is providers/ollama.sh with a different default model. It exists because bench/run keys
# its results directory by provider name, so comparing two local models needs two names — not
# because Qwen needs different handling. For ordinary `handoff do` runs prefer
# `HANDOFF_MODEL=ollama/qwen2.5-coder:14b handoff do <slug>` with the ollama provider; reach for
# a file like this only when results must be labelled apart.
#
# Note this model advertises `tools` and `insert` but not `thinking`. Gemma 4, which does think,
# spent its reasoning inside the deliverable on the mechanical bench — worth watching whether the
# absence of a thinking mode helps or hurts here.

: "${HANDOFF_MODEL:=ollama/qwen2.5-coder:14b}"
export HANDOFF_MODEL

# shellcheck disable=SC1090
source "$(dirname "${BASH_SOURCE[0]}")/ollama.sh"

provider_name() { echo "qwen"; }
