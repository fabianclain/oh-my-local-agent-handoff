#!/usr/bin/env python3
"""
Reproduction: ollama returns HTTP 500 "error parsing tool call" for gpt-oss.

    python3 tools/repro-ollama-toolcall-500.py [model] [attempts]

Ollama fails to parse a tool call **its own model just generated** and returns a 500 whose body is:

    {"error":"error parsing tool call: raw='{\\"input\\":\\"*** Begin Patch\\\\n..."}

Three conditions must hold together. Removing any one of them makes the error go away:

  1. the model is gpt-oss (harmony tool-call format),
  2. an `apply_patch`-style tool is offered — one freeform string argument carrying a whole patch,
  3. the conversation already contains an assistant tool call and a substantial tool result.

With a small tool result, or with `apply_patch` absent, the same conversation succeeds. It is also
non-deterministic: it depends on what the model chooses to emit, so it reproduces in roughly one
attempt in three and sometimes not in six. Run with a higher attempt count.

Why this matters beyond ollama: the error surfaces through whatever client is in front, so it
reads as a client bug. It cost a full investigation here — the same string was blamed on Cline's
response parsing, on tool-list bloat, on reasoning being disabled and on argument size, all of
which were ruled out by measurement. This script takes every client out of the picture.

Clients that do not offer a freeform-patch tool are unaffected: opencode ships small targeted
`edit` calls instead, the model never generates the payload that fails to parse, and the same
model completes normally there.
"""
import json
import sys
import urllib.error
import urllib.request

OLLAMA = "http://127.0.0.1:11434/api/chat"

APPLY_PATCH = {
    "type": "function",
    "function": {
        "name": "apply_patch",
        "description": (
            "Edit files with the canonical freeform patch grammar. Pass the patch text directly "
            "as the `input` string:\n\n*** Begin Patch\n*** Update File: path\n@@\n-[old]\n+[new]\n"
            "*** End Patch"
        ),
        "parameters": {
            "type": "object",
            "properties": {"input": {"type": "string", "minLength": 1}},
            "required": ["input"],
            "additionalProperties": False,
        },
    },
}

READ_FILES = {
    "type": "function",
    "function": {
        "name": "read_files",
        "description": "Read files",
        "parameters": {
            "type": "object",
            "properties": {"paths": {"type": "array", "items": {"type": "string"}}},
            "required": ["paths"],
        },
    },
}

# Size matters. At ~740 bytes this did not reproduce in ten attempts; at ~1650 it reproduced
# readily. Keep this above 1.5 KB — a tool result small enough to fit comfortably appears not to
# trigger it at all, which is consistent with the bisect: small result + apply_patch is fine.
SUBJECT = """<?php

namespace Bench\\Fixture;

/**
 * Aggregates invoice lines into subtotal, tax and total.
 *
 * Money flows one way only: subtotal() is the single source of truth for the pre-tax figure,
 * tax() derives from it, and total() is their sum. Anything changing what a customer owes
 * belongs in subtotal() and must never be duplicated into tax() or total().
 */
final class InvoiceTotals
{
    /** @var array<int, array{description: string, quantity: int, unit_price: float}> */
    private array $lines = [];

    public function addLine(string $description, int $quantity, float $unitPrice): void
    {
        $this->lines[] = [
            'description' => $description,
            'quantity' => $quantity,
            'unit_price' => $unitPrice,
        ];
    }

    public function lineCount(): int
    {
        return count($this->lines);
    }

    public function subtotal(): float
    {
        $total = 0.0;

        foreach ($this->lines as $line) {
            $total += $line['quantity'] * $line['unit_price'];
        }

        return $total;
    }

    public function tax(float $rate): float
    {
        return $this->subtotal() * $rate;
    }

    public function total(float $rate): float
    {
        return $this->subtotal() + $this->tax($rate);
    }

    public function heaviestLine(): ?string
    {
        $best = null;
        $bestValue = -1.0;

        foreach ($this->lines as $line) {
            $value = $line['quantity'] * $line['unit_price'];

            if ($value > $bestValue) {
                $bestValue = $value;
                $best = $line['description'];
            }
        }

        return $best;
    }

    public function describe(): string
    {
        return sprintf('%d line(s), subtotal %.2f', $this->lineCount(), $this->subtotal());
    }
}
"""


def attempt(model):
    """Return None on success, or the raw payload ollama could not parse."""
    messages = [
        {"role": "user", "content": "Read f.php then patch it."},
        {"role": "assistant", "content": "",
         "tool_calls": [{"function": {"name": "read_files", "arguments": {"paths": ["f.php"]}}}]},
        {"role": "tool", "content": SUBJECT},
    ]
    body = json.dumps({
        "model": model, "stream": False, "think": False, "tool_choice": "auto",
        "options": {"num_ctx": 65536},
        "messages": messages,
        "tools": [READ_FILES, APPLY_PATCH],
    }).encode()
    request = urllib.request.Request(
        OLLAMA, data=body, headers={"Content-Type": "application/json"}, method="POST")
    try:
        with urllib.request.urlopen(request, timeout=900) as response:
            json.loads(response.read())
        return None
    except urllib.error.HTTPError as err:
        message = json.loads(err.read()).get("error", "")
        return message.split("raw='", 1)[1] if "raw='" in message else message


def main():
    model = sys.argv[1] if len(sys.argv) > 1 else "gpt-oss:20b"
    attempts = int(sys.argv[2]) if len(sys.argv) > 2 else 10
    failures = 0
    for i in range(1, attempts + 1):
        raw = attempt(model)
        if raw is None:
            print(f"  attempt {i}: ok")
            continue
        failures += 1
        print(f"  attempt {i}: HTTP 500, ollama could not parse {len(raw)}B of its own output")
        print(f"    head: {raw[:120]!r}")
        print(f"    tail: {raw[-120:]!r}")
    print(f"\n{failures}/{attempts} attempts reproduced the error")
    return 0 if failures == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
