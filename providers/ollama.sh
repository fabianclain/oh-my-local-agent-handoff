#!/usr/bin/env bash
#
# Provider adapter: local models served by Ollama, driven through opencode.
#
# This is providers/opencode.sh with a model default, and that is the whole point. A provider is
# (binary, env block, capabilities) — not one adapter per model. Any local model Ollama serves
# and opencode has registered can be used here by setting HANDOFF_MODEL; nothing below is
# Gemma-specific.
#
# Ollama on its own cannot implement a plan. It is an inference server: no file editing, no
# command execution, no agent loop. opencode supplies those and speaks to Ollama's endpoint, so
# the model must support **tool calling** or it will produce prose and change nothing. Check with
# `ollama show <model>` and look for `tools` under Capabilities before adding a model.
#
# Two limits worth knowing before you read the results:
#
#   1. A quantised local model in the 10-30B range is materially weaker at long multi-file plans
#      than a hosted frontier model. Expect more deviations, more missed acceptance criteria, and
#      more rounds. That is information, not failure — but do not read a bad round as proof the
#      plan was bad.
#   2. It inherits every opencode caveat: structured output is prompt-and-validate rather than
#      schema-enforced, and there is no sandbox. Read the diff by hand.
#
# The context window must be declared in opencode's model entry. Ollama will happily accept a
# model whose advertised ceiling is far larger than the KV cache your GPU can hold; the entry is
# where you keep it honest.

: "${HANDOFF_MODEL:=ollama/gemma4:12b-128k}"
export HANDOFF_MODEL

# shellcheck disable=SC1090
source "$(dirname "${BASH_SOURCE[0]}")/opencode.sh"

provider_name() { echo "ollama"; }

# This provider drives the one local model server on this machine, so rounds using it must be
# serialised. Two clients against one server interleave their lines in llamacpp.log, and the token
# accounting above brackets a round by BYTE OFFSET into that file -- so concurrent rounds do not
# merely contend for the GPU, they silently attribute each other's tokens. bin/handoff reads this
# flag to decide whether to take the GPU lock.
HANDOFF_USES_LOCAL_GPU=1


_ollama_opencode_preflight() { :; }
eval "_ollama_opencode_preflight() { $(declare -f provider_preflight | tail -n +2) }"

# Ollama's host is opencode's business, not ours — it lives in that model's provider entry in
# opencode.json. Preflight only proves the daemon answers, because the failure it prevents is a
# long, confusing timeout inside the agent loop rather than a clear error here.
provider_preflight() {
    _ollama_opencode_preflight || return 1

    local host="${OLLAMA_HOST:-http://127.0.0.1:11434}"
    if ! curl -fsS --max-time 5 "${host%/}/api/tags" >/dev/null 2>&1; then
        echo "No Ollama daemon answering at ${host} (set OLLAMA_HOST to point elsewhere)." >&2
        echo "Start it with 'ollama serve', or check the baseURL in the ollama provider entry" >&2
        echo "of ~/.config/opencode/opencode.json if opencode reaches it over the network." >&2
        return 1
    fi

    local model="${HANDOFF_MODEL#ollama/}"
    if ! opencode models 2>/dev/null | grep -qx "ollama/${model}"; then
        echo "opencode does not have 'ollama/${model}' registered." >&2
        echo "Add it under provider.ollama.models in ~/.config/opencode/opencode.json, with" >&2
        echo "\"tools\": true and an explicit context limit your hardware can actually hold." >&2
        return 1
    fi
}
