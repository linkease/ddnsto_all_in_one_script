#!/bin/sh
#
# ddnsto Linux 平台一键安装脚本
# 功能：根据当前系统架构从官方 CDN 下载 ddnsto 压缩包，解压后安装到 /usr/local/bin/ddnsto
#

# ========== 配置项 ==========
# ddnsto 版本号，可通过环境变量 DDNSTO_VERSION 覆盖
DDNSTO_VERSION=${DDNSTO_VERSION:-4.2.3}
# 二进制包下载地址
APP_URL="https://fw0.koolcenter.com/binary/ddnsto/linux-binary"
# 压缩包文件名
APP_PACKAGE="ddnsto-standard-${DDNSTO_VERSION}.tar.gz"
# 压缩包内的顶层目录名
APP_DIR_NAME="ddnsto-standard-${DDNSTO_VERSION}"
# 临时工作目录（脚本退出时自动清理）
TMP_DIR=$(mktemp -d)
# 目标安装路径
BIN_PATH='/usr/local/bin/ddnsto'

# ========== 辅助函数 ==========
# 命令是否存在
command_exists() {
    command -v "$@" >/dev/null 2>&1
}

# 错误输出
error() {
    echo ${RED}"Error: $@"${RESET} >&2
}

# 下载文件：优先 curl，回退 wget
download_files() {
    local URL=$1
    local FileName=$2
    if command_exists curl; then
        curl -sSLk "${URL}" -o "${FileName}"
    elif command_exists wget; then
        wget -c --no-check-certificate "${URL}" -O "${FileName}"
    else
        error "需要 curl 或 wget 工具用于下载"
        exit 1
    fi
}

# 退出时清理临时目录
cleanup() {
    rm -rf "${TMP_DIR}"
}
trap cleanup EXIT INT TERM

# ========== 入口 ==========
echo "get your token from https://www.ddnsto.com"
read -p "please enter your token:" token

# 检测当前用户权限，决定是否使用 sudo
CURR_UID=`id -u`
SUDO=
if [ "${CURR_UID}" = "0" ] ; then
  echo "run as root"
else
  echo "use sudo"
  SUDO=sudo
fi

# 如果已安装，先停止服务
if [ -f "/usr/local/bin/ddnsto" ];then
  echo "ddnsto exist"
  ${SUDO} ddnsto stop
fi

# 根据当前 CPU 架构选择对应的二进制平台
if echo `uname -m` | grep -Eqi 'x86_64'; then
    arch='x86_64'
elif echo `uname -m` | grep -Eqi 'aarch64'; then
    arch='aarch64'
else
    error "The program only supports x86_64 & aarch64."
    exit 1
fi

# 下载压缩包
echo "downloading ${APP_PACKAGE} ..."
download_files "${APP_URL}/${APP_PACKAGE}" "${TMP_DIR}/${APP_PACKAGE}"

# 仅解压当前架构对应的二进制文件
echo "extracting ddnsto.${arch} ..."
if ! tar -xzf "${TMP_DIR}/${APP_PACKAGE}" -C "${TMP_DIR}" "${APP_DIR_NAME}/ddnsto.${arch}"; then
    error "解压失败，请检查压缩包是否正确"
    exit 1
fi

# 移动二进制到目标路径并赋予可执行权限
${SUDO} mv "${TMP_DIR}/${APP_DIR_NAME}/ddnsto.${arch}" "${BIN_PATH}"
${SUDO} chmod +x "${BIN_PATH}"

# 以守护进程模式启动 ddnsto
${SUDO} ddnsto -u $token -daemon

echo "command to stop ddnsto service: systemctl stop com.linkease.ddnstoshell"
