#!/usr/bin/env bash
#
# nativeraw — the native loop, generating through /completions and parsing harmony itself.
#
# llama.cpp discarded 99 of 3,131 completions overnight, 3.16%, and answered HTTP 500 with the text
# gone. 75 were a header the model garbled by one token; 18 were a `final` message carrying the
# completion report, tagged `<|constrain|>json`. Both are unambiguous to a reader and neither is
# admitted by the grammar.
#
# The prompt is still the server's: /apply-template renders exactly what /v1/chat/completions
# would build, so nothing here reimplements the template or can drift from it. Only the parsing is
# ours, and it is lenient in three specific ways taken from those failures.
#
# The retry it complements stays in place: this removes the fault, the retry covers what is left.
# shellcheck disable=SC1090
source "$(dirname "${BASH_SOURCE[0]}")/native.sh"

provider_name() { echo "nativeraw"; }
NATIVE_EXTRA_ARGS="${NATIVE_EXTRA_ARGS:-} --raw-harmony"
