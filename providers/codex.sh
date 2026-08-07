#!/usr/bin/env bash
#
# Provider adapter: OpenAI Codex CLI.
#
# A provider is (binary, env block, capabilities) — not just a binary. Adapters expose the five
# functions below and nothing else; everything provider-agnostic lives in bin/handoff.
#
# Env overrides: HANDOFF_MODEL, HANDOFF_EFFORT, HANDOFF_SANDBOX

provider_name() { echo "codex"; }

# Declare what this provider supports natively. The driver degrades loudly when something is
# missing rather than silently producing a weaker guarantee that looks equivalent.
#
#   structured_output  native  — the model is forced to emit schema-valid JSON
#   session_resume     native  — a follow-up continues the same conversation
#   sandbox            native  — the OS restricts what the agent can touch
provider_capabilities() {
    cat <<'CAPS'
structured_output=native
session_resume=native
sandbox=native
CAPS
}

provider_preflight() {
    command -v codex >/dev/null 2>&1 || {
        echo "codex not found on PATH — see https://github.com/openai/codex" >&2
        return 1
    }
}

# Shared flags. Two of these exist because of specific, observed failures:
#
# --disable hooks: oh-my-codex hooks hijacked the end of two runs. Both finished their actual
#   work correctly, then spent their final turns on the harness's own session bookkeeping and
#   reported that instead — one lost its entire tests_run history and falsely claimed "blocked".
#
# sandbox_workspace_write.network_access: some test runners need a local listening socket
#   (pest-plugin-browser calls socket_create_listen after every test). Without this the suite
#   cannot start at all. The cost is real and must be stated: agents are no longer
#   network-isolated, so "do not change dependencies" becomes a rule the agent is asked to
#   follow rather than a boundary the OS enforces. Every round's diff must be checked for
#   dependency-manifest changes.
_codex_common_args() {
    local schema="$1" result="$2" dev_instructions="$3"
    printf '%s\n' \
        --model "${HANDOFF_MODEL:-gpt-5.6-sol}" \
        --output-schema "$schema" \
        --output-last-message "$result" \
        --disable hooks \
        -c "model_reasoning_effort=\"${HANDOFF_EFFORT:-high}\"" \
        -c "approval_policy=\"never\"" \
        -c "sandbox_mode=\"${HANDOFF_SANDBOX:-workspace-write}\"" \
        -c "sandbox_workspace_write.network_access=true" \
        -c "developer_instructions=\"$(printf '%s' "$dev_instructions" | sed 's/"/\\"/g')\""
}

# provider_run <repo_root> <schema> <result_file> <log_file> <dev_instructions> <prompt>
provider_run() {
    local root="$1" schema="$2" result="$3" log="$4" dev="$5" prompt="$6"
    local args=(); mapfile -t args < <(_codex_common_args "$schema" "$result" "$dev")
    codex exec "${args[@]}" \
        --cd "$root" --sandbox "${HANDOFF_SANDBOX:-workspace-write}" --color never \
        "$prompt" 2>&1 | tee "$log"
    return "${PIPESTATUS[0]}"
}

# provider_resume <session_id> <schema> <result_file> <log_file> <dev_instructions> <prompt>
#
# `codex exec resume` accepts a narrower flag set than `codex exec` — no --cd, --sandbox or
# --color — so anything unsupported there is passed as a -c config override instead.
provider_resume() {
    local session="$1" schema="$2" result="$3" log="$4" dev="$5" prompt="$6"
    local args=(); mapfile -t args < <(_codex_common_args "$schema" "$result" "$dev")
    codex exec resume "$session" "${args[@]}" "$prompt" 2>&1 | tee -a "$log"
    return "${PIPESTATUS[0]}"
}

# Pin the session so a later resume continues this exact conversation rather than whatever
# session happened to run most recently.
provider_parse_session_id() {
    grep -m1 -oE '^session id: [0-9a-f-]+' "$1" 2>/dev/null | awk '{print $3}'
}
