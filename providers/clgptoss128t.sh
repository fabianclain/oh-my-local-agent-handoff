#!/usr/bin/env bash
#
# Bench label: clgptoss128t — gpt-oss 20B at 128k (~84% GPU) through Cline with reasoning at 'medium'.
#
# Paired with providers/clgptoss128nt.sh, which is identical except for the reasoning level. Reasoning is
# worth isolating: at 32k, gemma with reasoning on exhausted the window and reported "maximum
# output token limit" three times while writing nothing, and the same model with reasoning off
# finished the surgical plan 7/7 in 95s. Whether that was the reasoning or the small window is
# exactly what a 128k pair answers.
: "${HANDOFF_MODEL:=gptoss-128k}"
: "${HANDOFF_CLINE_THINKING:=medium}"
export HANDOFF_MODEL HANDOFF_CLINE_THINKING
# shellcheck disable=SC1090
source "$(dirname "${BASH_SOURCE[0]}")/cline.sh"
provider_name() { echo "clgptoss128t"; }
