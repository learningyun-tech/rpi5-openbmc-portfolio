#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
PROJECT_ROOT=$(cd -- "${SCRIPT_DIR}/.." && pwd)
LOCK_FILE="${PROJECT_ROOT}/upstream.lock"

# shellcheck source=/dev/null
source "${LOCK_FILE}"

OPENBMC_DIR=${OPENBMC_DIR:-"${PROJECT_ROOT}/work/openbmc"}
BUILD_DIR=${BUILD_DIR:-"${PROJECT_ROOT}/work/build-rpi5"}
IMAGE_TARGET=${IMAGE_TARGET:-rpi5-obmc-lab-image}
MODE=${1:-build}

usage() {
    cat <<'EOF'
用法：
  ./scripts/build.sh configure   下載、設定並只解析 metadata
  ./scripts/build.sh build       建置可燒錄映像（預設）
  ./scripts/build.sh shell       進入已載入 BitBake 環境的 shell

可用環境變數：OPENBMC_DIR、BUILD_DIR、IMAGE_TARGET。
EOF
}

case "${MODE}" in
    configure|build|shell) ;;
    -h|--help)
        usage
        exit 0
        ;;
    *)
        usage >&2
        exit 2
        ;;
esac

if [[ ${EUID} -eq 0 ]]; then
    echo "Yocto 不允許以 root 建置；請改用一般使用者。" >&2
    exit 1
fi

if grep -qi microsoft /proc/version 2>/dev/null &&
   [[ ${PROJECT_ROOT} == /mnt/* ]]; then
    cat >&2 <<'EOF'
錯誤：請勿把 Yocto build directory 放在 WSL 的 /mnt/c 或其他 Windows 掛載點。
請先把本專案複製到 WSL 的 Linux 檔案系統（例如 ~/src/rpi5-openbmc-lab）。
EOF
    exit 1
fi

if [[ ${PROJECT_ROOT} == /mnt/hgfs/* ]]; then
    cat >&2 <<'EOF'
錯誤：請勿在 VMware Shared Folders（/mnt/hgfs）內建置 Yocto。
共享資料夾只適合傳送檔案；請把專案複製到 Ubuntu 虛擬磁碟內，
例如 ~/src/rpi5-openbmc-lab，再從該目錄執行本腳本。
EOF
    exit 1
fi

required_commands=(awk bzip2 df flock git make patch python3 tar wget)
missing=()
for command_name in "${required_commands[@]}"; do
    if ! command -v "${command_name}" >/dev/null 2>&1; then
        missing+=("${command_name}")
    fi
done
if ((${#missing[@]} > 0)); then
    echo "缺少建置工具：${missing[*]}" >&2
    echo "Ubuntu/Debian 請先執行 ./scripts/install-build-deps-ubuntu.sh" >&2
    exit 1
fi

if [[ ${MODE} != shell ]]; then
    mkdir -p "${PROJECT_ROOT}/work"
    exec {build_lock_fd}>"${PROJECT_ROOT}/work/build.lock"
    if ! flock -n "${build_lock_fd}"; then
        cat >&2 <<'EOF'
已有另一個 configure 或 build 正在使用本專案。
請用 ./scripts/tmux-build.sh status 查看，勿同時啟動兩個 BitBake。
EOF
        exit 1
    fi
fi

if ! locale -a 2>/dev/null | grep -Eqi '^en_US\.utf-?8$'; then
    echo "缺少 en_US.UTF-8 locale；請先執行安裝相依套件腳本。" >&2
    exit 1
fi

mkdir -p "$(dirname -- "${OPENBMC_DIR}")" "${BUILD_DIR}"

available_kib=$(df -Pk "${BUILD_DIR}" | awk 'NR == 2 {print $4}')
if [[ ${available_kib} =~ ^[0-9]+$ ]] && ((available_kib < 146800640)); then
    available_gib=$((available_kib / 1024 / 1024))
    echo "警告：只剩 ${available_gib} GiB；Yocto Wrynose 文件建議至少 140 GiB。" >&2
fi

if [[ ! -d ${OPENBMC_DIR}/.git ]]; then
    if [[ -e ${OPENBMC_DIR} ]] && [[ -n $(find "${OPENBMC_DIR}" -mindepth 1 -maxdepth 1 -print -quit) ]]; then
        echo "${OPENBMC_DIR} 已存在且不是空目錄，也不是 Git repository。" >&2
        exit 1
    fi
    echo "下載 OpenBMC ${OPENBMC_BRANCH}..."
    git clone --filter=blob:none --branch "${OPENBMC_BRANCH}" \
        "${OPENBMC_REPOSITORY}" "${OPENBMC_DIR}"
fi

origin_url=$(git -C "${OPENBMC_DIR}" remote get-url origin)
if [[ ${origin_url%.git} != "${OPENBMC_REPOSITORY%.git}" ]]; then
    echo "現有 repository 的 origin 不符：${origin_url}" >&2
    exit 1
fi

current_commit=$(git -C "${OPENBMC_DIR}" rev-parse HEAD)
if [[ ${current_commit} != "${OPENBMC_COMMIT}" ]]; then
    if [[ -n $(git -C "${OPENBMC_DIR}" status --porcelain --untracked-files=no) ]]; then
        echo "OpenBMC source 有已追蹤的本地修改，為避免覆寫而停止。" >&2
        exit 1
    fi
    git -C "${OPENBMC_DIR}" fetch --depth 1 origin "${OPENBMC_COMMIT}"
    git -C "${OPENBMC_DIR}" checkout --detach "${OPENBMC_COMMIT}"
fi

cd "${OPENBMC_DIR}"
set +u
# shellcheck source=/dev/null
TEMPLATECONF="meta-phosphor/conf/templates/default" \
    source ./oe-init-build-env "${BUILD_DIR}" >/dev/null
set -u

# The generated build directory belongs to this wrapper. local-extra.conf is
# intentionally separate and preserved for user experiments.
install -m 0644 "${PROJECT_ROOT}/config/local.conf" \
    "${BUILD_DIR}/conf/local.conf"
if [[ ! -e ${BUILD_DIR}/conf/local-extra.conf ]]; then
    install -m 0644 "${PROJECT_ROOT}/config/local-extra.conf.example" \
        "${BUILD_DIR}/conf/local-extra.conf"
fi

add_layer_if_missing() {
    local layer_path=$1
    if ! grep -Fq "${layer_path}" "${BUILD_DIR}/conf/bblayers.conf"; then
        bitbake-layers add-layer "${layer_path}"
    fi
}

add_layer_if_missing "${OPENBMC_DIR}/meta-raspberrypi"
add_layer_if_missing "${PROJECT_ROOT}/meta-rpi5-openbmc"

case "${MODE}" in
    configure)
        bitbake-layers show-layers
        bitbake -p
        echo "設定與 metadata 解析成功：${BUILD_DIR}"
        ;;
    build)
        bitbake "${IMAGE_TARGET}"
        deploy_dir="${BUILD_DIR}/tmp/deploy/images/raspberrypi5"
        echo "建置完成。可燒錄檔案："
        find "${deploy_dir}" -maxdepth 1 -type f \
            \( -name "${IMAGE_TARGET}*.wic.bz2" -o \
               -name "${IMAGE_TARGET}*.wic.bmap" \) -print
        ;;
    shell)
        echo "已載入 BitBake 環境；IMAGE_TARGET=${IMAGE_TARGET}"
        exec "${SHELL:-/bin/bash}" -i
        ;;
esac
