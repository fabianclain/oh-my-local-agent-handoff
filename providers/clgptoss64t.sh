#!/usr/bin/env bash
#
# Bench label: clgptoss64t — gpt-oss 20B at 64k through Cline, reasoning 'medium'.
#
# 64k is the measured sweet spot for this model on a 16 GB card: the multi-file plan peaks around
# 36k of prompt, which a 32k window cannot hold, and 64k still loads 100% GPU-resident where 128k
# falls to 84% and costs roughly a third of throughput.
: "${HANDOFF_MODEL:=gptoss-64k}"
: "${HANDOFF_CLINE_THINKING:=medium}"
export HANDOFF_MODEL HANDOFF_CLINE_THINKING
# shellcheck disable=SC1090
source "$(dirname "${BASH_SOURCE[0]}")/cline.sh"
provider_name() { echo "clgptoss64t"; }
