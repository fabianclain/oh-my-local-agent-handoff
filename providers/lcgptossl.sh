#!/usr/bin/env bash
#
# Bench label: lcgptossl — gpt-oss 20B via llama.cpp, reasoning at 'low'.
#
# The third point in the reasoning sweep, and the one the architecture argues for. The planner is a
# hosted model that has already done the thinking; the implementer's job is to execute a written
# specification, not to re-derive it.
#
# The measured case against 'medium' is not accuracy — both scored 9/9 — it is discipline. One
# medium run wrote its own verification scripts into .handoff/, three files the plan never named,
# and took 524s against a ~300s median. An implementer inventing its own acceptance checks is
# duplicating the planner's work and littering while it does so.
#
# 'low' rather than 'none' because gpt-oss is a harmony model whose tool calls live in a channel
# structure that reasoning participates in; leaving a little is cheaper than discovering that
# removing it entirely costs something subtle.
: "${HANDOFF_MODEL:=gpt-oss-20b}"
: "${HANDOFF_CLINE_THINKING:=low}"
export HANDOFF_MODEL HANDOFF_CLINE_THINKING
# shellcheck disable=SC1090
source "$(dirname "${BASH_SOURCE[0]}")/lcpp.sh"
provider_name() { echo "lcgptossl"; }
