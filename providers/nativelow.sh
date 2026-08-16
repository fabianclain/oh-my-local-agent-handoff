#!/usr/bin/env bash
#
# nativelow — nativegrammar at `Reasoning: low`.
#
# Everything the harmony work produced, in one arm: OpenAI's renderer, the report declared in the
# developer message, a GBNF built from the schema, and the reasoning level set deliberately rather
# than inherited.
#
# WHAT IS KNOWN ABOUT `low`, precisely. This project measured `low` against `off` -- 15 runs each,
# a reviewable patch 14 times in 15 both ways, every difference inside chance at p >= 0.70. It has
# NEVER measured low against MEDIUM, and medium is what llama.cpp's template emits and therefore
# what every result in this repository was produced under. So this arm varies something real that
# has not been varied before, and "low is faster" is a reasonable expectation rather than a finding.
# shellcheck disable=SC1090
source "$(dirname "${BASH_SOURCE[0]}")/native.sh"

provider_name() { echo "nativelow"; }
NATIVE_EXTRA_ARGS="${NATIVE_EXTRA_ARGS:-} --harmony-grammar --response-format-section --no-report-tool --reasoning-effort low"
