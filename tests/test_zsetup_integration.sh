#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
release_dir=${1:?usage: test_zsetup_integration.sh ZSETUP_RELEASE_DIR}
tmp=$(mktemp -d "${TMPDIR:-/tmp}/ddnsto-zsetup-test.XXXXXX")
trap 'rm -rf "$tmp"' EXIT HUP INT TERM

expected=$(sha256sum "$release_dir/zsetup-linux-x86_64" | awk '{print $1}')
grep -Fq "expected='$expected'" "$root/install_ddnsto.sh"
! grep -Eq 'start-stop-daemon|(^|[^a-z])(curl|wget)([^a-z]|$)' "$root/install_ddnsto_business.sh"

cat > "$tmp/zsetup" <<'EOF'
#!/bin/sh
echo "$*" >> "$TEST_LOG"
case "$1" in
  context) echo opkg ;;
  download)
    shift
    [ "$1" = -o ]
    printf 'fixture\n' > "$2"
    ;;
  run)
    printf '321\n' > /tmp/ddnsto-upgrade.pid
    printf '0\n' > /tmp/ddnsto-upgrade.result
    ;;
esac
EOF
cat > "$tmp/opkg" <<'EOF'
#!/bin/sh
echo "opkg $*" >> "$TEST_LOG"
EOF
chmod 0755 "$tmp/zsetup" "$tmp/opkg"

TEST_LOG="$tmp/log" PATH="$tmp:$PATH" ZSETUP_BIN="$tmp/zsetup" \
  ZSETUP_PACKAGE_MANAGER=opkg ZSETUP_ARCH=x86_64 \
  sh "$root/install_ddnsto_business.sh"

[ "$(grep -c '^download ' "$tmp/log")" -eq 3 ]
grep -Fq 'run --background' "$tmp/log"
grep -Fq 'fw.koolcenter.com' "$tmp/log"
grep -Fq 'fw0.koolcenter.com' "$tmp/log"
echo "DDNSTO zsetup bootstrap/business contract passed"
