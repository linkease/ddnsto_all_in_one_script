#!/bin/bash

set -euo pipefail

BASE_URL_PRIMARY="https://fw.kspeeder.com/binary/fastnet"
BASE_URL_FALLBACK="https://fw.koolcenter.com/binary/fastnet"

ARCH=$(uname -m)
case "$ARCH" in
    "x86_64")
        ARCH_SUFFIX="amd64"
        SHA_KEY="FASTNET_AMD64_SHA256"
        ;;
    "aarch64"|"arm64")
        ARCH_SUFFIX="arm64"
        SHA_KEY="FASTNET_ARM64_SHA256"
        ;;
    "armv7l"|"armv7")
        ARCH_SUFFIX="armv7"
        SHA_KEY="FASTNET_ARMV7_SHA256"
        ;;
    *)
        echo "Unsupported architecture: $ARCH"
        exit 1
        ;;
esac

if [ -d "/root" ]; then
  TEMP_DIR="/root"
else
  TEMP_DIR=$(mktemp -d 2>/dev/null || mktemp -d -t 'fastnet')
fi

cleanup() {
    rm -f "/tmp/fastnet-install.sh"
}
trap cleanup EXIT

download_nocache_once() {
    local url=$1
    local dest=$2

    if curl -fsSL -H 'Cache-Control: no-cache' -H 'Pragma: no-cache' -o "$dest" "$url"; then
        return 0
    fi

    if wget --no-cache --header='Cache-Control: no-cache' --header='Pragma: no-cache' -O "$dest" "$url"; then
        return 0
    fi

    return 1
}

download_file_once() {
    local url=$1
    local dest=$2

    if curl -fL -o "$dest" "$url"; then
        return 0
    fi

    if wget -O "$dest" "$url"; then
        return 0
    fi

    return 1
}

calc_sha256() {
    local file=$1
    local out
    if out=$(sha256sum "$file" 2>/dev/null); then
        printf '%s\n' "$out" | awk '{print $1}'
        return 0
    fi
    if out=$(shasum -a 256 "$file" 2>/dev/null); then
        printf '%s\n' "$out" | awk '{print $1}'
        return 0
    fi
    if out=$(openssl dgst -sha256 "$file" 2>/dev/null); then
        printf '%s\n' "$out" | awk '{print $2}'
        return 0
    fi

    echo "sha256sum, shasum, or openssl is required for checksum verification." >&2
    exit 1
}

download_with_fallback() {
    local path=$1
    local dest=$2
    local nocache=${3:-0}

    for base in "$BASE_URL_PRIMARY" "$BASE_URL_FALLBACK"; do
        local url="${base}/${path}"
        if [ "$nocache" -eq 1 ]; then
            if download_nocache_once "$url" "$dest"; then
                return 0
            fi
        else
            if download_file_once "$url" "$dest"; then
                return 0
            fi
        fi
    done

    echo "Failed to download ${path} from all mirrors." >&2
    return 1
}

VERSION_FILE="$TEMP_DIR/version.txt"
download_with_fallback "version.txt" "$VERSION_FILE" 1

VERSION=$(awk -F= '/^VERSION=/{print $2;exit}' "$VERSION_FILE")
EXPECTED_SHA=$(awk -F= -v key="$SHA_KEY" '$1==key{print $2;exit}' "$VERSION_FILE")

if [ -z "$VERSION" ] || [ -z "$EXPECTED_SHA" ]; then
    echo "version.txt is missing VERSION or $SHA_KEY." >&2
    exit 1
fi

BINARY_NAME="FastNet-${VERSION}.${ARCH_SUFFIX}"
BINARY_URL="${BASE_URL_PRIMARY}/${BINARY_NAME}"
CACHE_FILE="$TEMP_DIR/${BINARY_NAME}"

needs_download=1
if [ -f "$CACHE_FILE" ]; then
    LOCAL_SHA=$(calc_sha256 "$CACHE_FILE")
    if [ "$LOCAL_SHA" = "$EXPECTED_SHA" ]; then
        needs_download=0
    else
        rm -f "$CACHE_FILE"
    fi
fi

if [ "$needs_download" -eq 1 ]; then
    TMP_FILE="${CACHE_FILE}.tmp"
    download_with_fallback "$BINARY_NAME" "$TMP_FILE"

    LOCAL_SHA=$(calc_sha256 "$TMP_FILE")
    if [ "$LOCAL_SHA" != "$EXPECTED_SHA" ]; then
        echo "Checksum mismatch for downloaded FastNet ($ARCH_SUFFIX)." >&2
        rm -f "$TMP_FILE"
        exit 1
    fi

    mv "$TMP_FILE" "$CACHE_FILE"
    chmod +x "$CACHE_FILE"
fi

"$CACHE_FILE" version
"$CACHE_FILE" "$@"
