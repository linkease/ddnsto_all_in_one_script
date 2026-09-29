#!/bin/sh
set -eu

ZSETUP_VERSION='0.1.0'
ZSETUP_DIR=${ZSETUP_DIR:-/tmp}
ZSETUP_BIN="$ZSETUP_DIR/zsetup"

case "$(uname -m)" in
    x86_64|amd64)
        artifact='zsetup-linux-x86_64'
        expected='9ddb0cc3f80da4b83d278fcf77069b0ce4a354ef04d05a6c3aa4b1971528966f'
        ;;
    aarch64|arm64)
        artifact='zsetup-linux-aarch64'
        expected='92db19c6730d4239e46bf4180578b43936eab5f9fce02812250bb25f398acfac'
        ;;
    armv7*|armv8l)
        artifact='zsetup-linux-armv7'
        expected='64c1adf4f2e6f94d9348f412bc707d500179734aa5a21e4e4e8ba5fc60584e9c'
        ;;
    mipsel|mipsle)
        artifact='zsetup-linux-mipsel'
        expected='8ab2a233d35aa533d184d6b25168431865e7d0ed98f4ff7b798ca881fc074e90'
        ;;
    *) echo "Unsupported architecture: $(uname -m)" >&2; exit 1 ;;
esac

primary="https://fw.koolcenter.com/binary/zsetup/releases/$ZSETUP_VERSION/$artifact"
backup="https://fw0.koolcenter.com/binary/zsetup/releases/$ZSETUP_VERSION/$artifact"
temporary="$ZSETUP_BIN.tmp.$$"
trap 'rm -f "$temporary"' EXIT HUP INT TERM

download() {
    url=$1
    if command -v curl >/dev/null 2>&1; then
        curl -fsSLk "$url" -o "$temporary"
    elif command -v wget >/dev/null 2>&1; then
        wget -q --no-check-certificate "$url" -O "$temporary"
    else
        echo "curl or wget is required to bootstrap zsetup" >&2
        return 1
    fi
}

download "$primary" || download "$backup"
command -v sha256sum >/dev/null 2>&1 || { echo "sha256sum is required" >&2; exit 1; }
actual=$(sha256sum "$temporary" | awk '{print $1}')
[ "$actual" = "$expected" ] || { echo "zsetup SHA-256 mismatch" >&2; exit 1; }
chmod 0755 "$temporary"
mv -f "$temporary" "$ZSETUP_BIN"
trap - EXIT HUP INT TERM

exec "$ZSETUP_BIN" install ddnsto "$@"
