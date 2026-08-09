#!/usr/bin/env python3
"""
ollama-ctx-proxy — rewrite the context window Cline forces on Ollama.

    python3 tools/ollama-ctx-proxy.py [port] [default_ctx] [ctx_map_json|-] [metrics.jsonl]
    # defaults: port 11556, floor 32768, the per-model map below, metrics off

Cline's CLI sends an explicit `options.num_ctx` on every /api/chat call and it is not
configurable in 3.0.52 — the current published release. Captured from the wire:

    {"model": "gem-96k", "think": false, "options": {"num_ctx": 32768},
     "tool_choice": "auto", "stream": true}

That overrides whatever `PARAMETER num_ctx` the model was built with, so a model baked to 96k is
silently served at 32k. It matters twice over: a 25-tool system prompt plus file contents plus
reasoning fills 32k and the run dies reporting "Model reached the maximum output token limit",
and separately gemma is on record scoring 4/5 at 32k against 5/5 at 96k. Any Cline-versus-opencode
comparison run this way is really a 32k-versus-96k comparison wearing a disguise.

Point Cline at this proxy by setting `baseUrl` in the ollama provider's entry in
<config>/data/settings/providers.json. `cline auth -b` refuses that flag for the ollama provider,
but the field is honoured when written directly — verified by seeing the requests arrive here.

Deliberately separate from tools/toolcall-shim.py. That one collapses a stream into a single
response so it can inspect and rewrite the reply; Cline consumes the stream incrementally, so the
two must not be combined. This proxy touches the request only and passes the response through
untouched.
"""
import json
import sys
import time
import urllib.error
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

UPSTREAM = "http://127.0.0.1:11434"
HOP_BY_HOP = ("host", "content-length", "accept-encoding", "connection", "transfer-encoding")

# Rebound from argv under __main__. Defined here so importing this module for a unit test does
# not raise NameError inside the request path.
DEFAULT_CTX = 32768
CTX_MAP = {}
METRICS_PATH = None
# Tool-name prefixes hidden from the model. Set to an empty tuple to pass everything.
DROP_TOOL_PREFIXES = ("team_",)


def dropped_tool(tool):
    """True if this tool should be hidden from the model.

    Cline offers 25 tools and 18 of them are `team_*` orchestration calls that a coding task can
    never use. That is schema bloat in every request and eighteen extra ways for a model to pick
    the wrong tool, so they are removed here rather than left to the model's judgement.

    Filtering happens in the proxy because Cline 3.0.52 exposes no way to do it: `--pure` is in
    the help text but the binary rejects it, and `cline config tools` only opens a TUI.
    """
    try:
        name = (tool.get("function") or tool).get("name") or ""
    except Exception:
        return False
    return any(name.startswith(prefix) for prefix in DROP_TOOL_PREFIXES)


# Replacement descriptions for tools whose shipped description provokes malformed output.
#
# Cline's `apply_patch` description is 1,224 bytes of grammar rules and worked examples, including
# a JSX snippet full of braces and a note about `%%bash` / heredoc wrappers. With it, gpt-oss emits
# an ARRAY-wrapped tool call — `[{"input": ...}]` — and ollama rejects its own model's output with
#
#     HTTP 500 error parsing tool call: raw='{"input":"*** Begin Patch..."}]'
#     err=invalid character ']' after top-level value
#
# Measured against the same model and the same conversation, varying only this string:
#
#     Cline's description (1224B) -> 2/5 requests failed
#     short description   (105B)  -> 0/5 requests failed
#
# The grammar is not lost: gpt-oss already knows the apply_patch format from its own training, so
# the short description is enough. Keyed by tool name and applied only when the shipped text is
# long, so a client that already sends something terse is left alone.
TOOL_DESCRIPTION_OVERRIDES = {
    "apply_patch": (
        "Edit files using the canonical apply_patch grammar "
        "(*** Begin Patch / *** Update File: / @@ / *** End Patch). "
        "Pass the patch text directly as the `input` string. "
        "Emit exactly one JSON object, never an array."
    ),
}
OVERRIDE_MIN_LENGTH = 400


def rewrite_tool_description(tool):
    """Shorten a tool description known to provoke malformed tool calls. True if changed."""
    try:
        fn = tool.get("function") or tool
        name = fn.get("name")
        replacement = TOOL_DESCRIPTION_OVERRIDES.get(name)
        if not replacement:
            return False
        if len(fn.get("description") or "") < OVERRIDE_MIN_LENGTH:
            return False
        fn["description"] = replacement
        return True
    except Exception:
        return False


def payload_model(body):
    try:
        return json.loads(body).get("model")
    except Exception:
        return None


def record_throughput(tail, model):
    """Append one throughput sample per completed generation.

    Timestamped so samples can be joined to a bench run afterwards: bench/run writes
    started_epoch and finished_epoch into each run's `timing` file, which brackets the requests
    belonging to it. Failures are swallowed — a metrics sink must never be able to break the
    inference path it is observing.
    """
    try:
        final = None
        for line in tail.split(b"\n"):
            line = line.strip()
            if not line.startswith(b"{"):
                continue
            try:
                obj = json.loads(line)
            except Exception:
                continue
            if obj.get("done"):
                final = obj
        if not final:
            return
        eval_count = final.get("eval_count") or 0
        eval_ns = final.get("eval_duration") or 0
        sample = {
            "ts": time.time(),
            "model": model,
            "eval_count": eval_count,
            "eval_duration_ns": eval_ns,
            "prompt_eval_count": final.get("prompt_eval_count") or 0,
            "tokens_per_second": round(eval_count / (eval_ns / 1e9), 2) if eval_ns else None,
        }
        with open(METRICS_PATH, "a") as handle:
            handle.write(json.dumps(sample) + "\n")
    except Exception:
        pass


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, *args):
        pass

    def _forward(self):
        body = self.rfile.read(int(self.headers.get("Content-Length") or 0))

        # Rewrite only when the client actually asked for a smaller window. Raising a limit the
        # caller set deliberately lower would be its own silent misconfiguration.
        if body:
            try:
                payload = json.loads(body)
                target = CTX_MAP.get(payload.get("model"), DEFAULT_CTX)
                options = payload.setdefault("options", {})
                current = options.get("num_ctx")
                changed = False
                if not isinstance(current, int) or current < target:
                    options["num_ctx"] = target
                    changed = True
                if isinstance(payload.get("tools"), list):
                    if DROP_TOOL_PREFIXES:
                        kept = [t for t in payload["tools"] if not dropped_tool(t)]
                        if len(kept) != len(payload["tools"]):
                            payload["tools"] = kept
                            changed = True
                    for tool in payload["tools"]:
                        if rewrite_tool_description(tool):
                            changed = True
                if changed:
                    body = json.dumps(payload).encode()
            except Exception:
                pass

        request = urllib.request.Request(UPSTREAM + self.path, data=body, method=self.command)
        for key, value in self.headers.items():
            if key.lower() not in HOP_BY_HOP:
                request.add_header(key, value)

        try:
            upstream = urllib.request.urlopen(request, timeout=3600)
        except urllib.error.HTTPError as err:
            payload = err.read()
            self.send_response(err.code)
            self.send_header("Content-Type", err.headers.get("Content-Type", "application/json"))
            self.send_header("Content-Length", str(len(payload)))
            self.end_headers()
            self.wfile.write(payload)
            return
        except Exception as exc:
            payload = json.dumps({"error": str(exc)}).encode()
            self.send_response(502)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(payload)))
            self.end_headers()
            self.wfile.write(payload)
            return

        # Stream the response through rather than buffering it. Ollama emits NDJSON as tokens are
        # produced, and a long edit can take minutes; buffering would hand the client nothing until
        # generation finished, which reads as a hang.
        self.send_response(upstream.status)
        self.send_header("Content-Type", upstream.headers.get("Content-Type", "application/json"))
        self.send_header("Transfer-Encoding", "chunked")
        self.end_headers()
        # Keep only the tail. Ollama's final NDJSON object carries eval_count and eval_duration,
        # which is the only honest source of generation throughput: wall-clock time covers tool
        # execution, model load and the agent's own overhead, so a model that is genuinely slower
        # per token and one that simply took more turns look identical from outside.
        tail = b""
        try:
            while True:
                chunk = upstream.read(4096)
                if not chunk:
                    break
                if METRICS_PATH:
                    tail = (tail + chunk)[-8192:]
                self.wfile.write(b"%x\r\n%s\r\n" % (len(chunk), chunk))
                self.wfile.flush()
            self.wfile.write(b"0\r\n\r\n")
            self.wfile.flush()
        except (BrokenPipeError, ConnectionResetError):
            pass
        finally:
            upstream.close()
            if METRICS_PATH and tail:
                record_throughput(tail, payload_model(body))

    do_POST = _forward
    do_GET = _forward
    do_DELETE = _forward


# Per-model windows, because one number cannot be right for every model on one card.
#
# Measured on an RTX 5060 Ti (14.4 GB usable) with a global 128k override, which is how this map
# came to exist:
#
#   gem-96k      8.1 GB   100% GPU   4962 MiB free   probe passed
#   gptoss-32k    14 GB    83% GPU   1142 MiB free   probe passed, degraded
#   qw3c-32k      18 GB    74% GPU   1057 MiB free   probe FAILED
#
# Residency is a throughput tax rather than an automatic cliff: gpt-oss at 84% still produced a
# byte-perfect patch, at 43 tok/s against 61 at 100%. It has cost everything once, though —
# Devstral at 85% ran 101 minutes and wrote no files — so a partial offload is a deliberate
# choice to price in per model, never a default.
#
# Prefer the largest window that stays 100% resident. For gpt-oss that is 64k, which also clears
# the ~36k a multi-file plan actually consumes; 128k buys nothing this workload uses and costs a
# third of the throughput.
#
# Re-measure before changing an entry. `ollama ps` reports both PROCESSOR and CONTEXT while a run
# is live, which is the only check that matters here.
DEFAULT_CTX_MAP = {
    "gem-96k": 131072,
    "gptoss-32k": 32768,
    # 64k clears the ~36k a multi-file task actually consumes and still loads 100% on
    # the GPU (12 GB, 1.1 GB free). Strictly better than 128k here: same headroom for
    # this workload, none of the 30% throughput tax the 84% offload costs.
    "gptoss-64k": 65536,
    # Deliberately over-subscribed: 128k puts this build at ~83% GPU / 17% CPU.
    # That is the offload experiment, not an oversight — see docs/local-models.md.
    "gptoss-128k": 131072,
    "gptossd-32k": 32768,
    "qw3c-32k": 32768,
}

if __name__ == "__main__":
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 11556
    DEFAULT_CTX = int(sys.argv[2]) if len(sys.argv) > 2 else 32768
    CTX_MAP = dict(DEFAULT_CTX_MAP)
    if len(sys.argv) > 3 and sys.argv[3] not in ("", "-"):
        CTX_MAP.update(json.loads(sys.argv[3]))
    METRICS_PATH = sys.argv[4] if len(sys.argv) > 4 else None
    if len(sys.argv) > 5:
        DROP_TOOL_PREFIXES = tuple(p for p in sys.argv[5].split(",") if p)
    print(f"ollama-ctx-proxy on :{port} -> {UPSTREAM}", flush=True)
    print(f"  default num_ctx floor: {DEFAULT_CTX}", flush=True)
    for model, ctx in sorted(CTX_MAP.items()):
        print(f"  {model}: {ctx}", flush=True)
    if METRICS_PATH:
        print(f"  throughput samples -> {METRICS_PATH}", flush=True)
    print(f"  hiding tools with prefixes: {DROP_TOOL_PREFIXES or '(none)'}", flush=True)
    ThreadingHTTPServer(("127.0.0.1", port), Handler).serve_forever()
