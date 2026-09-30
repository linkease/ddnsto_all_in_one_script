#!/bin/sh
set -eu

ZSETUP_VERSION='0.1.0'
ZSETUP_DIR=${ZSETUP_DIR:-/tmp}
ZSETUP_BIN="$ZSETUP_DIR/zsetup"

case "$(uname -m)" in
    x86_64|amd64)
        artifact='zsetup-linux-x86_64'
        expected='520c084cd325146afb1bf3462512328a97e93be9c9af0769623843286892f60f'
        ;;
    aarch64|arm64)
        artifact='zsetup-linux-aarch64'
        expected='486267486e23a7c876586b0936989e4c62929377d621dc88618a8fe8b89e2450'
        ;;
    armv7*|armv8l)
        artifact='zsetup-linux-armv7'
        expected='3b2bb095dabf9e27d1f3dfec0798e5c3cc76b35d8c2a8b61d4cc8ce2819f8409'
        ;;
    mipsel|mipsle)
        artifact='zsetup-linux-mipsel'
        expected='6702c5262b2778ceb7ff83e6c597a4bb790ce703be4fac3fbfb50facd6b505d4'
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
