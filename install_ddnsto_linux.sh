#!/bin/sh

version="1.0"
APP_URL='https://fw.koolcenter.com/binary/ddnsto/linux'
app_aarch64='ddnsto.arm64'
app_x86='ddnsto.amd64'
tmp_path='/tmp/ddnsto'
bin_path='/usr/local/bin/ddnsto'

echo "get your token from https://www.ddnsto.com"
read -p "please enter your token:" token
command_exists() {
    command -v "$@" >/dev/null 2>&1
}
error() {
    echo ${RED}"Error: $@"${RESET} >&2
}

UID=`id -u`
SUDO=

if [ "${UID}" = "0" ]] ; then
  echo "run as root"
  SUDO=time
else
  echo "use sudo"
  SUDO=sudo
fi

Download_Files(){
  local URL=$1
  local FileName=$2
  if command_exists curl; then
    curl -sSLk ${URL} -o ${FileName}
  elif command_exists wget; then
    wget -c --no-check-certificate ${URL} -O ${FileName}
  fi
}

if [ -f "/usr/local/bin/ddnsto" ];then
echo `ddnsto exist`
${SUDO} ddnsto stop
fi

if echo `uname -m` | grep -Eqi 'x86_64'; then
    arch='x86_64'
    ( set -x; Download_Files ${APP_URL}/${app_x86} $tmp_path; ${SUDO} mv $tmp_path $bin_path)
elif  echo `uname -m` | grep -Eqi 'aarch64'; then
    arch='aarch64'
    ( set -x; Download_Files ${APP_URL}/${app_aarch64} $tmp_path; ${SUDO} mv $tmp_path $bin_path)
else
    error "The program only supports x86_64 & aarch64."
    exit 1
fi


${SUDO} chmod +x $bin_path
${SUDO} ddnsto -u $token -daemon

echo "stop ddnsto service command: systemctl stop com.linkease.ddnstoshell"

