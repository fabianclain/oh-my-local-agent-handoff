#!/usr/bin/env bash
#
# nativegemma4 — the native loop against gemma-4-12B-agentic-fable5-composer2.5-v2, Q8_0.
#
# One variable: same loop, tools, prompts, engine and harness commit as `native`; only the weights
# differ.
#
# THE FORMAT GATE is the reason this build is worth running at all. Its sibling
# `gemma-4-12B-coder-fable5` is one of four models this project rejected for emitting correct tool
# calls as TEXT rather than as tool_calls, while `gemma4:12b-128k` from the ollama library emits
# them natively. Same architecture, same family, opposite answers. Probed here before any round:
# native tool_calls, correct name and argument, in 46-53 tokens.
#
# SERVED AT 16384, not 98304. The weights are 12.67 GB on a card with ~14.4 GB usable, so the
# context is what is left over rather than what is wanted. The gpt-oss control ran at 98304. On
# `semantic`, whose rounds reach 4-9k, neither binds -- but it is a difference, and it is recorded
# here rather than discovered later.
#
# A RESIDENCY FALSE ALARM, recorded so it is not re-litigated. llamacpp-serve warned that the model
# was "at least partly in host memory" because llama-server held 2.2 GB of host RSS. It is not:
# llama.cpp mmaps the GGUF, and this one is read from ollama's blob store, so the page cache for
# the model file lands in RSS. Measured during sustained generation: GPU 94-96%, 70-74 W, and
# llama-server using 14% of a single CPU core. The heuristic is wrong for any ollama-blob model.
# shellcheck disable=SC1090
source "$(dirname "${BASH_SOURCE[0]}")/native.sh"

provider_name() { echo "nativegemma4"; }
export HANDOFF_MODEL=gemma4-agentic-12b
