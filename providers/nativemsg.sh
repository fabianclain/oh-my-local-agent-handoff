#!/usr/bin/env bash
#
# Bench label: nativemsg — native, with no submit_report tool. The report can only come from the
# final no-tools turn.
#
# Isolates the report channel INSIDE the native loop, which no client could do: the fallback turn
# already removes the tools, so this asks whether offering the tool as well adds anything. Round 10
# measured the tool channel at 1/12 missing against 4/15 through Cline, but that confounded the
# channel with the client.
source "$(dirname "${BASH_SOURCE[0]}")/native.sh"
provider_name() { echo "nativemsg"; }
_nativemsg_run() { :; }
eval "_nativemsg_run() { $(declare -f provider_run | tail -n +2) }"
provider_run() { NATIVE_EXTRA_ARGS="--no-report-tool" _nativemsg_run "$@"; }
