#!/usr/bin/env bash
#
# nativegrammar — nativersp, plus the grammar the specification says it needs.
#
# docs/format.md defines structured output as a `# Response Formats` section in the developer
# message, and is candid that the declaration alone is not enough:
#
#     This prompt alone will, however, only influence the model's behavior but doesn't guarantee
#     the full adherence to the schema. For this you still need to construct your own grammar and
#     enforce the schema during sampling.
#
# This project had only the enforcement half (providers/nativejson.sh, response_format on the chat
# path) and could not combine it with the harmony work, because response_format constrains the
# WHOLE completion and a harmony completion starts with a channel marker rather than a brace.
#
# It composes after all. llama.cpp's GBNF admits harmony's special tokens as literals, so the
# envelope goes INSIDE the constraint:
#
#     root ::= "<|channel|>final<|message|>" report "<|return|>"
#
# with `report` generated from schemas/handoff.schema.json by tools/schema_grammar.py. Measured on
# the real schema: 118 tokens, 2.5s, every required key, no extra keys, and status inside the enum
# -- where the same turn with a generic JSON grammar answered "completed", which the enum does not
# admit, and which is exactly the drift the extractor exists to survive.
#
# So this arm is BOTH halves of the mechanism the model was trained on: the format declared where
# it expects to read it, and the sampler unable to produce anything else.
#
# The converter refuses rather than approximates. oneOf, $ref, tuple items, optional properties,
# additionalProperties:true and any unknown type raise instead of emitting a grammar that permits
# what the schema forbids -- which would look like enforcement and be nothing of the kind.
# shellcheck disable=SC1090
source "$(dirname "${BASH_SOURCE[0]}")/native.sh"

provider_name() { echo "nativegrammar"; }
NATIVE_EXTRA_ARGS="${NATIVE_EXTRA_ARGS:-} --harmony-grammar --response-format-section --no-report-tool"
