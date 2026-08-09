#!/usr/bin/env python3
"""
handoff-json-check.py <reply-text-file> <schema.json> <result.json>

Extract a handoff report from a model's final text and validate it against the schema.

Exists as a separate file because a second prompt-validate provider needed exactly what
providers/opencode.sh does inline, and copying sixty lines of validator into every new adapter is
how the two drift apart. opencode.sh deliberately still carries its own copy: it works, it is
covered by recorded runs, and changing it to source this would be a regression risk taken for no
benefit. New adapters use this one.

Extraction is tolerant on purpose. The model is told to emit raw JSON and in practice may wrap it
in a markdown fence or put prose in front of it. stdlib only -- jsonschema is not guaranteed
present, and the handoff schema uses a small enough vocabulary that a real validator is not worth
a dependency.

On success writes canonical JSON to <result.json> and exits 0 silently.
On failure prints a human-readable reason and exits 1, leaving <result.json> untouched so a stale
file from an earlier attempt can never be read as a fresh success.
"""
import json
import re
import sys

Q = chr(34)


def try_loads(text):
    try:
        return json.loads(text), None
    except Exception as exc:
        return None, str(exc)


def balanced(text):
    """Return the first balanced {...} region, ignoring braces inside strings."""
    depth = 0
    start = None
    in_string = False
    escaped = False
    for i, ch in enumerate(text):
        if escaped:
            escaped = False
            continue
        if ch == "\\":
            escaped = True
            continue
        if ch == Q:
            in_string = not in_string
            continue
        if in_string:
            continue
        if ch == "{":
            if depth == 0:
                start = i
            depth += 1
        elif ch == "}":
            depth -= 1
            if depth == 0 and start is not None:
                return text[start:i + 1]
    return None


def validate(instance, schema, path, errors):
    if "type" in schema:
        t = schema["type"]
        ok = ((t == "object" and isinstance(instance, dict))
              or (t == "array" and isinstance(instance, list))
              or (t == "string" and isinstance(instance, str))
              or (t == "boolean" and isinstance(instance, bool))
              or (t in ("integer", "number")
                  and isinstance(instance, (int, float)) and not isinstance(instance, bool))
              or (t == "null" and instance is None))
        if not ok:
            errors.append(f"{path}: expected {t}, got {type(instance).__name__}")
    if "enum" in schema and instance not in schema["enum"]:
        errors.append(f"{path}: {instance!r} not in enum {schema['enum']!r}")
    if isinstance(instance, dict):
        for required in schema.get("required", []):
            if required not in instance:
                errors.append(f"{path}: missing required {required!r}")
        if schema.get("additionalProperties") is False:
            allowed = set(schema.get("properties", {}).keys())
            for key in instance:
                if key not in allowed:
                    errors.append(f"{path}: additional property {key!r} not allowed")
        for key, subschema in schema.get("properties", {}).items():
            if key in instance:
                validate(instance[key], subschema, f"{path}.{key}", errors)
    if isinstance(instance, list) and "items" in schema:
        for i, item in enumerate(instance):
            validate(item, schema["items"], f"{path}[{i}]", errors)


def main():
    reply_path, schema_path, out_path = sys.argv[1], sys.argv[2], sys.argv[3]
    text = open(reply_path).read().strip()
    if not text:
        print("the provider returned no final text")
        return 1

    fence = re.search(r"```(?:json)?\s*(.*?)```", text, re.S)
    if fence:
        text = fence.group(1).strip()

    obj, err = try_loads(text)
    if obj is None:
        region = balanced(text)
        if region is not None:
            obj, err = try_loads(region)
    if obj is None:
        print(f"could not extract a JSON object from the reply: {err or 'no balanced object found'}")
        return 1

    errors = []
    validate(obj, json.load(open(schema_path)), "$", errors)
    if errors:
        print("schema validation failed: " + " | ".join(errors))
        return 1

    open(out_path, "w").write(json.dumps(obj, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
