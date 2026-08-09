#!/usr/bin/env bash
#
# Provider base: Cline driving a model served by llama.cpp rather than ollama.
#
# This exists because ollama corrupts gpt-oss tool calls. Same weights, same tool schema, same
# conversation, only the engine differing:
#
#   ollama      2/5 tool calls malformed, HTTP 500 "error parsing tool call"; 1/3 correct via Cline
#   llama.cpp   8/8 valid tool calls; 4/4 correct via Cline; ~74 tok/s against ~61
#
# Cline reaches llama.cpp through its `openai-compatible` provider. That path is not
# interchangeable with the ollama one — tested against ollama's own /v1 endpoint, gemma worked and
# both gpt-oss and qwen failed — so it is only used here, pointed at llama.cpp, where it is
# measured to work.
#
# Env overrides: HANDOFF_MODEL (the model id Cline was authed with), LLAMACPP_PORT,
#                HANDOFF_CLINE_THINKING

: "${HANDOFF_CLINE_PROVIDER:=openai-compatible}"
: "${HANDOFF_CLINE_CONFIG:=$HOME/.cline-llamacpp}"
export HANDOFF_CLINE_PROVIDER HANDOFF_CLINE_CONFIG

# shellcheck disable=SC1090
source "$(dirname "${BASH_SOURCE[0]}")/cline.sh"

provider_name() { echo "lcpp"; }

# The llama.cpp stack, pinned by digest rather than by name.
#
# The model file is hashed because a GGUF filename says nothing: two builds of "gpt-oss-20b"
# differ in architecture id, template and quantisation, and one of them will not even load here.
# Hashing 12 GB is slow, so the first 64 MB plus the size stands in — enough to distinguish builds,
# not a integrity check.
provider_manifest() {
    LLAMACPP_SERVER="${LLAMA_SERVER:-$HOME/.local/opt/llamacpp/llama-b10331/llama-server}" \
    LLAMACPP_MODEL_FILE="${GPTOSS_GGUF:-$HOME/.cache/agent-handoff/models/gpt-oss-20b-MXFP4.gguf}" \
    python3 -c '
import hashlib, json, os, subprocess, urllib.request

def cmd(*args):
    try:
        return subprocess.run(args, capture_output=True, text=True, timeout=10).stdout.strip()
    except Exception:
        return None

path = os.environ["LLAMACPP_MODEL_FILE"]
digest = size = None
try:
    size = os.path.getsize(path)
    with open(path, "rb") as handle:
        digest = "sha256:" + hashlib.sha256(handle.read(64 * 1024 * 1024)).hexdigest()[:32] + "/64MB"
except Exception:
    pass

props = None
try:
    port = os.environ.get("LLAMACPP_PORT", "8071")
    with urllib.request.urlopen(f"http://127.0.0.1:{port}/props", timeout=5) as response:
        data = json.loads(response.read())
    props = {"n_ctx": data.get("default_generation_settings", {}).get("n_ctx"),
             "model": os.path.basename(data.get("model_path", "") or "")}
except Exception:
    pass

print(json.dumps({
    "client": "cline",
    "client_version": cmd("cline", "--version"),
    "client_provider": os.environ.get("HANDOFF_CLINE_PROVIDER", "openai-compatible"),
    "model": os.environ.get("HANDOFF_MODEL"),
    "reasoning": os.environ.get("HANDOFF_CLINE_THINKING") or "(client default)",
    "engine": "llama.cpp",
    "engine_binary": os.path.basename(os.path.dirname(os.environ["LLAMACPP_SERVER"])),
    "model_file": os.path.basename(path),
    "model_bytes": size,
    "model_digest": digest,
    "server_props": props,
    "kv_type": "q8_0",
    "gpu_layers": "all",
}, indent=2))
'
}

_lcpp_cline_preflight() { :; }
eval "_lcpp_cline_preflight() { $(declare -f provider_preflight | tail -n +2) }"

# The inherited preflight checks for an ollama daemon, which is the wrong dependency here and
# would pass while the actual backend was down. Check llama-server instead, and check that it is
# serving the model this provider expects: one card holds one model, so a leftover server from a
# previous provider would silently benchmark the wrong weights.
provider_preflight() {
    command -v cline >/dev/null 2>&1 || {
        echo "cline not found on PATH — install with 'npm i -g cline'" >&2
        return 1
    }

    local config="${HANDOFF_CLINE_CONFIG}"
    [[ -f "$config/data/settings/providers.json" ]] || {
        echo "Cline has no provider configured at ${config}." >&2
        echo "Run: cline auth -p openai-compatible -m ${HANDOFF_MODEL:-<model>} \\" >&2
        echo "       -b http://127.0.0.1:${LLAMACPP_PORT:-8071}/v1 -k dummy --config ${config}" >&2
        return 1
    }

    local port="${LLAMACPP_PORT:-8071}"
    curl -fsS --max-time 5 "http://127.0.0.1:${port}/health" >/dev/null 2>&1 || {
        echo "No llama-server answering on :${port}." >&2
        echo "Start it with: tools/llamacpp-serve start ${HANDOFF_MODEL:-<model>}" >&2
        return 1
    }

    local serving="${LLAMACPP_STATE:-$HOME/.cache/agent-handoff}/llamacpp.model"
    if [[ -s "$serving" && -n "${HANDOFF_MODEL:-}" ]]; then
        local actual; actual="$(cat "$serving")"
        [[ "$actual" == "$HANDOFF_MODEL" ]] || {
            echo "llama-server is serving '${actual}', not '${HANDOFF_MODEL}'." >&2
            echo "Run: tools/llamacpp-serve start ${HANDOFF_MODEL}" >&2
            return 1
        }
    fi
}
