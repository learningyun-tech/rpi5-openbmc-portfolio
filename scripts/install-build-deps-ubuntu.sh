#!/usr/bin/env bash
set -euo pipefail

if [[ ${EUID} -eq 0 ]]; then
    echo "請用一般使用者執行；腳本會在需要時呼叫 sudo。" >&2
    exit 1
fi

if [[ ! -r /etc/os-release ]]; then
    echo "找不到 /etc/os-release；此腳本只支援 Ubuntu/Debian。" >&2
    exit 1
fi

# shellcheck source=/dev/null
source /etc/os-release
case "${ID:-}" in
    ubuntu|debian) ;;
    *)
        echo "偵測到 ${ID:-unknown}；請依 Yocto Wrynose 文件手動安裝套件。" >&2
        exit 1
        ;;
esac

sudo apt-get update
sudo apt-get install -y \
    bmap-tools \
    bzip2 \
    build-essential \
    chrpath \
    cpio \
    debianutils \
    diffstat \
    file \
    gawk \
    gcc \
    git \
    iputils-ping \
    jq \
    libacl1 \
    libcrypt-dev \
    liblz4-tool \
    locales \
    python3 \
    python3-git \
    python3-jinja2 \
    python3-pexpect \
    python3-pip \
    python3-subunit \
    python3-websockets \
    rpcsvc-proto \
    shellcheck \
    socat \
    texinfo \
    tmux \
    unzip \
    wget \
    xz-utils \
    zstd

if ! locale -a | grep -Eqi '^en_US\.utf-?8$'; then
    sudo sed -i 's/^# *\(en_US.UTF-8 UTF-8\)/\1/' /etc/locale.gen
    sudo locale-gen en_US.UTF-8
fi

echo "建置相依套件已安裝。"
