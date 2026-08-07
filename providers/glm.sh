#!/usr/bin/env bash
#
# Provider adapter: GLM via z.ai's Anthropic-compatible endpoint.
#
# This is providers/claude.sh with a different env block, and that is the whole point. A
# provider is (binary, env block, capabilities) — not one adapter per model. If this file ever
# needs to override a flag rather than an environment variable, the abstraction has leaked and
# the shared adapter should be fixed instead of forked here.
#
# Zhipu ships no headless coding CLI: ZCode is a desktop application. z.ai publishes an
# Anthropic-compatible endpoint precisely so an existing harness can drive GLM, which is the
# supported path rather than a workaround.
#
# Credentials are read from a file outside any repository. Never inline a key here — this file
# is published.

_glm_env_file="${HANDOFF_GLM_ENV:-$HOME/.config/agent-handoff/glm.env}"

if [[ -f "$_glm_env_file" ]]; then
    # shellcheck disable=SC1090
    set -a; source "$_glm_env_file"; set +a
fi

: "${ANTHROPIC_BASE_URL:=https://api.z.ai/api/anthropic}"
: "${ANTHROPIC_DEFAULT_OPUS_MODEL:=GLM-5.2}"
: "${ANTHROPIC_DEFAULT_SONNET_MODEL:=GLM-5.2}"
: "${ANTHROPIC_DEFAULT_HAIKU_MODEL:=GLM-4.7}"
export ANTHROPIC_BASE_URL ANTHROPIC_DEFAULT_OPUS_MODEL ANTHROPIC_DEFAULT_SONNET_MODEL ANTHROPIC_DEFAULT_HAIKU_MODEL

# shellcheck disable=SC1090
source "$(dirname "${BASH_SOURCE[0]}")/claude.sh"

provider_name() { echo "glm"; }

# Identical to the claude adapter: same binary, same flags, same guarantees. Only the model
# behind the endpoint differs.
_glm_claude_preflight() { :; }
eval "_glm_claude_preflight() { $(declare -f provider_preflight | tail -n +2) }"

provider_preflight() {
    _glm_claude_preflight || return 1
    if [[ -z "${ANTHROPIC_AUTH_TOKEN:-}" ]]; then
        echo "ANTHROPIC_AUTH_TOKEN is not set." >&2
        echo "Create a z.ai API key and put it in $_glm_env_file, or export it before running." >&2
        echo "Failing here rather than sending an unauthenticated request, which returns a" >&2
        echo "misleading error far from its cause." >&2
        return 1
    fi
}
