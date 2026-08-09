#!/usr/bin/env bash
#
# Bench label: clqwen — Qwen3-Coder-30B-A3B Q2_K at 32k, no shim driven through the Cline CLI.
#
# Pairs with providers/qw3c.sh, which is the same model through opencode. The two labels exist so a
# client comparison is visible in the results table rather than overwriting itself.
: "${HANDOFF_MODEL:=qw3c-32k}"
export HANDOFF_MODEL
# shellcheck disable=SC1090
source "$(dirname "${BASH_SOURCE[0]}")/cline.sh"
provider_name() { echo "clqwen"; }
