#!/usr/bin/env bash
#
# Bench label: clgptoss128nt — gpt-oss 20B at 128k through Cline, reasoning off.
#
# Deliberately over-subscribed. At 128k this build sits at roughly 83% GPU / 17% CPU, which the
# project's own rule calls unusable: a 15% offload once cost 101 minutes and zero files written.
# The counter-argument is that the failure actually diagnosed under Cline was context exhaustion,
# so trading residency for context attacks the real cause. Paired against clgptossnt, which is the
# same model and client at 32k and 100% resident, so residency is the only variable.
#
# Throughput is recorded separately by tools/ollama-ctx-proxy.py: wall-clock alone cannot separate
# "slower per token" from "needed more turns", and that distinction is the whole question here.
: "${HANDOFF_MODEL:=gptoss-128k}"
: "${HANDOFF_CLINE_THINKING:=none}"
export HANDOFF_MODEL HANDOFF_CLINE_THINKING
# shellcheck disable=SC1090
source "$(dirname "${BASH_SOURCE[0]}")/cline.sh"
provider_name() { echo "clgptoss128nt"; }
