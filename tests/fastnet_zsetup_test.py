#!/usr/bin/env python3
"""The single FastNet installer enters business mode through zsetup and preserves its cache."""

from __future__ import annotations

import hashlib
import http.server
import os
import ssl
import subprocess
import sys
import tempfile
import threading
from pathlib import Path


SCRIPT = Path(__file__).resolve().parents[1] / "fastnet-install.sh"
ZSETUP = Path(sys.argv[1])
TUNNEL_ROOT = Path(sys.argv[2])
CERT_DIR = TUNNEL_ROOT / "runtime-zig/third-part/mbedtls/framework/data_files"
BINARY = b"""#!/bin/sh
if [ "${1:-}" = version ]; then echo 'FastNet fixture'; exit 0; fi
printf '%s\n' "$*" > "$FASTNET_TEST_OUTPUT"
"""
VERSION = (
    "VERSION=1.2.3\n"
    f"FASTNET_AMD64_SHA256={hashlib.sha256(BINARY).hexdigest()}\n"
    f"FASTNET_ARM64_SHA256={hashlib.sha256(BINARY).hexdigest()}\n"
    f"FASTNET_ARMV7_SHA256={hashlib.sha256(BINARY).hexdigest()}\n"
).encode()
BUSINESS = SCRIPT.read_bytes()


class Handler(http.server.BaseHTTPRequestHandler):
    counts: dict[str, int] = {}
    no_cache = False

    def do_GET(self) -> None:  # noqa: N802
        type(self).counts[self.path] = type(self).counts.get(self.path, 0) + 1
        if self.path == "/binary/fastnet/version.txt":
            body = VERSION
            type(self).no_cache = self.headers.get("Cache-Control") == "no-cache"
        elif self.path == "/binary/fastnet/FastNet-1.2.3.amd64":
            body = BINARY
        elif self.path == "/binary/fastnet/install.sh":
            body = BUSINESS
        else:
            self.send_error(404)
            return
        self.send_response(200)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *_args: object) -> None:
        return


def main() -> None:
    server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    tls = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    tls.load_cert_chain(CERT_DIR / "server5.crt", CERT_DIR / "server5.key")
    server.socket = tls.wrap_socket(server.socket, server_side=True)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    try:
        with tempfile.TemporaryDirectory(prefix="fastnet-zsetup-") as tmp_text:
            tmp = Path(tmp_text)
            output = tmp / "args"
            base = f"https://localhost:{server.server_address[1]}/binary"
            config = {
                "schema_version": 1,
                "config_version": "fastnet-fixture-1",
                "source_groups": [{"id": "fixture", "primary_bases": [base]}],
                "stable_zsetup": {
                    "version": "0.2.0", "source_group": "fixture",
                    "artifacts": [{"arch": "x86_64", "path": "zsetup/unused", "sha256": "00" * 32, "size": 1}],
                },
                "installers": [{
                    "application": "fastnet", "os": "*", "package_manager": "*", "arch": "*",
                    "source_group": "fixture", "path": "fastnet/install.sh",
                    "sha256": hashlib.sha256(BUSINESS).hexdigest(), "size": len(BUSINESS),
                    "background": False, "min_version": "0.2.0",
                }],
            }
            config_path = tmp / "config.json"
            import json
            config_path.write_text(json.dumps(config), encoding="utf-8")
            trap_bin = tmp / "bin"
            trap_bin.mkdir()
            for name in ("curl", "wget"):
                trap = trap_bin / name
                trap.write_text("#!/bin/sh\nexit 97\n", encoding="utf-8")
                trap.chmod(0o755)
            env = os.environ | {
                "ZSETUP_BIN": str(ZSETUP),
                "ZSETUP_ARCH": "x86_64",
                "ZSETUP_CA_FILE": str(CERT_DIR / "test-ca2.crt"),
                "ZSETUP_WORK_DIR": str(tmp / "work"),
                "FASTNET_TEST_OUTPUT": str(output),
                "ZSETUP_CONFIG": str(config_path),
                "ZSETUP_CONFIG_CACHE": str(tmp / "config-cache.json"),
                "ZSETUP_MANAGED_ROOT": str(tmp / "managed"),
                "PATH": f"{trap_bin}:/usr/bin:/bin",
            }
            first = subprocess.run([str(ZSETUP), "install", "fastnet", "--foreground", "--", "one", "two"], env=env, text=True, capture_output=True, timeout=10)
            assert first.returncode == 0, first
            assert output.read_text(encoding="utf-8").strip() == "one two"
            assert Handler.no_cache
            assert Handler.counts["/binary/fastnet/FastNet-1.2.3.amd64"] == 1

            output.unlink()
            second = subprocess.run([str(ZSETUP), "install", "fastnet", "--foreground", "--", "again"], env=env, text=True, capture_output=True, timeout=10)
            assert second.returncode == 0, second
            assert output.read_text(encoding="utf-8").strip() == "again"
            assert Handler.counts["/binary/fastnet/FastNet-1.2.3.amd64"] == 1
    finally:
        server.shutdown()
        server.server_close()
        thread.join(timeout=2)

    print("FastNet single installer: zsetup mode, metadata, verified binary, args and reuse passed")


if __name__ == "__main__":
    main()
