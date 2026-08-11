#!/usr/bin/env bash
#
# Bench label: nativewhole — native, minus replace_in_file. Every edit becomes a whole-file write.
#
# This is round 15 from docs/BENCHMARK-QUEUE.md, which sat unrunnable for months because it needed
# a client that would offer a different tool set. It is now a flag.
#
# The question: does rewriting a file wholesale eliminate mis-anchored partial edits, or does it
# trade them for truncation? The patch-only gate exists because a 421-line service came back as an
# 11-line fragment, so the tension is real and has never been measured on the same plan.
source "$(dirname "${BASH_SOURCE[0]}")/native.sh"
provider_name() { echo "nativewhole"; }
_nativewhole_run() { :; }
eval "_nativewhole_run() { $(declare -f provider_run | tail -n +2) }"
provider_run() { NATIVE_EXTRA_ARGS="--no-replace" _nativewhole_run "$@"; }
