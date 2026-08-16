#!/usr/bin/env bash
#
# nativecot — nativeharmony, plus the model's own chain of thought carried between tool calls.
#
# docs/format.md's worked example is explicit about this. Showing an analysis message, a tool call,
# the tool result and then the next assistant turn, it says: "we are passing not just the function
# output back into the model for further sampling but ALSO the previous chain-of-thought ... to
# provide the model with the necessary information to continue its chain-of-thought or provide the
# final answer."
#
# This harness has never done it. parse_harmony reads the analysis channel and the loop logs it,
# and then drops it: every turn started its reasoning from nothing, however carefully the previous
# turn had worked something out. That is a candidate cause for behaviour already measured here --
# rounds that re-read the same file, and the circling that tools/repeat-guard-selftest exists to
# detect at all.
#
# IT IS NOT FREE, which is why it is its own arm rather than folded into nativeharmony. Analysis is
# the bulk of what gpt-oss generates -- a round on `semantic` produces ~9.5k output tokens, most of
# it reasoning -- so carrying it grows the context it is meant to help. On a plan that already
# reaches 14-33k, that could cost more than it returns. The comparison against nativeharmony
# isolates exactly this: same renderer, same tools, same everything, one extra channel in context.
# shellcheck disable=SC1090
source "$(dirname "${BASH_SOURCE[0]}")/native.sh"

provider_name() { echo "nativecot"; }
NATIVE_EXTRA_ARGS="${NATIVE_EXTRA_ARGS:-} --harmony-render --carry-reasoning"
