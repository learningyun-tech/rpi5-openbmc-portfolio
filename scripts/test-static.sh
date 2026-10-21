#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
PROJECT_ROOT=$(cd -- "${SCRIPT_DIR}/.." && pwd)
cd "${PROJECT_ROOT}"

for shell_script in scripts/*.sh; do
    bash -n "$shell_script"
done

python3 tests/validate_project.py
python3 tests/test_temperature_reading.py

if command -v shellcheck >/dev/null 2>&1; then
    shellcheck scripts/*.sh
else
    echo "提示：未安裝 shellcheck，已跳過 lint。" >&2
fi

git diff --check
echo "專案靜態檢查與溫度回歸測試全部通過。"
