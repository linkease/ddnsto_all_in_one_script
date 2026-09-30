#!/bin/sh
set -eu

ZSETUP_VERSION='0.1.0'
ZSETUP_DIR=${ZSETUP_DIR:-/tmp}
ZSETUP_BIN="$ZSETUP_DIR/zsetup"

case "$(uname -m)" in
    x86_64|amd64)
        artifact='zsetup-linux-x86_64'
        expected='c726dec4b211c1da786424e6f819faa208b28f2342f3a44ab6a649223d09e3a2'
        ;;
    aarch64|arm64)
        artifact='zsetup-linux-aarch64'
        expected='b8eae214bb0a22f5d5405d11c148cf954e339bdb6721dd8dfc7a0d4445ff6ed2'
        ;;
    armv7*|armv8l)
        artifact='zsetup-linux-armv7'
        expected='4189a9bc8bd1a44e6bf78091b4bb453d7cad53db07ac76f692bba6aa94e8c252'
        ;;
    mipsel|mipsle)
        artifact='zsetup-linux-mipsel'
        expected='23eba6b50a94316cc511febcceac88055bfe2fdb9665a9725a5dcc475c5e1e55'
        ;;
    *) echo "Unsupported architecture: $(uname -m)" >&2; exit 1 ;;
esac

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

command -v sha256sum >/dev/null 2>&1 || { echo "sha256sum is required" >&2; exit 1; }
download_verified() {
    for base in \
        'https://dl.istoreos.com' \
        'https://fw.d4ctech.com' \
        'https://fw20.koolcenter.com' \
        'https://fw.koolcenter.com'
    do
        rm -f "$temporary"
        if download "$base/binary/zsetup/$ZSETUP_VERSION/$artifact"; then
            actual=$(sha256sum "$temporary" | awk '{print $1}')
            [ "$actual" = "$expected" ] && return 0
            echo "zsetup SHA-256 mismatch from $base; trying next source" >&2
        fi
    done
    return 1
}

download_verified || { echo "Unable to download a verified zsetup binary" >&2; exit 1; }
chmod 0755 "$temporary"
mv -f "$temporary" "$ZSETUP_BIN"
trap - EXIT HUP INT TERM

exec "$ZSETUP_BIN" install ddnsto "$@"
