#!/usr/bin/env bash
#
# Bench label: Devstral Small 2 24B, served locally by Ollama.
#
# providers/ollama.sh with a different default model. It exists because bench/run keys results by
# provider name, so comparing local models needs distinct names — not because Devstral needs
# different handling.
#
# Devstral is Mistral's agentic coding model: trained for tool-calling and multi-file edits
# rather than chat, which is the shape this harness actually needs. Gemma 4 12B, by contrast, is
# a general model that happens to expose tools. If the greenfield-only restriction that Gemma
# needs turns out to be unnecessary here, that is the reason to expect it.
#
# Fit warning: at 24B the Q4 weights are around 14 GB. On a 16 GB card with a display server and
# anything else resident, this will not fully offload to GPU with a large context. Check
# `ollama ps` for "100% GPU" — a partial offload still works but is dramatically slower, and a
# speed comparison against a fully-resident model is then meaningless. Size the context down
# (a derived model with PARAMETER num_ctx) rather than accepting a CPU spill.

: "${HANDOFF_MODEL:=ollama/dv-q3-16k}"
export HANDOFF_MODEL

# shellcheck disable=SC1090
source "$(dirname "${BASH_SOURCE[0]}")/ollama.sh"

provider_name() { echo "devstral"; }
