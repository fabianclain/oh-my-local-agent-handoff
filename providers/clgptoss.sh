#!/usr/bin/env bash
#
# Bench label: clgptoss — gpt-oss 20B official at 32k driven through the Cline CLI.
#
# Pairs with providers/gptoss.sh, which is the same model through opencode. The two labels exist so a
# client comparison is visible in the results table rather than overwriting itself.
: "${HANDOFF_MODEL:=gptoss-32k}"
export HANDOFF_MODEL
# shellcheck disable=SC1090
source "$(dirname "${BASH_SOURCE[0]}")/cline.sh"
provider_name() { echo "clgptoss"; }
