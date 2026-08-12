#!/usr/bin/env bash
#
# nativelean — native, all three of tonight's context changes together
#
# A three-line overlay on providers/native.sh, which is the practical point of owning the loop:
# a design question becomes an arm rather than a fork.
# shellcheck disable=SC1090
source "$(dirname "${BASH_SOURCE[0]}")/native.sh"

provider_name() { echo "nativelean"; }
NATIVE_EXTRA_ARGS="${NATIVE_EXTRA_ARGS:-} --prune-superseded --report-tool-max-depth 10000 --max-syntax-warnings 3"
