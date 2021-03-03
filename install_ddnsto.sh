#!/bin/sh

PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin:~/bin
export PATH

version="1.0"
APP_URL='http://firmware.koolshare.cn/binary/ddnsto/openwrt'
app_arm='ddnsto_arm.ipk'
app_aarch64='ddnsto_aarch64.ipk'
app_mips='ddnsto_mipsel.ipk'
app_x86='ddnsto_x86_64.ipk'
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

clean_app(){
    rm -f /tmp/${app_x86} /tmp/${app_arm} /tmp/${app_aarch64} /tmp/${app_mips} /tmp/${app_ui} /tmp/${app_lng}
}

command_exists opkg || {
    error "The program only supports Openwrt."
    clean_app
    exit 1
}

if echo `uname -m` | grep -Eqi 'x86_64'; then
    arch='x86_64'
    ( set -x; Download_Files ${APP_URL}/${app_x86} /tmp/${app_x86};
      Download_Files ${APP_URL}/${app_ui} /tmp/${app_ui};
      Download_Files ${APP_URL}/${app_lng} /tmp/${app_lng};
      opkg install /tmp/${app_x86};
      opkg install /tmp/${app_ui};
      opkg install /tmp/${app_lng}; )
elif  echo `uname -m` | grep -Eqi 'arm'; then
    arch='arm'
    ( set -x; Download_Files ${APP_URL}/${app_arm} /tmp/${app_arm};
      Download_Files ${APP_URL}/${app_ui} /tmp/${app_ui};
      Download_Files ${APP_URL}/${app_lng} /tmp/${app_lng};
      opkg install /tmp/${app_arm};
      opkg install /tmp/${app_ui};
      opkg install /tmp/${app_lng}; )
elif  echo `uname -m` | grep -Eqi 'aarch64'; then
    arch='aarch64'
    ( set -x; Download_Files ${APP_URL}/${app_aarch64} /tmp/${app_aarch64};
      Download_Files ${APP_URL}/${app_ui} /tmp/${app_ui};
      Download_Files ${APP_URL}/${app_lng} /tmp/${app_lng};
      opkg install /tmp/${app_aarch64};
      opkg install /tmp/${app_ui};
      opkg install /tmp/${app_lng}; )
elif  echo `uname -m` | grep -Eqi 'mipsel|mips'; then
    arch='mips'
    ( set -x; Download_Files ${APP_URL}/${app_mips} /tmp/${app_mips};
      Download_Files ${APP_URL}/${app_ui} /tmp/${app_ui};
      Download_Files ${APP_URL}/${app_lng} /tmp/${app_lng};
      opkg install /tmp/${app_mips};
      opkg install /tmp/${app_ui};
      opkg install /tmp/${app_lng}; )
else
    error "The program only supports Openwrt."
    exit 1
fi
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
clean_app

