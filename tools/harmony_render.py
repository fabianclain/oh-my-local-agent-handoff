"""harmony_render — build the prompt with OpenAI's own renderer instead of llama.cpp's template.

WHY THIS EXISTS

llama.cpp renders harmony's tool section, and renders it lossily. Every nested object in a tool's
JSON Schema collapses to `any[]`, taking the field names and their descriptions with it. The same
`read_files` schema, both renderers:

    harmony      files: { path?: string,
                          // first line, 1-based
                          start?: number,
                          // last line, inclusive
                          end?: number, }[]

    llama.cpp    files: any[]

Four structures in the real tool set are erased that way: `read_files.files`, and `submit_report`'s
`files_changed`, `tests_run` and `deviations`. The `start`/`end` window -- the change that turned
three dead rounds into an accepted one -- is not in the type the model is shown at all. It survives
because it happens to be spelled out in prose in the tool's description string.

docs/format.md is explicit that this matters: tools are defined "using a TypeScript-like type
syntax" and "it's important to stick to this format closely to improve accuracy of function
calling". So this is not tidiness. It is the difference between showing the model its tools and
describing them to it.

WHAT IS AND IS NOT REPRODUCED

The mapping from this harness's OpenAI-shaped messages onto harmony's roles, stated because a
silent difference here would be indistinguishable from a model effect:

    our `system`      -> developer INSTRUCTIONS. Our system prompt is task instruction, not model
                         identity; harmony's system message is reserved for identity, knowledge
                         cutoff, reasoning effort and the channel list, which the encoding writes
                         itself.
    our `tools`       -> developer tools, in the `functions` namespace
    our `user`        -> user
    our `assistant`   -> assistant, with tool calls rendered to the commentary channel and
                         `to=functions.NAME`, which is what the spec asks for
    our `tool`        -> a tool message authored by `functions.NAME`, matched back to the call it
                         answers by tool_call_id

REASONING EFFORT is settable and defaults to UNSET, which leaves the encoding's `Reasoning: medium`
-- the same line llama.cpp's template emits, so the default arm differs from the control in one
thing and not two. Passing it is opt-in, for an arm that means to vary it. The one prior measurement
here (low against off, 15 runs each, no difference at p >= 0.70) went through Cline, whose flag is a
different mechanism, so it does not settle what this control does.
"""

from __future__ import annotations

import json
import pathlib
import sys

# The venv tools/install-harmony creates. Added to the path rather than installed into the system
# python, which PEP 668 refuses and which is not this project's to modify.
_VENV = pathlib.Path.home() / ".cache" / "agent-handoff" / "venv"


def _load():
    for candidate in sorted(_VENV.glob("lib/python*/site-packages")):
        if str(candidate) not in sys.path:
            sys.path.insert(0, str(candidate))
    try:
        import openai_harmony  # noqa: PLC0415
    except ImportError as error:
        # Loud, never a fallback to llama.cpp's rendering. An arm that silently ran as the control
        # would produce a full set of results and be recorded as having tested something it never
        # tested; this project has discarded 25 runs to that class of mistake.
        raise SystemExit(
            "the harmony renderer is not installed, so this arm cannot run.\n"
            f"  expected: {_VENV}/lib/python*/site-packages/openai_harmony\n"
            "  install:  tools/install-harmony\n"
            f"  cause:    {error}") from error
    return openai_harmony


def _today() -> str:
    """The date llama.cpp's template puts in the system message, in its format."""
    import datetime  # noqa: PLC0415

    return datetime.date.today().isoformat()


def response_format_section(name: str, schema: dict, description: str = "") -> str:
    """The `# Response Formats` block, exactly as docs/format.md defines it.

        # Response Formats

        ## {format name}

        // {description or context}
        {schema}

    openai-harmony's DeveloperContent exposes `with_instructions` and `with_function_tools` and
    nothing for this, so it is built here from the specification rather than left unused. The
    schema is a JSON Schema, minified, because it is data the model reads once per conversation
    rather than prose.

    The spec is candid about what this buys on its own: "This prompt alone will, however, only
    influence the model's behavior but doesn't guarantee the full adherence to the schema. For this
    you still need to construct your own grammar and enforce the schema during sampling." That
    grammar is what providers/nativejson.sh applies. The two halves belong together, and until now
    this project had only the second one.
    """
    lines = ["# Response Formats", "", f"## {name}", ""]
    if description:
        lines.append(f"// {' '.join(description.split())}")
    lines.append(json.dumps(schema, separators=(",", ":")))
    return "\n".join(lines)


def render_prompt(messages: list[dict], tools: list[dict],
                  response_format: dict | None = None,
                  reasoning_effort: str | None = None) -> str:
    """The completion prompt for this conversation, rendered by openai-harmony.

    `response_format`, when given, is {"name", "schema", "description"} and is appended to the END
    of the developer message, which is where docs/format.md puts it -- after the tools, not before.
    The library builds the developer message as a unit, so the section is spliced in before that
    message's terminator rather than folded into the instructions, which would place it above
    `# Tools` and no longer be what the spec describes.
    """
    h = _load()
    encoding = h.load_harmony_encoding(h.HarmonyEncodingName.HARMONY_GPT_OSS)

    instructions = "\n\n".join(m.get("content") or "" for m in messages
                               if m.get("role") == "system").strip()
    developer = h.DeveloperContent.new()
    if instructions:
        developer = developer.with_instructions(instructions)
    if tools:
        described = []
        for tool in tools:
            function = tool.get("function") or {}
            described.append(h.ToolDescription.new(
                function.get("name") or "",
                function.get("description") or "",
                parameters=function.get("parameters") or {"type": "object", "properties": {}}))
        developer = developer.with_function_tools(described)

    # The SYSTEM message, which harmony does not add for you and which is not optional. It carries
    # the model identity, the knowledge cutoff, the reasoning effort and -- the part that matters
    # here -- the channel list and the rule that calls to `functions` go to the commentary channel.
    # llama.cpp's template emits all of it; leaving it out would have made this arm differ from the
    # control in TWO ways, tool types and channel guidance, and measured neither.
    # `Current date:` too, because llama.cpp's template emits it and the ONLY difference between
    # this arm and the control must be the thing under test. A second difference, however small,
    # makes the result unattributable -- which is the objection bench/compare raises as CONFOUNDED
    # and which this project has thrown away runs over.
    system = h.SystemContent.new().with_conversation_start_date(
        _today() if _today() else "")
    if reasoning_effort:
        # `Reasoning: low|medium|high` in the system message, which docs/format.md calls the
        # recommended way to control it. This harness has never set it: llama.cpp's template emits
        # `Reasoning: medium` and nothing here chose that. The one prior measurement -- low against
        # off, 15 runs each, no difference at p >= 0.70 -- was taken through Cline, whose own flag
        # is a different mechanism, so it does not settle what this control does.
        levels = {"low": h.ReasoningEffort.LOW, "medium": h.ReasoningEffort.MEDIUM,
                  "high": h.ReasoningEffort.HIGH}
        if reasoning_effort not in levels:
            raise SystemExit(f"reasoning effort must be one of {sorted(levels)}, "
                             f"not {reasoning_effort!r}")
        system = system.with_reasoning_effort(levels[reasoning_effort])
    rendered: list = [
        h.Message.from_role_and_content(h.Role.SYSTEM, system),
        h.Message.from_role_and_content(h.Role.DEVELOPER, developer),
    ]

    # tool_call_id -> the function it called, so a tool RESULT can name its author. harmony
    # attributes a tool message to `functions.NAME`; the OpenAI shape carries only the id.
    author_of: dict[str, str] = {}

    for message in messages:
        role = message.get("role")
        if role == "system":
            continue
        if role == "user":
            rendered.append(h.Message.from_role_and_content(h.Role.USER,
                                                            message.get("content") or ""))
        elif role == "assistant":
            # The analysis channel first, when the loop chose to carry it. docs/format.md's worked
            # example keeps the chain of thought in context across a tool call precisely so the
            # model can continue a thought rather than restart one, and this harness dropped it on
            # every turn until it was read.
            thinking = (message.get("reasoning_content") or "").strip()
            if thinking:
                rendered.append(h.Message.from_role_and_content(h.Role.ASSISTANT, thinking)
                                .with_channel("analysis"))
            text = (message.get("content") or "").strip()
            if text:
                rendered.append(h.Message.from_role_and_content(h.Role.ASSISTANT, text)
                                .with_channel("final"))
            for call in message.get("tool_calls") or []:
                function = call.get("function") or {}
                name = function.get("name") or ""
                author_of[call.get("id") or ""] = name
                rendered.append(
                    h.Message.from_role_and_content(h.Role.ASSISTANT,
                                                    function.get("arguments") or "{}")
                    .with_channel("commentary")
                    .with_recipient(f"functions.{name}"))
        elif role == "tool":
            name = author_of.get(message.get("tool_call_id") or "", "tool")
            rendered.append(
                h.Message.from_author_and_content(
                    h.Author.new(h.Role.TOOL, f"functions.{name}"),
                    message.get("content") or "")
                .with_channel("commentary")
                .with_recipient("assistant"))

    conversation = h.Conversation.from_messages(rendered)
    tokens = encoding.render_conversation_for_completion(conversation, h.Role.ASSISTANT)
    prompt = encoding.decode_utf8(tokens)

    if response_format:
        section = response_format_section(response_format.get("name") or "report",
                                          response_format.get("schema") or {},
                                          response_format.get("description") or "")
        # Spliced before the developer message's terminator, so it lands after `# Tools` as the
        # spec has it. Located by the developer marker rather than by counting <|end|>s, because
        # tool results and assistant turns produce plenty of those.
        marker = "<|start|>developer<|message|>"
        start = prompt.find(marker)
        if start < 0:
            raise SystemExit("no developer message to attach the response format to; "
                             "the renderer changed shape and this splice is no longer valid")
        end = prompt.find("<|end|>", start)
        if end < 0:
            raise SystemExit("the developer message is unterminated; refusing to guess where "
                             "the response format belongs")
        prompt = prompt[:end] + "\n\n" + section + prompt[end:]
    return prompt


if __name__ == "__main__":
    # A quick look at what a model would actually be shown, for eyeballing against
    # `curl /apply-template`.
    payload = json.load(sys.stdin)
    print(render_prompt(payload.get("messages") or [], payload.get("tools") or []))
