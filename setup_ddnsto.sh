#!/bin/sh

if [ -z "$1" ]; then
    echo "Error: Please provide token as argument. Usage: $0 <DDNSTO_TOKEN>"
    exit 1
fi

TOKEN=$1

echo "Step 1: Installing DDNSTO..."
if command -v curl >/dev/null 2>&1; then
    sh -c "$(curl -sSL http://fw.koolcenter.com/binary/ddnsto/openwrt/install_ddnsto.sh)"
else
    sh -c "$(wget --no-check-certificate -qO- http://fw.koolcenter.com/binary/ddnsto/openwrt/install_ddnsto.sh)"
fi

echo "Step 2: Configuring DDNSTO..."
uci set ddnsto.@ddnsto[0].token="$TOKEN"
uci set ddnsto.@ddnsto[0].enabled='1'
uci commit ddnsto
/etc/init.d/ddnsto restart

echo "Step 3: Verifying DDNSTO status..."
sleep 3

if pgrep -x "/usr/sbin/ddnstod" >/dev/null; then
    echo "DDNSTO is running"
else
    echo "Warning: DDNSTO process not found!"
    exit 1
fi

echo "DDNSTO version and device info:"
/usr/sbin/ddnsto -w

exit 0
