#!/usr/bin/env bash
#
# nativeprune — native, replaces read results the model has since overwritten
#
# A three-line overlay on providers/native.sh, which is the practical point of owning the loop:
# a design question becomes an arm rather than a fork.
# shellcheck disable=SC1090
source "$(dirname "${BASH_SOURCE[0]}")/native.sh"

provider_name() { echo "nativeprune"; }
NATIVE_EXTRA_ARGS="${NATIVE_EXTRA_ARGS:-} --prune-superseded"
