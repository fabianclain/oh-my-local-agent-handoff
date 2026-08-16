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

REASONING EFFORT is left at the encoding's default rather than set from anything here, because the
control does not set it either and an arm that changes two things measures neither.
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


def render_prompt(messages: list[dict], tools: list[dict]) -> str:
    """The completion prompt for this conversation, rendered by openai-harmony."""
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
    return encoding.decode_utf8(tokens)


if __name__ == "__main__":
    # A quick look at what a model would actually be shown, for eyeballing against
    # `curl /apply-template`.
    payload = json.load(sys.stdin)
    print(render_prompt(payload.get("messages") or [], payload.get("tools") or []))
