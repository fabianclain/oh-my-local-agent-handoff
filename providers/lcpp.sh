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

# This provider drives the one local model server on this machine, so rounds using it must be
# serialised. Two clients against one server interleave their lines in llamacpp.log, and the token
# accounting above brackets a round by BYTE OFFSET into that file -- so concurrent rounds do not
# merely contend for the GPU, they silently attribute each other's tokens. bin/handoff reads this
# flag to decide whether to take the GPU lock.
HANDOFF_USES_LOCAL_GPU=1


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

# Token accounting, read from llama-server's own timing records.
#
# Wall clock alone cannot say *why* one configuration is slower, and for the reasoning sweep that
# is the whole question: a model that thinks less should generate fewer tokens, and generated
# tokens are a far quieter measurement than seconds. Five runs of wall clock did not separate
# reasoning `low` from `off`; token counts measure the same claim without the noise of prompt
# cache hits, disk, and the client's own latency.
#
# The mark is a byte offset into the server log, and the count is taken over the region appended
# between two marks. That attribution is only sound because exactly one benchmark runs at a time
# on this machine — which the bench lock enforces. A second client talking to the same server
# would be counted into whichever run happened to be open.
_lcpp_log_path() { echo "${LLAMACPP_STATE:-$HOME/.cache/agent-handoff}/llamacpp.log"; }

provider_usage_mark() {
    local log; log="$(_lcpp_log_path)"
    [[ -f "$log" ]] && wc -c <"$log" | tr -d ' ' || echo 0
}

provider_usage_since() {
    local log mark
    log="$(_lcpp_log_path)"
    mark="${1:-0}"
    [[ -f "$log" ]] || return 0
    LCPP_LOG="$log" LCPP_MARK="$mark" python3 -c '
import os, re, sys

path, mark = os.environ["LCPP_LOG"], int(os.environ["LCPP_MARK"] or 0)
size = os.path.getsize(path)
# A log that shrank was rotated or the server restarted mid-round; the offset no longer refers to
# the region it was taken in, and a silently wrong token count is worse than none.
if size < mark:
    print("usage_tokens_unattributable=1")
    sys.exit(0)

prompt_re = re.compile(r"prompt eval time =\s*[\d.]+ ms /\s*(\d+) tokens")
gen_re = re.compile(r"\|\s+eval time =\s*[\d.]+ ms /\s*(\d+) tokens")
# A request that filled the window and lost history, and one the server refused outright. Both are
# configuration results rather than model results, and both were invisible until someone read this
# log by hand: one run of round 6 was truncated at 65535 tokens and scored as though it had its
# whole conversation.
truncated_re = re.compile(r"truncated = 1")
overflow_re = re.compile(r"exceeds the available context size")
prompt_tokens = gen_tokens = requests = truncated = overflowed = 0
with open(path, "rb") as handle:
    handle.seek(mark)
    for raw in handle.read().decode("utf-8", "replace").splitlines():
        if truncated_re.search(raw):
            truncated += 1
        if overflow_re.search(raw):
            overflowed += 1
        found = prompt_re.search(raw)
        if found:
            prompt_tokens += int(found.group(1))
            requests += 1
            continue
        found = gen_re.search(raw)
        if found:
            gen_tokens += int(found.group(1))

print(f"prompt_tokens={prompt_tokens}")
print(f"generated_tokens={gen_tokens}")
print(f"model_requests={requests}")
print(f"truncated_requests={truncated}")
print(f"context_overflows={overflowed}")
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
