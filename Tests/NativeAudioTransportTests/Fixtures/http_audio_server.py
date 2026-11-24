#!/usr/bin/env python3
"""Loopback media fixture serving synthetic bytes or a supplied local audio file."""

from __future__ import annotations

import argparse
from collections import Counter
import http.client
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
from pathlib import Path
import re
import threading
import time
import unittest
from urllib.parse import urlsplit


PREFIX = b"\x00\x00\x00\x18ftypM4A \x00\x00\x00\x00M4A isom"
BODY = PREFIX + bytes(range(256)) * 4096
IDENTITY = {
    "User-Agent": "MixtapeTransportTests/1.0",
    "Origin": "https://www.youtube.com",
    "Referer": "https://www.youtube.com/",
    "Accept-Encoding": "identity",
}


class AudioServer(ThreadingHTTPServer):
    daemon_threads = True

    def __init__(self, address, body=BODY):
        super().__init__(address, AudioHandler)
        self.body = body
        self.counts = Counter()
        self.count_lock = threading.Lock()


class AudioHandler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, *_):
        pass

    def send_bytes(self, status, body, mime="audio/mp4", extra=None):
        self.send_response(status)
        self.send_header("Content-Type", mime)
        self.send_header("Content-Length", str(len(body)))
        for name, value in (extra or {}).items():
            self.send_header(name, value)
        self.end_headers()
        if body:
            self.wfile.write(body)

    def do_GET(self):
        path = urlsplit(self.path).path
        body = self.server.body
        with self.server.count_lock:
            self.server.counts[path] += 1
            count = self.server.counts[path]
        try:
            if path == "/forbidden":
                self.send_bytes(403, b"", "text/html")
                return
            if path == "/html":
                self.send_bytes(200, b"<html>error</html>", "text/html")
                return
            if path == "/whole":
                self.send_bytes(200, body)
                return
            if path == "/short-whole":
                self.send_bytes(200, body[:256])
                return
            if path == "/redirect":
                self.send_bytes(302, b"", extra={"Location": "/identity"})
                return
            if path == "/transient" and count == 1:
                self.send_bytes(503, b"")
                return
            if path == "/identity" and (
                any(self.headers.get(name) != value for name, value in IDENTITY.items())
                or self.headers.get("Cookie") is not None
            ):
                self.send_bytes(400, b"")
                return
            match = re.fullmatch(r"bytes=(\d+)-(\d+)", self.headers.get("Range", ""))
            if not match:
                self.send_bytes(400, b"")
                return
            start, end = map(int, match.groups())
            if start >= len(body) or end < start:
                self.send_bytes(416, b"", extra={"Content-Range": f"bytes */{len(body)}"})
                return
            end = min(end, len(body) - 1)
            if path == "/clipped":
                end = min(end, start + 16_384 - 1)
            content = body[start : end + 1]
            range_start = start + 1 if path == "/bad-range" else start
            total = len(body) + (1 if path == "/changed-total" and start > 0 else 0)
            content_range = f"bytes {range_start}-{end}/{total}"
            if path == "/overlong":
                content += b"unexpected-extra"
            self.send_response(206)
            self.send_header("Content-Type", "audio/mp4")
            self.send_header("Content-Range", content_range)
            self.send_header("Content-Length", str(len(content)))
            self.end_headers()
            if path == "/truncated":
                self.wfile.write(content[: max(1, len(content) // 2)])
                self.wfile.flush()
                self.close_connection = True
            elif path == "/slow":
                self.wfile.write(content[:16])
                self.wfile.flush()
                time.sleep(2)
                self.wfile.write(content[16:])
            else:
                self.wfile.write(content)
        except (BrokenPipeError, ConnectionResetError, ConnectionAbortedError):
            # URLSession intentionally cancels invalid/oversized/slow responses.
            self.close_connection = True


class FixtureSelfTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.server = AudioServer(("127.0.0.1", 0))
        cls.thread = threading.Thread(target=cls.server.serve_forever, daemon=True)
        cls.thread.start()

    @classmethod
    def tearDownClass(cls):
        cls.server.shutdown()
        cls.server.server_close()
        cls.thread.join()

    def request(self, path, end=1023):
        connection = http.client.HTTPConnection(*self.server.server_address, timeout=3)
        connection.request("GET", path, headers={**IDENTITY, "Range": f"bytes=0-{end}"})
        response = connection.getresponse()
        body = response.read()
        result = response.status, dict(response.getheaders()), body
        connection.close()
        return result

    def test_identity_and_exact_range(self):
        status, headers, body = self.request("/identity")
        self.assertEqual(status, 206)
        self.assertEqual(headers["Content-Range"], f"bytes 0-1023/{len(BODY)}")
        self.assertEqual(body, BODY[:1024])

    def test_clipped_response_is_contiguous(self):
        status, headers, body = self.request("/clipped", end=32_767)
        self.assertEqual(status, 206)
        self.assertEqual(headers["Content-Range"], f"bytes 0-16383/{len(BODY)}")
        self.assertEqual(body, BODY[:16_384])

    def test_ignored_range_is_full_file(self):
        status, _, body = self.request("/whole")
        self.assertEqual(status, 200)
        self.assertEqual(body, BODY)

    def test_forbidden_is_zero_length(self):
        status, _, body = self.request("/forbidden")
        self.assertEqual((status, body), (403, b""))

    def test_truncated_response_is_incomplete(self):
        with self.assertRaises(http.client.IncompleteRead):
            self.request("/truncated")

    def test_custom_media_uses_its_actual_length_and_bytes(self):
        custom = PREFIX + b"local-aac-fixture" * 41
        server = AudioServer(("127.0.0.1", 0), body=custom)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        try:
            connection = http.client.HTTPConnection(*server.server_address, timeout=3)
            connection.request("GET", "/range", headers={"Range": "bytes=24-1023"})
            response = connection.getresponse()
            self.assertEqual(response.status, 206)
            self.assertEqual(response.getheader("Content-Range"), f"bytes 24-{len(custom) - 1}/{len(custom)}")
            self.assertEqual(response.read(), custom[24:])
            connection.close()
        finally:
            server.shutdown()
            server.server_close()
            thread.join()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--port", type=int, default=0)
    parser.add_argument("--media", type=Path, help="Serve bytes from a local audio file instead of synthetic data")
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    if args.self_test:
        result = unittest.TextTestRunner().run(unittest.defaultTestLoader.loadTestsFromTestCase(FixtureSelfTests))
        return 0 if result.wasSuccessful() else 1
    body = args.media.read_bytes() if args.media else BODY
    if not body:
        parser.error("--media must contain a nonempty audio file")
    server = AudioServer(("127.0.0.1", args.port), body=body)
    print(json.dumps({"port": server.server_port}), flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
