#!/bin/sh
set -eu

WORK_ROOT=${ZSETUP_ROOT:-/tmp/zsetup}
DEFAULT_PRIMARY_BASES="https://dl.istoreos.com/binary https://fw.d4ctech.com/binary https://fw20.koolcenter.com/binary"
DEFAULT_FALLBACK_BASE="https://fw.koolcenter.com/binary"
if [ -n "${ZSETUP_BOOTSTRAP_BASES:-}" ]; then
    BOOTSTRAP_BASES=$ZSETUP_BOOTSTRAP_BASES
    DIRECT_PRIMARY_BASES=$ZSETUP_BOOTSTRAP_BASES
    DIRECT_FALLBACK_BASE=
else
    BOOTSTRAP_BASES="$DEFAULT_PRIMARY_BASES $DEFAULT_FALLBACK_BASE"
    DIRECT_PRIMARY_BASES=$DEFAULT_PRIMARY_BASES
    DIRECT_FALLBACK_BASE=$DEFAULT_FALLBACK_BASE
fi
INSECURE_CONFIRMED=0

bootstrap_arch() {
    case "$(uname -m 2>/dev/null || true)" in
        x86_64|amd64) ZSETUP_ARCH=x86_64 ;;
        aarch64|arm64) ZSETUP_ARCH=aarch64 ;;
        armv7l|armv7) ZSETUP_ARCH=armv7 ;;
        mipsel|mipsle) ZSETUP_ARCH=mipsel ;;
        *) echo "zsetup: unsupported architecture" >&2; return 2 ;;
    esac
    ZSETUP_ARTIFACT="zsetup-linux-$ZSETUP_ARCH"
}

bootstrap_url() {
    scheme=$1
    base=$2
    path=$3
    authority_path=${base#*://}
    printf '%s://%s/%s\n' "$scheme" "${authority_path%/}" "$path"
}

bootstrap_fetch_from_base() {
    scheme=$1
    base=$2
    remote_path=$3
    destination=$4
    found=0
    url=$(bootstrap_url "$scheme" "$base" "$remote_path")
    if command -v curl >/dev/null 2>&1; then
        found=1
        unlink "$destination" 2>/dev/null || true
        if curl -fsSL --connect-timeout 10 -o "$destination" "$url"; then
            return 0
        fi
    fi
    if command -v wget >/dev/null 2>&1; then
        found=1
        unlink "$destination" 2>/dev/null || true
        if wget -q -T 10 -O "$destination" "$url"; then
            return 0
        fi
    fi
    [ "$found" -eq 1 ] || echo "zsetup: curl or wget is required for first bootstrap" >&2
    return 1
}

bootstrap_fetch() {
    scheme=$1
    remote_path=$2
    destination=$3
    for base in $BOOTSTRAP_BASES; do
        if bootstrap_fetch_from_base "$scheme" "$base" "$remote_path" "$destination"; then
            return 0
        fi
    done
    return 1
}

confirm_insecure_http() {
    [ "$INSECURE_CONFIRMED" -eq 0 ] || return 0
    echo "zsetup: all HTTPS bootstrap sources failed." >&2
    echo "WARNING: HTTP can be intercepted; both zsetup and checksum metadata may be replaced." >&2
    printf 'Continue with insecure HTTP bootstrap? [y/N] ' >&2
    confirm_file=${ZSETUP_CONFIRM_FILE:-/dev/tty}
    answer=
    if ! IFS= read -r answer < "$confirm_file"; then
        echo >&2
        echo "zsetup: HTTP bootstrap refused because no interactive confirmation is available" >&2
        return 1
    fi
    case "$answer" in
        y|Y|yes|YES) INSECURE_CONFIRMED=1; echo "zsetup: user accepted insecure HTTP bootstrap" >&2 ;;
        *) echo "zsetup: insecure HTTP bootstrap declined" >&2; return 1 ;;
    esac
}

read_stable_version() {
    file=$1
    IFS= read -r RESCUE_VERSION < "$file" || return 1
    case "$RESCUE_VERSION" in
        ''|*[!0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz._+-]*) return 1 ;;
    esac
    [ -n "$RESCUE_VERSION" ]
}

read_expected_sha256() {
    file=$1
    EXPECTED_SHA256=
    while IFS=' ' read -r digest name remainder; do
        name=${name#\*}
        if [ "$name" = "$ZSETUP_ARTIFACT" ] && [ -z "${remainder:-}" ]; then
            EXPECTED_SHA256=$digest
            break
        fi
    done < "$file"
    [ "${#EXPECTED_SHA256}" -eq 64 ] || return 1
    case "$EXPECTED_SHA256" in *[!0123456789abcdefABCDEF]*) return 1 ;; esac
}

have_hash_tool() {
    command -v sha256sum >/dev/null 2>&1 || command -v openssl >/dev/null 2>&1
}

hash_matches() {
    [ -f "$1" ] || return 1
    if [ -z "${EXPECTED_SHA256:-}" ]; then
        echo "zsetup: bootstrap SHA-256 verification skipped; HTTPS transport remains required" >&2
        return 0
    fi
    if command -v sha256sum >/dev/null 2>&1; then
        actual=$(sha256sum "$1")
        actual=${actual%% *}
    elif command -v openssl >/dev/null 2>&1; then
        actual=$(openssl dgst -sha256 "$1")
        actual=${actual##*= }
    else
        echo "zsetup: bootstrap SHA-256 tool disappeared before verification" >&2
        return 1
    fi
    [ "$actual" = "$EXPECTED_SHA256" ]
}

is_expected_zsetup() {
    [ -x "$1" ] && [ "$("$1" --version 2>/dev/null || true)" = "zsetup $RESCUE_VERSION" ]
}

find_existing_zsetup() {
    if [ -n "${ZSETUP_BIN:-}" ] && is_expected_zsetup "$ZSETUP_BIN"; then
        ACTIVE_ZSETUP=$ZSETUP_BIN
        return 0
    fi
    if is_expected_zsetup "$WORK_ROOT/rescue/$RESCUE_VERSION/zsetup"; then
        ACTIVE_ZSETUP="$WORK_ROOT/rescue/$RESCUE_VERSION/zsetup"
        return 0
    fi
    if command -v zsetup >/dev/null 2>&1; then
        system_zsetup=$(command -v zsetup)
        if is_expected_zsetup "$system_zsetup"; then
            ACTIVE_ZSETUP=$system_zsetup
            return 0
        fi
    fi
    return 1
}

fetch_bootstrap_metadata() {
    scheme=$1
    stable_file=$2
    sums_file=$3
    for base in $BOOTSTRAP_BASES; do
        bootstrap_fetch_from_base "$scheme" "$base" zsetup/stable "$stable_file" || continue
        read_stable_version "$stable_file" || continue
        EXPECTED_SHA256=
        if have_hash_tool && bootstrap_fetch_from_base "$scheme" "$base" "zsetup/$RESCUE_VERSION/SHA256SUMS" "$sums_file"; then
            read_expected_sha256 "$sums_file" || EXPECTED_SHA256=
        fi
        return 0
    done
    echo "zsetup: no source returned valid stable metadata over $scheme" >&2
    return 1
}

bootstrap_zsetup() {
    bootstrap_arch
    state_dir="$WORK_ROOT/bootstrap"
    mkdir -p "$state_dir"
    stable_file="$state_dir/.stable.$$"
    sums_file="$state_dir/.SHA256SUMS.$$"
    trap 'unlink "$stable_file" "$sums_file" "${candidate:-}" 2>/dev/null || true' EXIT HUP INT TERM

    metadata_scheme=https
    if ! fetch_bootstrap_metadata https "$stable_file" "$sums_file"; then
        confirm_insecure_http
        metadata_scheme=http
        fetch_bootstrap_metadata http "$stable_file" "$sums_file"
    fi

    if find_existing_zsetup; then
        trap - EXIT HUP INT TERM
        unlink "$stable_file" "$sums_file" 2>/dev/null || true
        return 0
    fi

    rescue_dir="$WORK_ROOT/rescue/$RESCUE_VERSION"
    rescue_bin="$rescue_dir/zsetup"
    candidate="$rescue_dir/.zsetup-download.$$"
    mkdir -p "$rescue_dir"
    if ! bootstrap_fetch https "zsetup/$RESCUE_VERSION/$ZSETUP_ARTIFACT" "$candidate"; then
        confirm_insecure_http
        bootstrap_fetch http "zsetup/$RESCUE_VERSION/$ZSETUP_ARTIFACT" "$candidate"
    fi
    hash_matches "$candidate" || {
        echo "zsetup: bootstrap checksum mismatch" >&2
        return 1
    }
    chmod 0755 "$candidate"
    is_expected_zsetup "$candidate" || {
        echo "zsetup: downloaded bootstrap has the wrong product or version" >&2
        return 1
    }
    mv -f "$candidate" "$rescue_bin"
    ACTIVE_ZSETUP=$rescue_bin
    trap - EXIT HUP INT TERM
    unlink "$stable_file" "$sums_file" 2>/dev/null || true
    [ "$metadata_scheme" = https ] || echo "zsetup: insecure HTTP bootstrap completed with user consent" >&2
}

bootstrap_and_run() {
    bootstrap_zsetup
    ZSETUP_BIN=$ACTIVE_ZSETUP
    ZSETUP_SOURCE_BASES=${ZSETUP_SOURCE_BASES:-$DIRECT_PRIMARY_BASES}
    ZSETUP_SOURCE_FALLBACK=${ZSETUP_SOURCE_FALLBACK:-$DIRECT_FALLBACK_BASE}
    export ZSETUP_BIN ZSETUP_ARCH ZSETUP_SOURCE_BASES ZSETUP_SOURCE_FALLBACK
    fastnet_install "$@"
}

fastnet_download() {
    remote_path=$1
    destination=$2
    expected_sha=${3:-}
    no_cache=${4:-0}
    set -- "$ZSETUP_BIN" download -o "$destination"
    [ -z "$expected_sha" ] || set -- "$@" --sha256 "$expected_sha"
    [ "$no_cache" -eq 0 ] || set -- "$@" --no-cache
    [ -z "${ZSETUP_CA_FILE:-}" ] || set -- "$@" --ca-file "$ZSETUP_CA_FILE"
    for base in $ZSETUP_SOURCE_BASES; do
        set -- "$@" "${base%/}/fastnet/$remote_path"
    done
    [ -z "${ZSETUP_SOURCE_FALLBACK:-}" ] || set -- "$@" --fallback-url "${ZSETUP_SOURCE_FALLBACK%/}/fastnet/$remote_path"
    "$@"
}

fastnet_install() {
    : "${ZSETUP_BIN:?zsetup is required}"
    : "${ZSETUP_SOURCE_BASES:?zsetup source group is required}"
    case "${ZSETUP_ARCH:-$(uname -m)}" in
        x86_64|amd64) arch_suffix=amd64; sha_key=FASTNET_AMD64_SHA256 ;;
        aarch64|arm64) arch_suffix=arm64; sha_key=FASTNET_ARM64_SHA256 ;;
        armv7l|armv7) arch_suffix=armv7; sha_key=FASTNET_ARMV7_SHA256 ;;
        *) echo "FastNet: unsupported architecture" >&2; return 2 ;;
    esac

    work_dir=${ZSETUP_WORK_DIR:-/tmp/zsetup/fastnet}
    mkdir -p "$work_dir"
    version_file="$work_dir/version.txt"
    fastnet_download version.txt "$version_file" "" 1
    version=$(sed -n 's/^VERSION=//p' "$version_file" | sed -n '1p')
    expected_sha=$(sed -n "s/^${sha_key}=//p" "$version_file" | sed -n '1p')
    if [ -z "$version" ] || [ -z "$expected_sha" ]; then
        echo "FastNet: version metadata is incomplete" >&2
        return 11
    fi

    binary_name="FastNet-${version}.${arch_suffix}"
    cache_file="$work_dir/$binary_name"
    if [ ! -x "$cache_file" ] || ! "$cache_file" version >/dev/null 2>&1; then
        candidate="$work_dir/.${binary_name}.candidate.$$"
        trap 'unlink "$candidate" 2>/dev/null || true' EXIT HUP INT TERM
        fastnet_download "$binary_name" "$candidate" "$expected_sha" 0
        chmod 0755 "$candidate"
        "$candidate" version >/dev/null
        mv -f "$candidate" "$cache_file"
        trap - EXIT HUP INT TERM
    fi
    "$cache_file" version
    exec "$cache_file" "$@"
}

main() {
    if [ "${ZSETUP_INSTALLER_MODE:-0}" = 1 ]; then
        fastnet_install "$@"
    else
        bootstrap_and_run "$@"
    fi
}

main "$@"
