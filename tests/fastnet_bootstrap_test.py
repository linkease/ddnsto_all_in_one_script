#!/usr/bin/env python3
"""Single-script bootstrap prefers HTTPS and requires consent before HTTP."""

from __future__ import annotations

import hashlib
import os
import shutil
import subprocess
import tempfile
from pathlib import Path


SCRIPT = Path(__file__).resolve().parents[1] / "fastnet-install.sh"
VERSION = "9.8.7"


def executable(path: Path, text: str) -> None:
    path.write_text(text, encoding="utf-8")
    path.chmod(0o755)


def main() -> None:
    with tempfile.TemporaryDirectory(prefix="fastnet-bootstrap-") as temp_text:
        root = Path(temp_text)
        web = root / "web"
        release = web / f"binary/zsetup/{VERSION}"
        release.mkdir(parents=True)
        (web / "binary/zsetup/stable").write_text(f"{VERSION}\n", encoding="ascii")
        payload = release / "zsetup-linux-x86_64"
        executable(payload, f"""#!/bin/sh
if [ "${{1:-}}" = --version ]; then echo 'zsetup {VERSION}'; exit 0; fi
printf '%s\\n' "$*" >> "$ZSETUP_COMMAND_LOG"
if [ "${{1:-}}" = download ]; then
    shift
    output=
    url=
    while [ "$#" -gt 0 ]; do
        [ "$1" = -o ] && {{ shift; output=$1; shift; continue; }}
        case "$1" in https://*) url=$1 ;; esac
        shift
    done
    cp "$FASTNET_FIXTURES/${{url##*/}}" "$output"
    exit 0
fi
exit 97
""")
        digest = hashlib.sha256(payload.read_bytes()).hexdigest()
        (release / "SHA256SUMS").write_text(f"{digest}  zsetup-linux-x86_64\n", encoding="ascii")
        fastnet_binary = web / "FastNet-1.2.3.amd64"
        executable(fastnet_binary, """#!/bin/sh
if [ "${1:-}" = version ]; then echo 'FastNet fixture'; exit 0; fi
printf '%s\\n' "$*" > "$FASTNET_TEST_LOG"
""")
        fastnet_digest = hashlib.sha256(fastnet_binary.read_bytes()).hexdigest()
        (web / "version.txt").write_text(
            f"VERSION=1.2.3\nFASTNET_AMD64_SHA256={fastnet_digest}\n",
            encoding="ascii",
        )

        fake_bin = root / "bin"
        fake_bin.mkdir()
        executable(fake_bin / "uname", "#!/bin/sh\necho x86_64\n")
        executable(fake_bin / "wget", "#!/bin/sh\nexit 1\n")
        executable(fake_bin / "curl", """#!/bin/sh
out=
url=
while [ "$#" -gt 0 ]; do
    [ "$1" = -o ] && { shift; out=$1; shift; continue; }
    case "$1" in http://*|https://*) url=$1 ;; esac
    shift
done
printf '%s\n' "$url" >> "$FETCH_LOG"
case "$url" in https://*) [ "${FAIL_HTTPS:-0}" = 0 ] || exit 22 ;; esac
case "$url" in
    *bad.test*/zsetup/stable) printf 'not/a/version\n' > "$out"; exit 0 ;;
esac
relative=${url#*://}
relative=${relative#*/}
cp "$WEB_ROOT/$relative" "$out"
""")
        minimal_bin = root / "minimal-bin"
        minimal_bin.mkdir()
        for name in ("sh", "cp", "mkdir", "chmod", "mv", "sed", "unlink"):
            target = shutil.which(name)
            assert target is not None
            (minimal_bin / name).symlink_to(target)
        for name in ("curl", "wget", "uname"):
            (minimal_bin / name).symlink_to(fake_bin / name)

        def run(
            name: str,
            *,
            existing: bool = False,
            fail_https: bool = False,
            answer: str | None = None,
            bases: str = "https://mirror.test/binary",
            without_hash_tools: bool = False,
        ) -> subprocess.CompletedProcess[str]:
            case = root / name
            case.mkdir()
            fetch_log = case / "fetch.log"
            install_log = case / "install.log"
            command_log = case / "zsetup.log"
            env = os.environ | {
                "PATH": str(minimal_bin) if without_hash_tools else f"{fake_bin}:/usr/bin:/bin",
                "WEB_ROOT": str(web),
                "FETCH_LOG": str(fetch_log),
                "ZSETUP_COMMAND_LOG": str(command_log),
                "FASTNET_TEST_LOG": str(install_log),
                "FASTNET_FIXTURES": str(web),
                "ZSETUP_ROOT": str(case / "work"),
                "ZSETUP_BOOTSTRAP_BASES": bases,
                "FAIL_HTTPS": "1" if fail_https else "0",
            }
            if existing:
                existing_bin = case / "existing-zsetup"
                existing_bin.write_bytes(payload.read_bytes())
                existing_bin.chmod(0o755)
                env["ZSETUP_BIN"] = str(existing_bin)
            if answer is not None:
                confirm = case / "confirm"
                confirm.write_text(answer + "\n", encoding="ascii")
                env["ZSETUP_CONFIRM_FILE"] = str(confirm)
            return subprocess.run(["sh", str(SCRIPT), name], env=env, text=True, capture_output=True, timeout=10)

        reused = run("reuse", existing=True)
        assert reused.returncode == 0, reused
        reuse_urls = (root / "reuse/fetch.log").read_text(encoding="utf-8").splitlines()
        assert all(url.startswith("https://") for url in reuse_urls)
        assert not any(url.endswith("zsetup-linux-x86_64") for url in reuse_urls)
        reuse_commands = (root / "reuse/zsetup.log").read_text(encoding="utf-8").splitlines()
        assert reuse_commands and all(command.startswith("download ") for command in reuse_commands)
        assert (root / "reuse/install.log").read_text(encoding="utf-8").strip() == "reuse"

        malformed = run("malformed", bases="https://bad.test/binary https://mirror.test/binary")
        assert malformed.returncode == 0, malformed
        malformed_urls = (root / "malformed/fetch.log").read_text().splitlines()
        assert malformed_urls[0].startswith("https://bad.test/")
        assert any(url.startswith("https://mirror.test/") for url in malformed_urls)
        assert not any(url.startswith("http://") for url in malformed_urls)

        downloaded = run("https")
        assert downloaded.returncode == 0, downloaded
        assert (root / "https/install.log").read_text(encoding="utf-8").strip() == "https"
        https_commands = (root / "https/zsetup.log").read_text(encoding="utf-8").splitlines()
        assert https_commands and all(command.startswith("download ") for command in https_commands)
        assert all(url.startswith("https://") for url in (root / "https/fetch.log").read_text().splitlines())

        no_hash = run("https-no-hash-tools", without_hash_tools=True)
        assert no_hash.returncode == 0, no_hash
        assert (root / "https-no-hash-tools/install.log").read_text().strip() == "https-no-hash-tools"

        sums = release / "SHA256SUMS"
        sums.write_text(f"{'0' * 64}  zsetup-linux-x86_64\n", encoding="ascii")
        mismatch = run("https-checksum-mismatch")
        assert mismatch.returncode != 0 and "checksum mismatch" in mismatch.stderr
        sums.write_text(f"{digest}  zsetup-linux-x86_64\n", encoding="ascii")

        declined = run("decline", fail_https=True, answer="n")
        assert declined.returncode != 0 and "declined" in declined.stderr
        assert not any(url.startswith("http://") for url in (root / "decline/fetch.log").read_text().splitlines())

        accepted = run("accept", fail_https=True, answer="y")
        assert accepted.returncode == 0, accepted
        accept_urls = (root / "accept/fetch.log").read_text().splitlines()
        assert any(url.startswith("http://") for url in accept_urls)
        assert "accepted insecure HTTP bootstrap" in accepted.stderr
        assert (root / "accept/install.log").read_text().strip() == "accept"

    print("FastNet bootstrap: HTTPS, reuse, explicit HTTP decline/consent passed")


if __name__ == "__main__":
    main()
