#!/usr/bin/env python3
"""Run macOS model tests against local HTTP fixtures; no external model download in unit tests."""
import http.server
import os
from pathlib import Path
import subprocess
import threading

ROOT = Path(__file__).resolve().parent.parent
VALID = b"l m g g".replace(b" ", b"") + bytes(128 * 1024)

class Handler(http.server.BaseHTTPRequestHandler):
    retries = 0
    def do_GET(self):
        name = self.path.rsplit("/", 1)[-1]
        if name == "ggml-retry.bin":
            Handler.retries += 1
            if Handler.retries == 1:
                self.send_error(503)
                return
        if name == "ggml-missing.bin":
            self.send_error(404)
            return
        body = b"<html>not a model</html>" if name == "ggml-html.bin" else b"lmg" if name == "ggml-short.bin" else VALID
        self.send_response(200)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)
    def log_message(self, *args):
        pass

if __name__ == "__main__":
    server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    try:
        result = subprocess.run(["swift", "test", "--package-path", str(ROOT / "mac"),
            "--scratch-path", str(ROOT / "tmp/swift-tests")],
            env={**os.environ, "MODEL_TEST_BASE_URL": f"http://127.0.0.1:{server.server_port}"})
    finally:
        server.shutdown()
    raise SystemExit(result.returncode)
