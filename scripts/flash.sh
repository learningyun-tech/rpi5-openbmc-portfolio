#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
PROJECT_ROOT=$(cd -- "${SCRIPT_DIR}/.." && pwd)
BUILD_DIR=${BUILD_DIR:-"${PROJECT_ROOT}/work/build-rpi5"}
DEPLOY_DIR="${BUILD_DIR}/tmp/deploy/images/raspberrypi5"

device=${1:-}
image=${2:-}

if [[ -z ${device} ]]; then
    echo "用法：sudo ./scripts/flash.sh /dev/sdX [image.wic.bz2]" >&2
    exit 2
fi

if [[ $(uname -s) != Linux ]]; then
    echo "此腳本只支援 Linux；Windows 請使用 export-image.sh 與 Raspberry Pi Imager。" >&2
    exit 1
fi

for command_name in bmaptool findmnt lsblk; do
    if ! command -v "${command_name}" >/dev/null 2>&1; then
        echo "缺少 ${command_name}。Ubuntu/Debian 可安裝 bmap-tools 與 util-linux。" >&2
        exit 1
    fi
done

device=$(readlink -f -- "${device}")
if [[ ! -b ${device} ]]; then
    echo "不是 block device：${device}" >&2
    exit 1
fi
if [[ $(lsblk -ndo TYPE "${device}") != disk ]]; then
    echo "請指定整顆磁碟（例如 /dev/sdb），不要指定 partition。" >&2
    exit 1
fi

if lsblk -nrpo MOUNTPOINT "${device}" | grep -qE '/.+'; then
    echo "目標磁碟或其 partition 仍有掛載點，請先手動卸載：" >&2
    lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINTS,MODEL "${device}" >&2
    exit 1
fi

if [[ -z ${image} ]]; then
    image=$(
        find "${DEPLOY_DIR}" -maxdepth 1 -type f \
            -name 'rpi5-obmc-lab-image*.wic.bz2' \
            -printf '%T@ %p\n' 2>/dev/null |
            sort -nr | head -n 1 | cut -d' ' -f2- || true
    )
fi
if [[ -z ${image} || ! -f ${image} ]]; then
    echo "找不到 .wic.bz2；請先建置，或傳入映像路徑。" >&2
    exit 1
fi

echo "即將完全覆寫下列磁碟："
lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINTS,MODEL,SERIAL "${device}"
echo "映像：${image}"
read -r -p "請輸入完整裝置名稱 ${device} 以確認：" confirmation
if [[ ${confirmation} != "${device}" ]]; then
    echo "確認不符，已取消。"
    exit 1
fi

if [[ ${EUID} -eq 0 ]]; then
    bmaptool copy "${image}" "${device}"
else
    sudo bmaptool copy "${image}" "${device}"
fi
sync
echo "燒錄完成；現在可以安全移除 microSD。"
