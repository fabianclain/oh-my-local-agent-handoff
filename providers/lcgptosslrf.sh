#!/usr/bin/env bash
#
# Bench label: lcgptosslrf — gpt-oss 20B, llama.cpp, reasoning low. Identical to lcgptossl except
# that the completion report is requested as a FILE the model writes with its file tool, rather
# than as its final assistant message.
#
# The reason is mechanical. This model emits tool calls reliably — 14 of 14 well formed at the
# engine level, including a ~1 KB freeform payload after a 20 KB tool result — and final text
# unreliably: 33% to 40% of first attempts end with a reasoning block and a tool call and no text
# block at all. That is the largest non-success outcome measured here, and every instance is a
# correct patch discarded for want of an envelope. This routes the report through the channel that
# works.
#
# The report path sits under .handoff/runs, which every scope and litter gate already excludes, so
# writing it cannot be scored as a file the plan never named.
#
# Control: round 6's lcgptossl arm (n=15), where patch-ok-no-report was 4/15 and the underlying
# no-text-block rate was 5/15.
: "${HANDOFF_MODEL:=gpt-oss-20b}"
: "${HANDOFF_CLINE_THINKING:=low}"
export HANDOFF_MODEL HANDOFF_CLINE_THINKING
# shellcheck disable=SC1090
source "$(dirname "${BASH_SOURCE[0]}")/lcpp.sh"
provider_name() { echo "lcgptosslrf"; }

# Pinned in the adapter, not left to the environment, so the label cannot disagree with what ran.
provider_report_channel() { echo file; }
