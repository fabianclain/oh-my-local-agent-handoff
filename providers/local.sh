#!/usr/bin/env bash
#
# Provider: local — the recommended local implementer, under a name you do not have to decode.
#
#   HANDOFF_PROVIDER=local handoff do <slug>
#
# This is the configuration that measured best, and every part of it is a decision with evidence
# behind it rather than a default someone happened to pick:
#
#   gpt-oss-20b        the only model measured properly under the current harness. 29 of 30 runs
#                      met every acceptance criterion on a six-file task
#   llama.cpp          not ollama. Same weights, same tool schema: ollama returns HTTP 500 for
#                      tool calls its own model generated, and every result taken through it had
#                      to be thrown away
#   Cline              drives its own tool loop, and reaches llama.cpp through `openai-compatible`
#   reasoning `low`    against `off`, 15 runs each: quality indistinguishable (p >= 0.70) and every
#                      cost estimate favours `low`. Chosen because nothing points away from it
#   64k context        the largest window that keeps this model fully GPU-resident on 16 GB. One
#                      run in fifteen still exceeded it, so treat it as a limit, not headroom
#
# `providers/lcgptossl.sh` is the same configuration under its benchmark label. This one exists so
# day-to-day use does not require reading a naming scheme; that one exists so results stay
# traceable to the arm that produced them. Keep both, and change them together.
#
# Set up the stack with: tools/setup-local-implementer
: "${HANDOFF_MODEL:=gpt-oss-20b}"
: "${HANDOFF_CLINE_THINKING:=low}"
export HANDOFF_MODEL HANDOFF_CLINE_THINKING
# shellcheck disable=SC1090
source "$(dirname "${BASH_SOURCE[0]}")/lcpp.sh"
provider_name() { echo "local"; }
