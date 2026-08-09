#!/usr/bin/env bash
#
# Bench label: gptoss128 — gpt-oss 20B at 128k through opencode, deliberately over-subscribed.
#
# The offload experiment, run in the client where this model actually works. Paired against
# providers/gptoss.sh (same model, same client, 32k, 100% GPU) so residency is the only variable.
#
# It is here rather than under Cline because Cline cannot parse gpt-oss's tool calls: four of five
# Cline runs at 32k and the first at 128k died on "error parsing tool call" having written nothing,
# which would have swamped any residency effect. Under opencode the same model completed 4/5.
#
# Measured cost of the offload: 16%/84% CPU/GPU, and throughput falls from ~60 tok/s to ~43 tok/s.
# The open question this pair answers is whether the extra context buys enough reliability to be
# worth that, against a rule that says anything below 100% residency is unusable rather than slow.
: "${HANDOFF_MODEL:=ollama/gptoss-128k}"
export HANDOFF_MODEL
# shellcheck disable=SC1090
source "$(dirname "${BASH_SOURCE[0]}")/ollama.sh"
provider_name() { echo "gptoss128"; }
