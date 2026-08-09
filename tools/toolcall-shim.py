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
"""
import json, re, urllib.request
from http.server import BaseHTTPRequestHandler, HTTPServer

UPSTREAM = "http://127.0.0.1:11434"

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

    candidates = XMLCALL.findall(content) + FENCE.findall(content) + [content]
    for blob in candidates:
        blob = blob.strip()
        if not blob.startswith("{"):
            continue
        try:
            obj = json.loads(blob)
        except Exception:
            continue
        name = obj.get("name")
        args = obj.get("arguments", obj.get("parameters", {}))
        if isinstance(name, str) and name in allowed:
            if isinstance(args, str):
                try:
                    args = json.loads(args)
                except Exception:
                    args = {}
            out.append({"name": name, "arguments": args if isinstance(args, dict) else {}})
            break
    return out


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

        if allowed and status == 200:
            try:
                data = json.loads(payload)
                for msg in ([data["message"]] if "message" in data else
                            [c["message"] for c in data.get("choices", []) if "message" in c]):
                    if msg.get("tool_calls"):
                        continue
                    calls = extract(msg.get("content") or "", allowed)
                    if calls:
                        msg["tool_calls"] = [
                            {"id": f"call_{i}", "type": "function",
                             "function": {"name": c["name"],
                                          "arguments": json.dumps(c["arguments"])}}
                            for i, c in enumerate(calls)
                        ]
                        msg["content"] = ""
                payload = json.dumps(data).encode()
            except Exception:
                pass

        # Re-emit as a single newline-delimited JSON object when the client asked to stream.
        # ollama's stream format is NDJSON, and one final object carrying done=true is a valid
        # (if degenerate) stream that clients accept.
        ctype = "application/json"
        if wanted_stream:
            # ollama never emits content and done=true in the same object: the content chunks
            # carry done=false, and a final chunk carries done=true with an empty message and the
            # timing fields. Collapsing both into one object made opencode wait forever with no
            # error, which is how this was found -- a known-good model failed through the shim.
            try:
                obj = json.loads(payload)
                msg = obj.get("message", {})
                first = dict(obj)
                first["message"] = msg
                first["done"] = False
                first.pop("done_reason", None)
                last = {k: v for k, v in obj.items() if k not in ("message",)}
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
    HTTPServer(("127.0.0.1", 11500), Handler).serve_forever()
