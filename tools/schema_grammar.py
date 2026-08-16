"""schema_grammar — a GBNF grammar from a JSON Schema, and a refusal when it cannot make one.

WHY THIS EXISTS

llama.cpp will build a grammar from a JSON Schema itself, but only for the WHOLE completion. On the
raw harmony path a completion does not start with `{` -- it starts with `<|channel|>`, and a schema
grammar applied there forces a brace where the format needs a channel marker. That is why
native-agent refuses to combine nativejson with nativeraw.

Measured first, then built: llama.cpp's GBNF admits harmony's special tokens as ordinary literals.
Given the grammar

    root ::= "<|channel|>final<|message|>" object "<|return|>"

gpt-oss produced exactly that shape in 24 tokens. So the two CAN compose, with a grammar that wraps
the schema in the harmony envelope instead of replacing it.

A generic JSON object grammar is not enough, and the same probe showed why: it answered
`{"status":"completed"}` where the enum admits only `complete`. That is the drift the extractor
exists to survive, and the reason to derive the grammar from the schema rather than from the shape
of JSON.

WHAT IT REFUSES

Only the constructs schemas/handoff.schema.json actually uses are implemented. Anything else --
oneOf, anyOf, $ref, patternProperties, tuple `items`, numeric bounds -- raises. That is the point:
a converter that silently ignored a keyword would emit a grammar PERMITTING what the schema
forbids, and the caller would believe the output was validated when it was not. An unsupported
construct is "I cannot build this", never "here is a grammar that mostly works".

`additionalProperties: false` is assumed and enforced by construction: only declared properties can
appear. A schema that sets it true would be admitting keys this grammar rejects, so that is refused
too rather than quietly narrowed.
"""

from __future__ import annotations

import json
import re


class Unsupported(Exception):
    """The schema uses something this converter does not implement.

    Raised rather than approximated. See the module docstring: a grammar that is wrong in the
    permissive direction is worse than no grammar, because it looks like enforcement.
    """


# The primitives, shared by every generated grammar. `string` follows RFC 8259 minus \\u escapes,
# which nothing in this project's schemas uses and which would be admitted silently if included.
PRIMITIVES = r'''
ws       ::= [ \t\n]*
string   ::= "\"" ([^"\\] | "\\" ["\\/bfnrt])* "\""
integer  ::= "-"? ("0" | [1-9] [0-9]*)
number   ::= "-"? ("0" | [1-9] [0-9]*) ("." [0-9]+)? ([eE] [-+]? [0-9]+)?
boolean  ::= "true" | "false"
'''.strip()


def _safe(part: str) -> str:
    """A rule-name fragment GBNF will accept.

    llama.cpp's grammar parser takes [a-zA-Z0-9-] in rule names and rejects UNDERSCORES, which
    `files_changed`, `tests_run` and `follow_ups` all contain. The server's only complaint is
    "failed to parse grammar" with no position, so this was found by bisecting a five-line grammar
    rather than from the error.
    """
    return "".join(c if (c.isalnum() or c == "-") else "-" for c in part)


def _name(path: list[str], root: str) -> str:
    """The rule name for this position. The empty path is the caller's chosen root name.

    It used to return the literal "root" regardless, so wrapping the schema under another name
    emitted `report ::= root` beside a second `root ::= "{" ...` -- a circular rule and a duplicate
    definition. Caught by reading the generated grammar rather than by anything failing, since a
    grammar is only rejected when the server tries to compile it.
    """
    return "-".join(_safe(p) for p in path) if path else root


def _rule(schema: dict, path: list[str], rules: dict[str, str], root: str = "root") -> str:
    """Emit rules for `schema`, returning the name of the one that matches it."""
    if not isinstance(schema, dict):
        raise Unsupported(f"{_name(path, root)}: not an object")

    for keyword in ("oneOf", "anyOf", "allOf", "$ref", "patternProperties", "not"):
        if keyword in schema:
            raise Unsupported(f"{_name(path, root)}: `{keyword}` is not implemented")

    if "enum" in schema:
        values = schema["enum"]
        if not values or not all(isinstance(v, str) for v in values):
            raise Unsupported(f"{_name(path, root)}: only non-empty string enums are implemented")
        rule = _name(path, root) + "-enum"
        # The GBNF literal must contain the JSON text INCLUDING its quotes, so the inner quotes
        # are escaped for the grammar: enum "complete" becomes the literal "\"complete\"".
        rules[rule] = " | ".join('"' + json.dumps(v).replace('"', '\\"') + '"' for v in values)
        return rule

    kind = schema.get("type")

    if kind == "object" or "properties" in schema:
        if schema.get("additionalProperties", False) is not False:
            raise Unsupported(
                f"{_name(path, root)}: additionalProperties must be false; a grammar cannot admit "
                "keys it was never shown")
        properties = schema.get("properties") or {}
        if not properties:
            raise Unsupported(f"{_name(path, root)}: an object with no properties")
        required = list(schema.get("required") or [])
        unknown = [r for r in required if r not in properties]
        if unknown:
            raise Unsupported(f"{_name(path, root)}: required names no such property: {unknown}")
        # OPTIONAL PROPERTIES, which the first version refused as combinatorial. They are not,
        # because this grammar already fixes key ORDER: with the required members emitted first and
        # each optional one wrapped as `( "," key ":" value )?` in a fixed sequence, every admissible
        # document is matched and no subset needs enumerating. The refusal was correct about not
        # approximating and wrong about the cost, and it fired on the first real schema this saw
        # that was not the one it was written against.
        #
        # An all-optional object is still refused: the leading comma has nothing to attach to, and
        # getting that wrong yields a grammar that accepts `{,"a":1}`.
        optional = [k for k in properties if k not in required]

        def member(key: str) -> str:
            child = _rule(properties[key], path + [key], rules, root)
            literal = '"' + json.dumps(key).replace('"', '\\"') + '"'
            return f'{literal} ws ":" ws {child}'

        if optional and not required:
            # Every member optional, so the comma cannot be attached to a fixed head. Still not
            # combinatorial: key ORDER is fixed, so one alternative per possible FIRST member --
            # each carrying the rest as optional tails -- matches every admissible document in n
            # rules rather than 2^n. The first attempt refused this case outright; refusing was
            # right about not approximating and wrong that there was no cheap construction.
            alternatives = []
            for index, key in enumerate(optional):
                tail = "".join(f' (ws "," ws {member(later)})?' for later in optional[index + 1:])
                alternatives.append(f"({member(key)}{tail})")
            rule = _name(path, root)
            if rule in rules:
                raise Unsupported(f"rule name collision on {rule!r}")
            rules[rule] = '"{" ws (' + " | ".join(alternatives) + ')? ws "}"'
            return rule

        parts = []
        for index, key in enumerate(k for k in properties if k in required):
            separator = ' ws "," ws ' if index else " "
            parts.append(f'{separator}{member(key)}')
        for key in optional:
            parts.append(f' (ws "," ws {member(key)})?')
        rule = _name(path, root)
        if rule in rules:
            # Two different positions sanitised to the same rule name; the second would silently
            # replace the first and the grammar would validate the wrong shape.
            raise Unsupported(f"rule name collision on {rule!r}: sanitising `_` to `-` made two "
                              "distinct paths identical. Rename a property.")
        rules[rule] = '"{" ws ' + "".join(parts) + ' ws "}"'
        return rule

    if kind == "array":
        items = schema.get("items")
        if isinstance(items, list):
            raise Unsupported(f"{_name(path, root)}: tuple-form `items` is not implemented")
        if not isinstance(items, dict):
            raise Unsupported(f"{_name(path, root)}: an array without a single `items` schema")
        child = _rule(items, path + ["item"], rules, root)
        rule = _name(path, root) + "-array"
        rules[rule] = f'"[" ws ({child} (ws "," ws {child})*)? ws "]"'
        return rule

    if kind == "string":
        return "string"
    if kind == "integer":
        return "integer"
    if kind == "number":
        return "number"
    if kind == "boolean":
        return "boolean"

    raise Unsupported(f"{_name(path, root)}: unsupported type {kind!r}")


PRIMITIVE_RULES = {
    "ws": r"ws       ::= [ \t\n]*",
    "string": r'string   ::= "\"" ([^"\\] | "\\" ["\\/bfnrt])* "\""',
    "integer": r'integer  ::= "-"? ("0" | [1-9] [0-9]*)',
    "number": r'number   ::= "-"? ("0" | [1-9] [0-9]*) ("." [0-9]+)? ([eE] [-+]? [0-9]+)?',
    "boolean": r'boolean  ::= "true" | "false"',
}


def schema_grammar(schema: dict, root: str = "root") -> str:
    """A GBNF grammar matching exactly the JSON documents this schema admits.

    Only the primitives the generated rules actually reference are emitted. A grammar carrying
    `number` and `integer` for a schema with neither is dead weight in every request, and dead
    rules are also where a typo hides: nothing references them, so nothing catches them.
    """
    rules: dict[str, str] = {}
    top = _rule(schema, [], rules, root)
    # An alias line ONLY when the top rule is not already the root -- an enum or array at the top
    # level returns its own name. When it IS the root, the rule lives in `rules` under that name and
    # must be emitted like any other. Filtering it out to avoid `root ::= root` removed the only
    # rule the grammar needed, and the server's sole complaint is "failed to parse grammar".
    lines = []
    if top != root:
        lines.append(f"{root} ::= {top}")
    lines += [f"{name} ::= {body}" for name, body in rules.items()]
    used = " ".join(rules.values())
    for name, rule in PRIMITIVE_RULES.items():
        if re.search(rf"\b{name}\b", used):
            lines.append(rule)
    return "\n".join(line for line in lines if line)


def harmony_report_grammar(schema: dict, allow_analysis: bool = True) -> str:
    """The same grammar, wrapped in the harmony envelope a final message must have.

    `<|channel|>final<|message|>{...}<|return|>` — the shape docs/format.md gives for a final
    message, and the shape 18 of the 99 completions llama.cpp discarded were already using.

    AN ANALYSIS MESSAGE IS ADMITTED FIRST, by default. The first version of this forbade it, on the
    reasoning that a model which reasons at length on the report turn is the recorded failure (a
    page of reasoning truncated mid-sentence, three of four on the deepest plan). That was an
    assertion, not a measurement, and it is the wrong conclusion from it: truncation is a BUDGET
    failure, and forbidding a reasoning model from reasoning at all is a much larger intervention
    than the evidence supports -- it would have to decide `files_changed` and `tests_run` with no
    working out at all.

    `thought` is `([^<] | "<" [^|])*`: any text that never begins a special token, so the model can
    reason about PHP generics and comparisons without the grammar mistaking `<` for a marker, and
    cannot run past `<|end|>`.

    Pass allow_analysis=False for the stricter shape; it is kept because it is one line and because
    which of the two is better is a question for the bench, not for this docstring.
    """
    body = schema_grammar(schema, root="report")
    final = 'final    ::= "<|channel|>final<|message|>" report "<|return|>"'
    if not allow_analysis:
        return 'root ::= "<|channel|>final<|message|>" report "<|return|>"\n' + body
    return "\n".join([
        "root     ::= analysis? final",
        'analysis ::= "<|channel|>analysis<|message|>" thought "<|end|><|start|>assistant"',
        'thought  ::= ([^<] | "<" [^|])*',
        final,
        body])
