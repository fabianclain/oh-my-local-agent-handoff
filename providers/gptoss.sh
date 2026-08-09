#!/usr/bin/env bash
#
# Bench label: gptoss — gpt-oss 20B, ollama's own build, at 32k.
#
# The control for gptossd: same architecture and size, correctly packaged, so a difference between
# the two is attributable to the Coding-Distill fine-tune rather than to packaging.
: "${HANDOFF_MODEL:=ollama/gptoss-32k}"
export HANDOFF_MODEL
# shellcheck disable=SC1090
source "$(dirname "${BASH_SOURCE[0]}")/ollama.sh"
provider_name() { echo "gptoss"; }
