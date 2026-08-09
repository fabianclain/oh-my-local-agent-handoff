#!/usr/bin/env python3
"""
Tool-call shim: sits between a client and ollama, and promotes text-formatted tool calls into
real tool_calls.

Several models emit a correct tool call as prose instead of as a native call:

    content: '```json\n{"name": "read", "arguments": {"filePath": "x"}}\n```'

The client never executes it, so the model reports -- accurately -- that it could not read the
file. Observed on qwen2.5-coder, JanusCoder, gemma-4-coder-fable5 and Qwen3-Coder. In at least
one case the cause is a packaging bug: unsloth's Qwen3-Coder GGUF ships a Qwen2.5-era template
containing <tool_call> rather than Qwen3-Coder's documented <function=...><parameter=...> format,
so the model is instructed in a format it was not trained to emit and falls back to bare JSON.

This rewrites the response so the client sees what the model meant. It only ever promotes a call
whose name matches a tool the client actually offered in the request, so stray JSON in ordinary
prose is left alone.

## Two bugs that made an earlier version of this file fail inside opencode

Both were found by measurement, and both are worth stating because each produced the same
symptom -- opencode hanging with no error and no output -- from an unrelated cause.

**1. `arguments` must be an object, not a JSON string.** The OpenAI wire format sends
tool-call arguments as a serialised string; ollama's does not. `ollama-ai-provider-v2` validates
every NDJSON line against a zod schema declaring
`arguments: z.record(z.string(), z.any())`, and `createNdjsonStreamResponseHandler` *drops* a
line that fails validation with nothing but a `console.warn`. So a promoted tool call written
the OpenAI way vanished silently and the client saw a stream containing only its terminator.
Verified by running the shim's real output through that exact schema:

    line 1: DROPPED -> expected record, received string   (the tool call)
    line 2: VALID                                         (the terminator)

**2. The server must be threaded.** `HTTPServer` handles one connection at a time, and
`protocol_version = "HTTP/1.1"` keeps connections alive. A client that holds an idle connection
open -- which any pooling HTTP client does -- blocks every subsequent connection forever.
Measured against the old shim: a second connection opened while the first sat idle timed out
after 8s having received nothing.

This is why *gemma* also failed through the shim despite emitting native tool calls and never
touching the promotion path at all. That observation was read at the time as evidence the whole
shim approach was broken; it was really the second bug, sitting underneath the first.
"""
import json, re, sys, urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

UPSTREAM = "http://127.0.0.1:11434"
LISTEN_PORT = 11500

FENCE = re.compile(r"```(?:json|xml)?\s*(.*?)```", re.S)
XMLCALL = re.compile(r"<tool_call>\s*(.*?)\s*</tool_call>", re.S)
QWEN3 = re.compile(r"<function=([A-Za-z0-9_]+)>(.*?)</function>", re.S)
PARAM = re.compile(r"<parameter=([A-Za-z0-9_]+)>\s*(.*?)\s*</parameter>", re.S)


def extract(content, allowed):
    """Return [{name, arguments}] found in content, restricted to `allowed` tool names."""
    if not content:
        return []
    out = []

    # Qwen3-Coder's documented format, in case a correct template is in use.
    for name, body in QWEN3.findall(content):
        if name in allowed:
            out.append({"name": name, "arguments": {k: v for k, v in PARAM.findall(body)}})
    if out:
        return out

    # A turn may carry more than one call. Qwen3-Coder emits them as consecutive top-level JSON
    # objects separated by a newline -- an edit followed by the bash command that verifies it.
    #
    # An earlier version ran json.loads() over the whole blob, which fails on the second object
    # with "Extra data: line 2 column 1" and promoted nothing at all. The model's text then became
    # the final answer, the driver tried to read it as a handoff report, and the round was scored
    # as a model that changed no files and returned an unparseable report. It had in fact written
    # a correct edit call. So: scan for every balanced object rather than parsing the blob whole.
    candidates = XMLCALL.findall(content) + FENCE.findall(content) + [content]
    seen = set()
    for blob in candidates:
        for obj in iter_json_objects(blob):
            name = obj.get("name")
            args = obj.get("arguments", obj.get("parameters", {}))
            if not isinstance(name, str) or name not in allowed:
                continue
            call = {"name": name, "arguments": coerce_arguments(args)}
            key = json.dumps(call, sort_keys=True)
            # The same call reached through both a fence and the bare content is one call.
            if key in seen:
                continue
            seen.add(key)
            out.append(call)
        if out:
            break
    return out


def iter_json_objects(blob):
    """Yield every top-level JSON object in blob, ignoring surrounding prose.

    Brace counting is string- and escape-aware, so a brace inside a PHP snippet in an oldString
    argument does not end the object early -- which matters here, because the arguments being
    promoted are usually source code.
    """
    depth = 0
    start = None
    in_string = False
    escaped = False
    for i, ch in enumerate(blob):
        if in_string:
            if escaped:
                escaped = False
            elif ch == "\\":
                escaped = True
            elif ch == '"':
                in_string = False
            continue
        if ch == '"':
            in_string = True
        elif ch == "{":
            if depth == 0:
                start = i
            depth += 1
        elif ch == "}":
            if depth == 0:
                continue
            depth -= 1
            if depth == 0 and start is not None:
                obj = loads_tolerant(blob[start:i + 1])
                if isinstance(obj, dict):
                    yield obj
                start = None


VALID_ESCAPES = set('"\\/bfnrtu')


def loads_tolerant(text):
    """Parse JSON a model wrote by hand, returning None if it cannot be recovered.

    A model emitting tool calls as text has to escape source code into a JSON string itself, and
    these do it badly in two consistent ways. Both were measured on Qwen3-Coder writing an `edit`
    call whose oldString was PHP:

      * raw newlines inside the string        -> "Invalid control character at column 249"
      * a lone backslash from `Bench\\Fixture` -> "Invalid \\escape"

    Neither is ambiguous about intent, and repairing them is safe *here* specifically because of
    what the arguments are used for: an `edit` whose oldString is repaired wrongly simply fails to
    match and errors, rather than applying a subtly wrong patch, and any newString damage shows up
    in the diff the byte-identical and rewrite gates already read. Repair is attempted only after
    strict parsing fails, so a well-formed call is never touched.
    """
    try:
        return json.loads(text)
    except Exception:
        pass
    # strict=False permits literal control characters inside strings.
    try:
        return json.loads(text, strict=False)
    except Exception:
        pass
    try:
        return json.loads(escape_stray_backslashes(text), strict=False)
    except Exception:
        return None


def escape_stray_backslashes(text):
    r"""Double any backslash that does not begin a valid JSON escape.

    `\F` in `Bench\Fixture` becomes `\\F`; a real `\n` or `\"` is left exactly as it is, so this
    is a no-op on valid JSON.
    """
    out = []
    i = 0
    while i < len(text):
        ch = text[i]
        if ch == "\\":
            nxt = text[i + 1] if i + 1 < len(text) else ""
            out.append("\\" if nxt in VALID_ESCAPES else "\\\\")
            out.append(nxt)
            i += 2
            continue
        out.append(ch)
        i += 1
    return "".join(out)


def coerce_arguments(args):
    """Return arguments as a dict.

    A model may emit them already-serialised, and some upstream builds pass a string through
    natively. Either way the client's schema requires an object, so normalise here rather than
    letting the line be dropped downstream -- see the module docstring.
    """
    if isinstance(args, str):
        try:
            args = json.loads(args)
        except Exception:
            return {}
    return args if isinstance(args, dict) else {}


def normalise_message(msg):
    """Make a message satisfy the client's schema: content a string, role present, arguments
    an object. Applied to native tool calls too, not only promoted ones."""
    if not isinstance(msg, dict):
        return
    if not isinstance(msg.get("content"), str):
        msg["content"] = ""
    if not isinstance(msg.get("role"), str):
        msg["role"] = "assistant"
    calls = msg.get("tool_calls")
    if isinstance(calls, list):
        for call in calls:
            fn = call.get("function") if isinstance(call, dict) else None
            if isinstance(fn, dict) and "arguments" in fn:
                fn["arguments"] = coerce_arguments(fn["arguments"])


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, *a):
        pass

    def _proxy(self):
        body = self.rfile.read(int(self.headers.get("Content-Length") or 0))
        allowed = set()
        wanted_stream = False
        try:
            req = json.loads(body or b"{}")
            for t in req.get("tools") or []:
                fn = t.get("function") or t
                if isinstance(fn.get("name"), str):
                    allowed.add(fn["name"])
            # Ask upstream for a single response so the whole reply can be inspected, and
            # remember that the client wanted a stream so the answer can be re-emitted in the
            # shape it expects. Silently downgrading to non-streaming makes opencode retry
            # forever with no error, which is how this was first found.
            wanted_stream = bool(req.get("stream"))
            if wanted_stream:
                req["stream"] = False
                body = json.dumps(req).encode()
        except Exception:
            pass

        r = urllib.request.Request(UPSTREAM + self.path, data=body, method=self.command)
        for k, v in self.headers.items():
            if k.lower() not in ("host", "content-length", "accept-encoding", "connection"):
                r.add_header(k, v)
        try:
            with urllib.request.urlopen(r, timeout=1800) as resp:
                payload = resp.read()
                status = resp.status
        except urllib.error.HTTPError as e:
            payload, status = e.read(), e.code
        except Exception as e:
            payload, status = json.dumps({"error": str(e)}).encode(), 502

        if status == 200:
            try:
                data = json.loads(payload)
                messages = ([data["message"]] if "message" in data else
                            [c["message"] for c in data.get("choices", []) if "message" in c])
                for msg in messages:
                    if not msg.get("tool_calls") and allowed:
                        calls = extract(msg.get("content") or "", allowed)
                        if calls:
                            msg["tool_calls"] = [
                                # No "type" key: ollama's own format omits it, and the client
                                # schema does not ask for it.
                                {"id": f"call_{i}",
                                 "function": {"name": c["name"], "arguments": c["arguments"]}}
                                for i, c in enumerate(calls)
                            ]
                            msg["content"] = ""
                    normalise_message(msg)
                payload = json.dumps(data).encode()
            except Exception:
                pass

        # Re-emit as newline-delimited JSON when the client asked to stream. ollama never emits
        # content and done=true in the same object: content chunks carry done=false and a final
        # chunk carries done=true with an empty message and the timing fields.
        ctype = "application/json"
        if wanted_stream:
            try:
                obj = json.loads(payload)
                first = dict(obj)
                first["done"] = False
                first.pop("done_reason", None)
                last = {k: v for k, v in obj.items() if k != "message"}
                last["message"] = {"role": "assistant", "content": ""}
                last["done"] = True
                payload = (json.dumps(first) + "\n" + json.dumps(last) + "\n").encode()
                ctype = "application/x-ndjson"
            except Exception:
                pass

        self.send_response(status)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)

    do_POST = _proxy

    def do_GET(self):
        self._proxy()


if __name__ == "__main__":
    port = int(sys.argv[1]) if len(sys.argv) > 1 else LISTEN_PORT
    # ThreadingHTTPServer, not HTTPServer: see bug 2 in the module docstring. A single-threaded
    # server with keep-alive is wedged by the first idle connection a pooling client leaves open.
    ThreadingHTTPServer(("127.0.0.1", port), Handler).serve_forever()
