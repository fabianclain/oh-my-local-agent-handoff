#!/usr/bin/env bash
#
# Bench label: clgemma — Gemma 4 12B at 96k driven through the Cline CLI.
#
# Pairs with providers/gemma.sh, which is the same model through opencode. The two labels exist so a
# client comparison is visible in the results table rather than overwriting itself.
: "${HANDOFF_MODEL:=gem-96k}"
export HANDOFF_MODEL
# shellcheck disable=SC1090
source "$(dirname "${BASH_SOURCE[0]}")/cline.sh"
provider_name() { echo "clgemma"; }
