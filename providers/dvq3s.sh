#!/usr/bin/env bash
#
# Bench label: dv-q3s-32k. providers/ollama.sh with a different default model.
#
# bench/run keys results by provider name, so comparing local models needs distinct names. The
# context is baked into the ollama model itself (PARAMETER num_ctx) AND declared in opencode's
# entry — declaring it in only one place leaves ollama serving its 4096 default, which produces
# failures that look like the model lying about what it can see.
: "${HANDOFF_MODEL:=ollama/dv-q3s-16k}"
export HANDOFF_MODEL
# shellcheck disable=SC1090
source "$(dirname "${BASH_SOURCE[0]}")/ollama.sh"
provider_name() { echo "dvq3s"; }
