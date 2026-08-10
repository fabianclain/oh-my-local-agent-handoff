#!/usr/bin/env bash
#
# stub — a provider that runs no model.
#
# Exists so the harness can be tested against itself: the repair loop, the feedback renderer and
# the outcome taxonomy are all harness behaviour, and testing them through a real model would make
# every assertion depend on a 20B parameter coin flip.
#
# It records the prompt it was handed, applies whatever STUB_PATCH says, and writes the report
# named by STUB_REPORT. Nothing here touches the GPU.

provider_preflight() { return 0; }

provider_manifest() { printf '{"provider":"stub"}\n'; }

# provider_run <repo_root> <schema> <result_file> <log_file> <dev_instructions> <prompt>
provider_run() {
    local repo_root="$1" result_file="$3" log_file="$4" prompt="$6"

    printf '%s' "$prompt" >>"${STUB_PROMPT_LOG:-/dev/null}"
    printf 'stub provider: prompt of %s bytes\n' "${#prompt}" >>"$log_file"

    # The ladder gives the stub two roles: implementer, and planner during an escalation. They
    # need different behaviour, and testing the ladder against one script that cannot tell them
    # apart would only ever exercise half of it.
    local patch="${STUB_PATCH:-}"
    [[ "${HANDOFF_ROLE:-}" != planner ]] || patch="${STUB_PLANNER_PATCH:-}"
    if [[ -n "$patch" ]]; then
        ( cd "$repo_root" && eval "$patch" ) >>"$log_file" 2>&1
    fi
    printf '%s\n' "${STUB_REPORT:-}" >"$result_file"
}

# Session support, opt-in via STUB_SESSION=1.
#
# Off by default because most real providers here have none — Cline's `--id` is incompatible with
# `--json` in 3.0.52 — and the driver must refuse to resume for those rather than running nothing
# and verifying the untouched tree. Both halves need testing, so the stub can be either.
if [[ -n "${STUB_SESSION:-}" ]]; then
    # provider_resume <session_id> <schema> <result_file> <log_file> <dev_instructions> <prompt>
    provider_resume() {
        local session="$1" result_file="$3" log_file="$4" prompt="$6"
        printf '%s' "$prompt" >>"${STUB_PROMPT_LOG:-/dev/null}"
        printf 'stub provider: resumed session %s\n' "$session" >>"$log_file"
        if [[ -n "${STUB_RESUME_PATCH:-${STUB_PATCH:-}}" ]]; then
            ( cd "$(git rev-parse --show-toplevel)" && eval "${STUB_RESUME_PATCH:-$STUB_PATCH}" ) \
                >>"$log_file" 2>&1
        fi
        printf '%s\n' "${STUB_REPORT:-}" >"$result_file"
    }
    provider_parse_session_id() { echo "stub-session"; }
fi

# Token accounting hooks, so tools/harness-selftest can check that bench/run sums usage across
# attempts rather than recording only the last one. The numbers are whatever STUB_USAGE says.
provider_usage_mark() { echo 0; }

provider_usage_since() {
    [[ -n "${STUB_USAGE:-}" ]] || return 0
    printf '%s\n' "$STUB_USAGE"
}
