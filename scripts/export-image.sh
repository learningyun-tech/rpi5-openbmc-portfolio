#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
PROJECT_ROOT=$(cd -- "${SCRIPT_DIR}/.." && pwd)
BUILD_DIR=${BUILD_DIR:-"${PROJECT_ROOT}/work/build-rpi5"}
DEPLOY_DIR="${BUILD_DIR}/tmp/deploy/images/raspberrypi5"

force=false
if [[ ${1:-} == --force ]]; then
    force=true
    shift
fi

source_image=${1:-}
output_image=${2:-"${PROJECT_ROOT}/artifacts/rpi5-openbmc-lab.img"}

if [[ -z ${source_image} ]]; then
    source_image=$(
        find "${DEPLOY_DIR}" -maxdepth 1 -type f \
            -name 'rpi5-obmc-lab-image*.wic.bz2' \
            -printf '%T@ %p\n' 2>/dev/null |
            sort -nr | head -n 1 | cut -d' ' -f2- || true
    )
fi

if [[ -z ${source_image} || ! -f ${source_image} ]]; then
    echo "找不到 .wic.bz2；請先建置，或把來源檔當作第一個參數。" >&2
    exit 1
fi

if [[ -e ${output_image} && ${force} != true ]]; then
    echo "輸出檔已存在：${output_image}" >&2
    echo "確定要覆寫時加上 --force。" >&2
    exit 1
fi

mkdir -p "$(dirname -- "${output_image}")"
temporary="${output_image}.partial"
trap 'rm -f -- "${temporary}"' EXIT

echo "解壓縮 ${source_image} -> ${output_image}"
bzip2 -dc -- "${source_image}" >"${temporary}"
mv -f -- "${temporary}" "${output_image}"
trap - EXIT
sha256sum "${output_image}" >"${output_image}.sha256"

echo "已匯出：${output_image}"
echo "校驗檔：${output_image}.sha256"
