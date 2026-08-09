#!/usr/bin/env bash
#
# Bench label: qw3c — Qwen3-Coder-30B-A3B-Instruct (unsloth Q2_K) at 32k, through the tool-call
# shim.
#
# This model does not reach opencode directly. Its GGUF ships a Qwen2.5-era chat template
# containing <tool_call> but neither <function=> nor <parameter=>, which is Qwen3-Coder's
# documented format — so the model is instructed in a format it was not trained to emit and falls
# back to bare JSON in `content`. opencode never executes that, and the model then reports,
# accurately, that it could not read the file. The block is packaging, not capability.
#
# tools/toolcall-shim.py promotes those text calls into native ones. It is a separate opencode
# provider ("ollamashim") pointing at the shim's port rather than ollama's, so a run through the
# shim and a run direct are distinguishable in the results rather than silently conflated.
#
# Preflight requires the shim to be answering. Without that check a shim that is not running
# fails deep inside the agent loop as a model that cannot read files — which is exactly the
# misattribution this whole provider exists to undo.

: "${HANDOFF_MODEL:=ollamashim/qw3c-32k}"
export HANDOFF_MODEL

# shellcheck disable=SC1090
source "$(dirname "${BASH_SOURCE[0]}")/opencode.sh"

provider_name() { echo "qw3c"; }

_qw3c_opencode_preflight() { :; }
eval "_qw3c_opencode_preflight() { $(declare -f provider_preflight | tail -n +2) }"

provider_preflight() {
    _qw3c_opencode_preflight || return 1

    local shim="${HANDOFF_SHIM_URL:-http://127.0.0.1:11500}"
    if ! curl -fsS --max-time 5 "${shim%/}/api/tags" >/dev/null 2>&1; then
        echo "No tool-call shim answering at ${shim}." >&2
        echo "Start it with: python3 tools/toolcall-shim.py" >&2
        echo "Without it this model emits tool calls as text and changes nothing, which looks" >&2
        echo "identical to incapacity. Refusing to run rather than record a harness fault as a" >&2
        echo "model result." >&2
        return 1
    fi

    if ! opencode models 2>/dev/null | grep -qx "$HANDOFF_MODEL"; then
        echo "opencode does not have '$HANDOFF_MODEL' registered." >&2
        echo "Add an 'ollamashim' provider whose baseURL is the shim's /api endpoint." >&2
        return 1
    fi
}
