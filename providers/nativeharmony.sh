#!/usr/bin/env bash
#
# nativeharmony — the native loop, with the prompt built by OpenAI's harmony renderer.
#
# llama.cpp renders the harmony format, and renders it lossily. Two divergences from the
# specification, both measured against openai-harmony on the same conversation:
#
#   TOOL TYPES        every nested object in a tool schema collapses to `any[]`, taking the field
#                     names and their descriptions with it. Four structures in the real tool set:
#                     read_files.files, and submit_report's files_changed, tests_run and
#                     deviations. The `start`/`end` window -- the change that turned three dead
#                     rounds into an accepted one -- is NOT in the type the model is shown. It
#                     survives only because it is spelled out in prose in the tool description.
#
#   TOOL RESULTS      are JSON-quoted. A file read arrives as "--- src/Invoice.php ---\n<?php\n..."
#                     -- one escaped string, ZERO real newlines, seven literal \n sequences in a
#                     seven-line file. The model has never seen the line structure of anything it
#                     was asked to edit. docs/format.md specifies the tool message as
#                     `<|message|>{output}<|end|>`, verbatim, and harmony's renderer passes it raw.
#
# That second one is the reason to run this arm first. Mis-anchored edits, damage to the line
# beside an insertion, and the difficulty locating a declaration that made tools/symbols necessary
# are all what you would expect from a model reading escaped strings instead of files.
#
# ONE VARIABLE, and it is "which renderer". The two prompts were diffed on an identical
# conversation and agree everywhere else: same system message, same channel rules, same current
# date, same instructions, same message order. The remaining difference is `<|constrain|>json` on
# the tool call, which llama.cpp emits and harmony does not, and which docs/format.md calls
# optional.
#
# Implies --raw-harmony: a prompt built here can only go to /completions, and
# /v1/chat/completions would rebuild it with the template this arm exists to replace. Parsing is
# already ours on that path.
#
# Needs openai-harmony, in the venv tools/install-harmony creates. It raises rather than falling
# back to the template: an arm that silently ran as the control would produce a full set of
# results and be recorded as having tested something it never tested.
# shellcheck disable=SC1090
source "$(dirname "${BASH_SOURCE[0]}")/native.sh"

provider_name() { echo "nativeharmony"; }
NATIVE_EXTRA_ARGS="${NATIVE_EXTRA_ARGS:-} --harmony-render"
