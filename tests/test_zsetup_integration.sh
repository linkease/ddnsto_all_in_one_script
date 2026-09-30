#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
release_dir=${1:?usage: test_zsetup_integration.sh ZSETUP_RELEASE_DIR}
tmp=$(mktemp -d "${TMPDIR:-/tmp}/ddnsto-zsetup-test.XXXXXX")
trap 'rm -rf "$tmp"' EXIT HUP INT TERM

expected=$(sha256sum "$release_dir/zsetup-linux-x86_64" | awk '{print $1}')
grep -Fq "expected='$expected'" "$root/install_ddnsto.sh"
grep -Fq 'binary/zsetup/$ZSETUP_VERSION/$artifact' "$root/install_ddnsto.sh"
! grep -Fq 'binary/zsetup/releases/' "$root/install_ddnsto.sh"
grep -Fq 'https://dl.istoreos.com' "$root/install_ddnsto.sh"
grep -Fq 'https://fw.d4ctech.com' "$root/install_ddnsto.sh"
grep -Fq 'https://fw20.koolcenter.com' "$root/install_ddnsto.sh"
grep -Fq 'https://fw.koolcenter.com' "$root/install_ddnsto.sh"
! grep -Fq 'fw0.koolcenter.com' "$root/install_ddnsto.sh"
! grep -Eq 'start-stop-daemon|(^|[^a-z])(curl|wget)([^a-z]|$)' "$root/install_ddnsto_business.sh"

mkdir -p "$tmp/bootstrap-bin" "$tmp/bootstrap"
cat > "$tmp/bootstrap-bin/uname" <<'EOF'
#!/bin/sh
echo x86_64
EOF
cat > "$tmp/bootstrap-bin/curl" <<'EOF'
#!/bin/sh
echo "$2" >> "$TEST_LOG.bootstrap"
cat > "$4" <<'INNER'
#!/bin/sh
echo "zsetup $*" >> "$TEST_LOG.bootstrap"
INNER
EOF
cat > "$tmp/bootstrap-bin/sha256sum" <<'EOF'
#!/bin/sh
count_file="$TEST_LOG.sha-count"
count=0
[ ! -f "$count_file" ] || count=$(cat "$count_file")
count=$((count + 1))
echo "$count" > "$count_file"
if [ "$count" -eq 1 ]; then
  printf '%064d  %s\n' 0 "$1"
else
  printf '%s  %s\n' "$EXPECTED_ZSETUP_SHA" "$1"
fi
EOF
chmod 0755 "$tmp/bootstrap-bin/"*
TEST_LOG="$tmp/bootstrap-log" EXPECTED_ZSETUP_SHA="$expected" \
  PATH="$tmp/bootstrap-bin:$PATH" ZSETUP_DIR="$tmp/bootstrap" \
  sh "$root/install_ddnsto.sh"
grep -Fq 'https://dl.istoreos.com/' "$tmp/bootstrap-log.bootstrap"
grep -Fq 'https://fw.d4ctech.com/' "$tmp/bootstrap-log.bootstrap"
! grep -Fq 'https://fw20.koolcenter.com/' "$tmp/bootstrap-log.bootstrap"
grep -Fq 'zsetup install ddnsto' "$tmp/bootstrap-log.bootstrap"

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
grep -Fq -- '--fallback-url' "$tmp/log"
grep -Fq 'dl.istoreos.com' "$tmp/log"
grep -Fq 'fw.d4ctech.com' "$tmp/log"
grep -Fq 'fw20.koolcenter.com' "$tmp/log"
grep -Fq 'fw.koolcenter.com' "$tmp/log"
! grep -Fq 'fw0.koolcenter.com' "$tmp/log"
echo "DDNSTO zsetup bootstrap/business contract passed"
