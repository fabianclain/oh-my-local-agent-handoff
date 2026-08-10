#!/usr/bin/env bash
#
# Bench label: lcgptossltool — gpt-oss 20B, llama.cpp, reasoning low. Identical to lcgptossl except
# that the completion report arrives as an MCP TOOL CALL whose input schema is the report schema,
# rather than as the model's final assistant message.
#
# The reasoning is mechanical, and it is the sharpest form of an idea that went through two weaker
# versions first. The largest non-success outcome measured here is a correct patch with no report —
# roughly one run in three — and the cause is not bad JSON. It is the model ending its turn having
# emitted reasoning and a tool call and no text block at all. The same model emits tool calls
# reliably: 14 of 14 well formed at the engine level.
#
#   message  the report is free text the model must remember to emit      <- the failure
#   file     transport moves onto the tool path, payload is still free text
#   tool     the schema IS the tool's inputSchema, so arguments are structured by construction
#
# Requires the MCP server registered in its own Cline config:
#
#   cline auth -p openai-compatible -m gpt-oss-20b -b http://127.0.0.1:8071/v1 -k dummy \
#       --config ~/.cline-llamacpp-mcp
#   # then write cline_mcp_settings.json pointing at tools/handoff-report-mcp
#   #   (cline mcp install does not accept --config, so the file is written directly)
#
# Control: round 6's lcgptossl arm (n=15), patch-ok-no-report 4/15, no-text-block 5/15.
: "${HANDOFF_MODEL:=gpt-oss-20b}"
: "${HANDOFF_CLINE_THINKING:=low}"
: "${HANDOFF_CLINE_CONFIG:=$HOME/.cline-llamacpp-mcp}"
export HANDOFF_MODEL HANDOFF_CLINE_THINKING HANDOFF_CLINE_CONFIG
# shellcheck disable=SC1090
source "$(dirname "${BASH_SOURCE[0]}")/lcpp.sh"
provider_name() { echo "lcgptossltool"; }

# Pinned in the adapter so the label cannot disagree with what ran.
provider_report_channel() { echo tool; }

# The MCP server must be registered in this config, or the tool silently does not exist and the
# model falls back to prose — which is the exact failure being measured against.
_lcgptossltool_base_preflight() { :; }
eval "_lcgptossltool_base_preflight() { $(declare -f provider_preflight | tail -n +2) }"

provider_preflight() {
    _lcgptossltool_base_preflight || return 1
    local settings="$HANDOFF_CLINE_CONFIG/data/settings/cline_mcp_settings.json"
    grep -q handoff-report "$settings" 2>/dev/null || {
        echo "the handoff-report MCP server is not registered in $HANDOFF_CLINE_CONFIG" >&2
        echo "Without it the tool does not exist and the model answers in prose instead." >&2
        return 1
    }
}
