#!/bin/sh

version="2.3"

# 基础URL配置
BASE_URL='http://fw.koolcenter.com/binary/ddnsto/openwrt'

# 版本目录配置
LITE_DIR='lite'
STANDARD_DIR='standard'

# 版本号文件路径（lite 与 standard 各自独立）
LITE_VERSION_FILE="${LITE_VERSION_FILE:-VERSION_LITE}"
STANDARD_VERSION_FILE="${STANDARD_VERSION_FILE:-VERSION}"

# 默认版本号（当无法读取版本文件时使用，按版本类型分别回退）
LITE_VERSION_DEFAULT="4.2.2"
STANDARD_VERSION_DEFAULT="4.2.3"

# 内存阈值配置（MB）- 小于此值使用lite版本，大于等于使用standard版本
MEM_THRESHOLD_MB=900

# 强制使用指定版本（空值表示自动选择）
FORCE_VERSION=""

# 包管理器类型（自动检测）
PKG_MANAGER=""
PKG_EXT="ipk"

# 包名前缀（根据包管理器动态设置）
PKG_PREFIX="ddnsto"

# 包文件名配置（根据包管理器动态设置）
app_arm='ddnsto_arm.ipk'
app_aarch64='ddnsto_aarch64.ipk'
app_mips='ddnsto_mipsel.ipk'
app_x86='ddnsto_x86_64.ipk'
app_binary='ddnsto.ipk'
app_ui='luci-app-ddnsto.ipk'
app_lng='luci-i18n-ddnsto-zh-cn.ipk'

# 颜色设置
setup_color() {
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

info() {
    echo ${BLUE}"Info: $@"${RESET}
}

success() {
    echo ${GREEN}"$@"${RESET}
}

warning() {
    echo ${YELLOW}"Warning: $@"${RESET}
}

# 获取内存大小（MB）
get_mem_mb() {
    if [ -r /proc/meminfo ]; then
        awk '/^MemTotal:/ {printf "%d\n", $2/1024}' /proc/meminfo 2>/dev/null || echo 0
    else
        echo 0
    fi
}

# 远程版本号文件 URL（lite 与 standard 各自独立）
LITE_VERSION_URL="${BASE_URL}/VERSION_LITE"
STANDARD_VERSION_URL="${BASE_URL}/VERSION"

# 读取版本号（优先从远程获取）
# 参数: $1 = 版本类型 (lite 或 standard)，缺省时使用 SELECTED_VERSION
get_version() {
    local version_type="${1:-${SELECTED_VERSION:-standard}}"
    local version_url version_file version_default
    local version_content

    # 根据版本类型选择对应的 URL、本地文件与默认值
    if [ "${version_type}" = "lite" ]; then
        version_url="${LITE_VERSION_URL}"
        version_file="${LITE_VERSION_FILE}"
        version_default="${LITE_VERSION_DEFAULT}"
    else
        version_url="${STANDARD_VERSION_URL}"
        version_file="${STANDARD_VERSION_FILE}"
        version_default="${STANDARD_VERSION_DEFAULT}"
    fi

    # 首先尝试从远程下载版本号文件
    if command_exists curl; then
        version_content=$(curl -fsSLk "${version_url}" 2>/dev/null | tr -d '[:space:]')
    elif command_exists wget; then
        version_content=$(wget -q --no-check-certificate "${version_url}" -O - 2>/dev/null | tr -d '[:space:]')
    fi

    # 如果远程获取成功且不为空，使用远程版本号
    if [ -n "${version_content}" ]; then
        echo "${version_content}"
        return 0
    fi

    # 其次尝试读取本地版本文件
    if [ -f "${version_file}" ]; then
        cat "${version_file}" 2>/dev/null | tr -d '[:space:]' || echo "${version_default}"
    else
        echo "${version_default}"
    fi
}

# 检测包管理器类型
detect_package_manager() {
    if command_exists apk; then
        PKG_MANAGER="apk"
        PKG_EXT="apk"
        PKG_PREFIX="ddnsto"
        info "Detected package manager: apk (OpenWrt V25+)"
    elif command_exists opkg; then
        PKG_MANAGER="opkg"
        PKG_EXT="ipk"
        PKG_PREFIX="ddnsto"
        info "Detected package manager: opkg (OpenWrt V24 or earlier)"
    else
        error "No supported package manager found (apk or opkg)"
        exit 1
    fi
}

# 更新包文件名配置
update_package_names() {
    local ext="$PKG_EXT"
    local prefix="$PKG_PREFIX"
    
    app_arm="${prefix}_arm.${ext}"
    app_aarch64="${prefix}_aarch64.${ext}"
    app_mips="${prefix}_mipsel.${ext}"
    app_x86="${prefix}_x86_64.${ext}"
    app_binary="${prefix}.${ext}"
    
    # LuCI 包根据包管理器选择格式
    if [ "$PKG_MANAGER" = "apk" ]; then
        # APK 系统使用 APK 格式的 LuCI 包
        app_ui='luci-app-ddnsto.apk'
        app_lng='luci-i18n-ddnsto-zh-cn.apk'
    else
        # OPKG 系统使用 IPK 格式的 LuCI 包
        app_ui='luci-app-ddnsto.ipk'
        app_lng='luci-i18n-ddnsto-zh-cn.ipk'
    fi
}

# 选择安装版本（lite 或 standard）
select_version() {
    local mem_mb
    mem_mb="$(get_mem_mb)"

    echo "Device memory: ${mem_mb}MB"
    echo "Device arch: ${arch}"
    echo "Package manager: ${PKG_MANAGER}"
    echo "Package format: ${PKG_EXT}"
    echo "Package prefix: ${PKG_PREFIX}"

    # 如果强制指定版本
    if [ -n "${FORCE_VERSION}" ]; then
        SELECTED_VERSION="${FORCE_VERSION}"
        if [ "${FORCE_VERSION}" = "lite" ]; then
            success "Force install Lite version"
        elif [ "${FORCE_VERSION}" = "standard" ]; then
            success "Force install Standard version"
        fi
        return 0
    fi

    # 根据内存自动选择版本
    if [ "${mem_mb}" -gt 0 ] && [ "${mem_mb}" -lt "${MEM_THRESHOLD_MB}" ]; then
        SELECTED_VERSION="lite"
        warning "Detected low memory: ${mem_mb}MB (<${MEM_THRESHOLD_MB}MB), use Lite version (lightweight)"
    else
        SELECTED_VERSION="standard"
        success "Use Standard version (full-featured)"
    fi
}

# 获取当前选定版本（lite/standard）对应的版本号
get_version_number() {
    get_version "${SELECTED_VERSION}"
}

# 构建下载URL
build_download_url() {
    local pkg_file="$1"
    local version_num
    version_num="$(get_version_number)"

    if [ "${SELECTED_VERSION}" = "lite" ]; then
        # APK 格式使用 lite-apk 目录
        if [ "$PKG_EXT" = "apk" ]; then
            echo "${BASE_URL}/${LITE_DIR}-apk/${version_num}/${pkg_file}"
        else
            echo "${BASE_URL}/${LITE_DIR}/${version_num}/${pkg_file}"
        fi
    else
        # APK 格式使用 standard-apk 目录
        if [ "$PKG_EXT" = "apk" ]; then
            echo "${BASE_URL}/${STANDARD_DIR}-apk/${version_num}/${pkg_file}"
        else
            echo "${BASE_URL}/${STANDARD_DIR}/${version_num}/${pkg_file}"
        fi
    fi
}

# 下载文件
Download_Files(){
    local URL=$1
    local FileName=$2
    if command_exists curl; then
        curl -fsSLk "${URL}" -o "${FileName}"
    elif command_exists wget; then
        wget -q --no-check-certificate "${URL}" -O "${FileName}"
    else
        error "curl or wget is required"
        return 1
    fi
    if [ ! -s "${FileName}" ]; then
        error "download failed: ${URL}"
        return 1
    fi
}

# 清理旧配置
remove_deprecated(){
    if [ -f /etc/config/ddnsto ] && grep -Eqi 'global' /etc/config/ddnsto; then
        rm -f /etc/config/ddnsto
    fi
}

# 清理临时文件
clean_app(){
    rm -f /tmp/${app_binary} /tmp/${app_ui} /tmp/${app_lng}
}

# 创建升级脚本
fork_upgrade() {
    local version_num
    version_num="$(get_version_number)"

    # 根据包管理器生成不同的安装命令
    local remove_cmd=""
    local install_cmd=""

    if [ "$PKG_MANAGER" = "apk" ]; then
        # APK 包管理器
        remove_cmd="apk del app-meta-ddnsto luci-i18n-ddnsto-zh-cn luci-app-ddnsto ddnsto 2>/dev/null || true"
        install_cmd="apk add --allow-untrusted"
    else
        # OPKG 包管理器
        remove_cmd="opkg remove app-meta-ddnsto luci-i18n-ddnsto-zh-cn luci-app-ddnsto ddnsto 2>/dev/null || true"
        install_cmd="opkg install"
    fi

    local ddnsto_cmd="ddnsto"

    cat <<EOF >/tmp/.ddnsto-upgrade.sh
#!/bin/sh

app_binary='${app_binary}'
app_ui='${app_ui}'
app_lng='${app_lng}'
selected_version='${SELECTED_VERSION}'
version_num='${version_num}'

# 日志文件
LOG_FILE="/tmp/.ddnsto-upgrade.log"

echo "Installing DDNSTO \${selected_version} version (\${version_num})..." | tee -a "\${LOG_FILE}"

# 检查文件是否存在
for f in "/tmp/\${app_binary}" "/tmp/\${app_ui}" "/tmp/\${app_lng}"; do
    if [ -f "\$f" ]; then
        echo "Found package: \$f (size: \$(ls -lh \$f | awk '{print \$5}'))" | tee -a "\${LOG_FILE}"
    else
        echo "ERROR: Package not found: \$f" | tee -a "\${LOG_FILE}"
        exit 1
    fi
done

# 移除旧版本
echo "Removing old version..." | tee -a "\${LOG_FILE}"
${remove_cmd} 2>&1 | tee -a "\${LOG_FILE}"

# 安装新版本
echo "Installing main binary..." | tee -a "\${LOG_FILE}"
${install_cmd} /tmp/\${app_binary} 2>&1 | tee -a "\${LOG_FILE}" || {
    echo "ERROR: Failed to install \${app_binary}" | tee -a "\${LOG_FILE}"
    exit 1
}

echo "Installing LuCI app..." | tee -a "\${LOG_FILE}"
${install_cmd} /tmp/\${app_ui} 2>&1 | tee -a "\${LOG_FILE}" || {
    echo "ERROR: Failed to install \${app_ui}" | tee -a "\${LOG_FILE}"
    exit 1
}

echo "Installing language pack..." | tee -a "\${LOG_FILE}"
${install_cmd} /tmp/\${app_lng} 2>&1 | tee -a "\${LOG_FILE}" || {
    echo "ERROR: Failed to install \${app_lng}" | tee -a "\${LOG_FILE}"
    exit 1
}

# 检查 ddnsto 是否安装成功
echo "Verifying installation..." | tee -a "\${LOG_FILE}"
if command -v ${ddnsto_cmd} >/dev/null 2>&1; then
    echo "${ddnsto_cmd} command found at: \$(which ${ddnsto_cmd})" | tee -a "\${LOG_FILE}"
    echo "${ddnsto_cmd} version: \$(${ddnsto_cmd} -v 2>&1)" | tee -a "\${LOG_FILE}"
else
    echo "WARNING: ${ddnsto_cmd} command not found in PATH" | tee -a "\${LOG_FILE}"
    # 尝试查找可执行文件
    find /usr -name "${ddnsto_cmd}" -type f 2>/dev/null | head -5 | while read f; do
        echo "Found ${ddnsto_cmd} at: \$f" | tee -a "\${LOG_FILE}"
    done
fi

# 清理临时文件
rm -f /tmp/\${app_binary} /tmp/\${app_ui} /tmp/\${app_lng}

echo "Installation completed!" | tee -a "\${LOG_FILE}"
EOF

    chmod 755 /tmp/.ddnsto-upgrade.sh
}

TOKEN=""

# 解析命令行参数
while [ "$#" -gt 0 ]; do
    case "$1" in
        --token)
            if [ -n "$2" ]; then
                TOKEN=$2
                shift 2
            else
                error "--token requires a value"
                exit 1
            fi
            ;;
        --token=*)
            TOKEN=${1#--token=}
            shift
            ;;
        --force-version)
            if [ -n "$2" ]; then
                FORCE_VERSION=$2
                shift 2
            else
                error "--force-version requires a value (lite or standard)"
                exit 1
            fi
            ;;
        --force-version=*)
            FORCE_VERSION=${1#--force-version=}
            shift
            ;;
        *)
            shift
            ;;
    esac
done

# 检测包管理器
detect_package_manager

# 更新包文件名
update_package_names

# 检查 LuCI 兼容性
# LuCI 2.0+ (OpenWrt 23.05+) 使用 ucode，需要 luci-compat 和 luci-lua-runtime 来兼容 CBI 模块
if [ "$PKG_MANAGER" = "opkg" ]; then
    # OPKG 系统：检查是否存在新版 LuCI 但缺少 CBI 模块
    if [ -f /www/luci-static/resources/luci.js ] && [ ! -f /usr/lib/lua/luci/cbi.lua ]; then
        info "Installing luci-compat for LuCI 2.0+ compatibility..."
        opkg update && opkg install luci-compat || true
    fi
    # 检查并安装 luci-lua-runtime 依赖（LuCI 2.0+ 需要）
    if ! opkg list-installed | grep -q "^luci-lua-runtime"; then
        info "Installing luci-lua-runtime dependency..."
        opkg update && opkg install luci-lua-runtime || true
    fi
elif [ "$PKG_MANAGER" = "apk" ]; then
    # APK 系统 (OpenWrt 25+)：必须安装 luci-compat 和 luci-lua-runtime
    if [ -f /www/luci-static/resources/luci.js ] && [ ! -f /usr/lib/lua/luci/cbi.lua ]; then
        info "Installing luci-compat for LuCI 2.0+ compatibility (APK system)..."
        apk update && apk add luci-compat || warning "Failed to install luci-compat, LuCI interface may not work properly"
    fi
    # 检查并安装 luci-lua-runtime 依赖（LuCI 2.0+ 需要）
    if ! apk info -e luci-lua-runtime >/dev/null 2>&1; then
        info "Installing luci-lua-runtime dependency..."
        apk update && apk add luci-lua-runtime || warning "Failed to install luci-lua-runtime, LuCI interface may not work properly"
    fi
fi

# 检测架构并下载
if echo $(uname -m) | grep -Eqi 'x86_64'; then
    arch='x86_64'
    select_version
    BINARY_URL="$(build_download_url "${app_x86}")"
    (
        set -x
        Download_Files "${BINARY_URL}" /tmp/${app_binary} || exit 1
        Download_Files "${BASE_URL}/${app_ui}" /tmp/${app_ui} || exit 1
        Download_Files "${BASE_URL}/${app_lng}" /tmp/${app_lng} || exit 1
    ) || exit 1
elif echo $(uname -m) | grep -Eqi 'arm'; then
    arch='arm'
    select_version
    BINARY_URL="$(build_download_url "${app_arm}")"
    (
        set -x
        Download_Files "${BINARY_URL}" /tmp/${app_binary} || exit 1
        Download_Files "${BASE_URL}/${app_ui}" /tmp/${app_ui} || exit 1
        Download_Files "${BASE_URL}/${app_lng}" /tmp/${app_lng} || exit 1
    ) || exit 1
elif echo $(uname -m) | grep -Eqi 'aarch64'; then
    arch='aarch64'
    select_version
    BINARY_URL="$(build_download_url "${app_aarch64}")"
    (
        set -x
        Download_Files "${BINARY_URL}" /tmp/${app_binary} || exit 1
        Download_Files "${BASE_URL}/${app_ui}" /tmp/${app_ui} || exit 1
        Download_Files "${BASE_URL}/${app_lng}" /tmp/${app_lng} || exit 1
    ) || exit 1
elif echo $(uname -m) | grep -Eqi 'mipsel|mips'; then
    arch='mips'
    select_version
    BINARY_URL="$(build_download_url "${app_mips}")"
    (
        set -x
        Download_Files "${BINARY_URL}" /tmp/${app_binary} || exit 1
        Download_Files "${BASE_URL}/${app_ui}" /tmp/${app_ui} || exit 1
        Download_Files "${BASE_URL}/${app_lng}" /tmp/${app_lng} || exit 1
    ) || exit 1
else
    error "The program only supports OpenWrt (x86_64, arm, aarch64, mipsel/mips)."
    exit 1
fi

# 清理并准备升级
rm -f /tmp/.ddnsto-upgrade.pid
remove_deprecated
fork_upgrade

# 执行安装
if command_exists start-stop-daemon; then
    echo "Forking to install..."
    start-stop-daemon -S -b -q -m -x /tmp/.ddnsto-upgrade.sh -p /tmp/.ddnsto-upgrade.pid
    sleep 3
    if [ -f /tmp/.ddnsto-upgrade.pid ]; then
        PID=$(cat /tmp/.ddnsto-upgrade.pid)
        while test -d /proc/"${PID}"/; do
            echo "Waiting for installation to finish..."
            sleep 3
        done
    fi
    # 额外等待，确保安装完成
    sleep 2
else
    echo "Installing..."
    /tmp/.ddnsto-upgrade.sh
fi

# 显示安装日志（如果存在）
if [ -f /tmp/.ddnsto-upgrade.log ]; then
    echo ""
    echo "=== Installation Log ==="
    cat /tmp/.ddnsto-upgrade.log
    echo "========================"
    echo ""
fi

DDNSTO_CMD="ddnsto"
DDNSTO_CONFIG="ddnsto"
DDNSTO_SERVICE="ddnsto"

# 验证安装 - 增加重试机制
RETRY_COUNT=0
MAX_RETRIES=5
while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
    if command_exists ${DDNSTO_CMD}; then
        break
    fi
    echo "Waiting for ${DDNSTO_CMD} to be available... (attempt $((RETRY_COUNT + 1))/$MAX_RETRIES)"
    sleep 2
    RETRY_COUNT=$((RETRY_COUNT + 1))
done

if command_exists ${DDNSTO_CMD}; then
    VERSION=$(${DDNSTO_CMD} -v 2>/dev/null || true)
    if [ -z "${VERSION}" ]; then
        error "Installation failed: empty version output"
        exit 1
    fi

    printf "$GREEN"
    cat <<-'EOF'
  ____  ____  _   _ ____ _____ ___
  |  _ \|  _ \| \ | / ___|_   _/ _ \
  | | | | | | |  \| \___ \ | || | | |
  | |_| | |_| | |\  |___) || || |_| |
  |____/|____/|_| \_|____/ |_| \___/   ....is now installed!


EOF
    printf "$RESET"

    VERSION_NUM=$(get_version_number)
    echo "Version: ${VERSION} (${SELECTED_VERSION} ${VERSION_NUM})"

    if [ -n "${TOKEN}" ]; then
        echo "Token ${TOKEN} 已写入并启用服务，请登录 https://www.ddnsto.com/app 查看状态"
    else
        echo "感谢使用 DDNSTO，请登录 https://www.ddnsto.com 获取 token 填入插件"
    fi
    echo "如 luci 菜单未显示 DDNSTO，请刷新浏览器缓存或重新登录 luci 后台"

    # 配置 token
    if [ -n "${TOKEN}" ]; then
        if command_exists uci; then
            uci set ${DDNSTO_CONFIG}.@${DDNSTO_CONFIG}[0].token="${TOKEN}" &&
            uci set ${DDNSTO_CONFIG}.@${DDNSTO_CONFIG}[0].enabled='1' &&
            uci commit ${DDNSTO_CONFIG} &&
            /etc/init.d/${DDNSTO_SERVICE} restart
        else
            error "uci not found, token not set"
        fi
    fi
else
    error "Installation failed: ddnsto not found"
    exit 1
fi
