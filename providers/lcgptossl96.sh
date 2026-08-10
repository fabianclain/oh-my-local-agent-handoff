#!/usr/bin/env bash
#
# Bench label: lcgptossl96 — gpt-oss 20B, llama.cpp, reasoning low, served at a 96k context window
# instead of 64k. Identical to lcgptossl in every other respect.
#
# 64k was chosen as "the largest window that stays 100% GPU-resident", and that rule has since been
# retracted: gpt-oss at 84% residency produced a byte-perfect patch in 60s, so partial offload is a
# throughput tax rather than a cliff. Meanwhile 64k is measurably at its edge — two runs have now
# filled the window and silently lost history, and one of them was its arm's only damaged result.
#
# So the question is whether the headroom is worth the throughput. Expect this arm to be slower per
# token; what matters is whether it is cheaper per usable patch.
#
# Context is a server setting, so this adapter cannot impose it and asserts it instead.
: "${HANDOFF_MODEL:=gpt-oss-20b}"
: "${HANDOFF_CLINE_THINKING:=low}"
export HANDOFF_MODEL HANDOFF_CLINE_THINKING
# shellcheck disable=SC1090
source "$(dirname "${BASH_SOURCE[0]}")/lcpp.sh"
provider_name() { echo "lcgptossl96"; }

_lcgptossl96_base_preflight() { :; }
eval "_lcgptossl96_base_preflight() { $(declare -f provider_preflight | tail -n +2) }"

provider_preflight() {
    _lcgptossl96_base_preflight || return 1
    local port="${LLAMACPP_PORT:-8071}" n_ctx
    n_ctx="$(curl -fsS --max-time 5 "http://127.0.0.1:${port}/props" 2>/dev/null |
        python3 -c 'import json,sys; print(json.load(sys.stdin)["default_generation_settings"]["n_ctx"])' 2>/dev/null)"
    [[ -n "$n_ctx" ]] || { echo "could not read n_ctx from llama-server" >&2; return 1; }
    [[ "$n_ctx" -ge 98304 ]] || {
        echo "this provider requires a 96k window; the server is at n_ctx=${n_ctx}." >&2
        echo "Start it with: tools/llamacpp-serve start gpt-oss-20b 98304" >&2
        return 1
    }
}
