#!/usr/bin/env bash
#
# Bench label: lcgptosslfull — identical to lcgptossl in every respect except that repair attempts
# are given the richer feedback (BENCH_FEEDBACK_DETAIL=full): the harness's captured output for
# each failing command, and the diff of what the previous attempts actually changed.
#
# It exists as its own adapter rather than as an environment variable on an existing one so that
# the condition is recorded in the results path, and it pins the level itself so the label cannot
# disagree with the behaviour it names. Configuration that lives only in the shell that launched a
# round cannot be recovered from the artifacts afterwards.
#
# Its control is lcgptossl on the same plan, same model, same reasoning level.
: "${HANDOFF_MODEL:=gpt-oss-20b}"
: "${HANDOFF_CLINE_THINKING:=low}"
export HANDOFF_MODEL HANDOFF_CLINE_THINKING
# shellcheck disable=SC1090
source "$(dirname "${BASH_SOURCE[0]}")/lcpp.sh"
provider_name() { echo "lcgptosslfull"; }

# The pin. bench/run prefers this over BENCH_FEEDBACK_DETAIL, so forgetting the environment
# variable cannot silently turn this arm into a duplicate of its own control.
provider_feedback_detail() { echo full; }
