#!/bin/sh
set -eu

APP_URL_PRIMARY='https://fw.koolcenter.com/binary/ddnsto/openwrt'
APP_URL_BACKUP='https://fw0.koolcenter.com/binary/ddnsto/openwrt'
ZSETUP_BIN=${ZSETUP_BIN:-zsetup}

app_ui='luci-app-ddnsto.ipk'
app_lng='luci-i18n-ddnsto-zh-cn.ipk'
app_binary='ddnsto.ipk'

error() {
    echo "Error: $*" >&2
}

download_file() {
    remote_name=$1
    output=$2
    "$ZSETUP_BIN" download \
        -o "$output" \
        "$APP_URL_PRIMARY/$remote_name" \
        "$APP_URL_BACKUP/$remote_name"
}

cleanup() {
    rm -f "/tmp/$app_binary" "/tmp/$app_ui" "/tmp/$app_lng"
}

package_manager=${ZSETUP_PACKAGE_MANAGER:-$("$ZSETUP_BIN" context get package_manager)}
[ "$package_manager" = opkg ] || {
    error "DDNSTO OpenWrt installer currently requires opkg."
    exit 1
}

arch=${ZSETUP_ARCH:-$("$ZSETUP_BIN" context get arch)}
case "$arch" in
    x86_64) remote_binary='ddnsto_x86_64.ipk' ;;
    aarch64) remote_binary='ddnsto_aarch64.ipk' ;;
    armv7|arm) remote_binary='ddnsto_arm.ipk' ;;
    mipsel) remote_binary='ddnsto_mipsel.ipk' ;;
    *) error "Unsupported OpenWrt architecture: $arch"; exit 1 ;;
esac

trap cleanup EXIT HUP INT TERM
opkg install luci-compat || true
download_file "$remote_binary" "/tmp/$app_binary"
download_file "$app_ui" "/tmp/$app_ui"
download_file "$app_lng" "/tmp/$app_lng"

cat > /tmp/.ddnsto-upgrade.sh <<'EOF'
#!/bin/sh
set -eu
opkg remove app-meta-ddnsto luci-i18n-ddnsto-zh-cn luci-app-ddnsto ddnsto || true
opkg install /tmp/ddnsto.ipk
opkg install /tmp/luci-app-ddnsto.ipk
opkg install /tmp/luci-i18n-ddnsto-zh-cn.ipk
rm -f /tmp/ddnsto.ipk /tmp/luci-app-ddnsto.ipk /tmp/luci-i18n-ddnsto-zh-cn.ipk
ddnsto -v || true
EOF
chmod 0755 /tmp/.ddnsto-upgrade.sh
trap - EXIT HUP INT TERM

"$ZSETUP_BIN" run --background \
    --log /tmp/ddnsto-upgrade.log \
    --pid-file /tmp/ddnsto-upgrade.pid \
    --result-file /tmp/ddnsto-upgrade.result \
    -- /bin/sh /tmp/.ddnsto-upgrade.sh

echo "DDNSTO upgrade started in background; log=/tmp/ddnsto-upgrade.log result=/tmp/ddnsto-upgrade.result"
