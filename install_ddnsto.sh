#!/bin/sh

PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin:~/bin
export PATH

version="1.0"
APP_URL='http://fw.koolcenter.com/binary/ddnsto/openwrt'
app_arm='ddnsto_arm.ipk'
app_aarch64='ddnsto_aarch64.ipk'
app_mips='ddnsto_mipsel.ipk'
app_x86='ddnsto_x86_64.ipk'
app_binary='ddnsto.ipk'
app_ui='luci-app-ddnsto.ipk'
app_lng='luci-i18n-ddnsto-zh-cn.ipk'

setup_color() {
    # Only use colors if connected to a terminal
    if [ -t 1 ]; then
        RED=$(printf '\033[31m')
        GREEN=$(printf '\033[32m')
        YELLOW=$(printf '\033[33m')
        BLUE=$(printf '\033[34m')
        BOLD=$(printf '\033[1m')
        RESET=$(printf '\033[m')
    else
        RED=""
        GREEN=""
        YELLOW=""
        BLUE=""
        BOLD=""
        RESET=""
    fi
}
setup_color
command_exists() {
    command -v "$@" >/dev/null 2>&1
}
error() {
    echo ${RED}"Error: $@"${RESET} >&2
}

Download_Files(){
  local URL=$1
  local FileName=$2
  if command_exists curl; then
    curl -sSLk ${URL} -o ${FileName}
  elif command_exists wget; then
    wget -c --progress=bar:force --prefer-family=IPv4 --no-check-certificate ${URL} -O ${FileName}
  fi
}

remove_deprecated(){
  if echo `cat /etc/config/ddnsto` | grep -Eqi 'global'; then
    rm /etc/config/ddnsto
  fi
}

clean_app(){
    rm -f /tmp/${app_binary} /tmp/${app_ui} /tmp/${app_lng}
}

fork_ugprade() {

cat <<\EOF >/tmp/.ddnsto-upgrade.sh
#!/bin/sh

      app_binary='ddnsto.ipk'
      app_ui='luci-app-ddnsto.ipk'
      app_lng='luci-i18n-ddnsto-zh-cn.ipk'
      opkg remove app-meta-ddnsto luci-i18n-ddnsto-zh-cn luci-app-ddnsto ddnsto
      opkg install /tmp/${app_binary}
      opkg install /tmp/${app_ui}
      opkg install /tmp/${app_lng}
      rm -f /tmp/${app_binary} /tmp/${app_ui} /tmp/${app_lng}
EOF

chmod 755 /tmp/.ddnsto-upgrade.sh

}

command_exists opkg || {
    error "The program only supports Openwrt."
    clean_app
    exit 1
}

opkg install luci-compat || true

if echo `uname -m` | grep -Eqi 'x86_64'; then
    arch='x86_64'
    ( set -x; Download_Files ${APP_URL}/${app_x86} /tmp/${app_binary};
      Download_Files ${APP_URL}/${app_ui} /tmp/${app_ui};
      Download_Files ${APP_URL}/${app_lng} /tmp/${app_lng}; )
elif  echo `uname -m` | grep -Eqi 'arm'; then
    arch='arm'
    ( set -x; Download_Files ${APP_URL}/${app_arm} /tmp/${app_binary};
      Download_Files ${APP_URL}/${app_ui} /tmp/${app_ui};
      Download_Files ${APP_URL}/${app_lng} /tmp/${app_lng}; )
elif  echo `uname -m` | grep -Eqi 'aarch64'; then
    arch='aarch64'
    ( set -x; Download_Files ${APP_URL}/${app_aarch64} /tmp/${app_binary};
      Download_Files ${APP_URL}/${app_ui} /tmp/${app_ui};
      Download_Files ${APP_URL}/${app_lng} /tmp/${app_lng}; )
elif  echo `uname -m` | grep -Eqi 'mipsel|mips'; then
    arch='mips'
    ( set -x; Download_Files ${APP_URL}/${app_mips} /tmp/${app_binary};
      Download_Files ${APP_URL}/${app_ui} /tmp/${app_ui};
      Download_Files ${APP_URL}/${app_lng} /tmp/${app_lng}; )
else
    error "The program only supports Openwrt."
    exit 1
fi

rm -f /tmp/.ddnsto-upgrade.pid
remove_deprecated
fork_ugprade

if which start-stop-daemon >/dev/null; then
  echo "fork to install, version is:"
  start-stop-daemon -S -b -q -m -x /tmp/.ddnsto-upgrade.sh -p /tmp/.ddnsto-upgrade.pid
  sleep 3
  if [ -f /tmp/.ddnsto-upgrade.pid ]; then

    PID=`cat /tmp/.ddnsto-upgrade.pid`
    if test -d /proc/"${PID}"/; then
      echo "waiting to finish"
      sleep 5
    fi

  fi
else
  echo "install, version is:"
  /tmp/.ddnsto-upgrade.sh
fi

ddnsto -v
RET=$?
if [ "${RET}" = "1" ]; then

printf "$GREEN"
cat <<-'EOF'
  ____  ____  _   _ ____ _____ ___
  |  _ \|  _ \| \ | / ___|_   _/ _ \
  | | | | | | |  \| \___ \ | || | | |
  | |_| | |_| | |\  |___) || || |_| |
  |____/|____/|_| \_|____/ |_| \___/   ....is now installed!


  感谢使用 DDNSTO，请登录 https://www.ddnsto.com 获取 token 填入插件

EOF
printf "$RESET"

else
  error "cannot install ddnsto, ret=${RET}"
fi

