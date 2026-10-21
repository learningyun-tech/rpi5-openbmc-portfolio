#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
PROJECT_ROOT=$(cd -- "${SCRIPT_DIR}/.." && pwd)
STATE_DIR="${PROJECT_ROOT}/work/tmux"
LOG_DIR="${STATE_DIR}/logs"
STATUS_FILE="${STATE_DIR}/status.txt"
ACTION=${1:-status}
PROJECT_ID=$(printf '%s' "${PROJECT_ROOT}" | cksum | awk '{print $1}')
SESSION_NAME=${TMUX_SESSION_NAME:-"rpi5-obmc-${UID}-${PROJECT_ID}"}

if [[ ! ${SESSION_NAME} =~ ^[A-Za-z0-9_-]+$ ]]; then
    echo "TMUX_SESSION_NAME 只能包含英文字母、數字、底線與連字號。" >&2
    exit 2
fi

usage() {
    cat <<'EOF'
用法：
  ./scripts/tmux-build.sh configure  在背景 tmux 初始化並解析 metadata
  ./scripts/tmux-build.sh build      在背景 tmux 建置映像
  ./scripts/tmux-build.sh attach     進入正在執行的 tmux 畫面
  ./scripts/tmux-build.sh status     顯示目前或最近一次工作的狀態
  ./scripts/tmux-build.sh log        顯示最近 100 行建置日誌
  ./scripts/tmux-build.sh follow     持續追蹤日誌；按 Ctrl+C 離開但不停止建置

離開 tmux 且保持工作執行：先按 Ctrl+B，放開後再按 D。
可用 TMUX_SESSION_NAME 自訂 session 名稱。
EOF
}

require_tmux() {
    if ! command -v tmux >/dev/null 2>&1; then
        echo "找不到 tmux；Ubuntu 請執行 sudo apt install tmux。" >&2
        exit 1
    fi
}

has_session() {
    tmux has-session -t "${SESSION_NAME}" 2>/dev/null
}

latest_log() {
    find "${LOG_DIR}" -maxdepth 1 -type f -name '*.log' \
        -printf '%T@ %p\n' 2>/dev/null | sort -nr | head -n 1 | cut -d' ' -f2-
}

write_status() {
    local state=$1
    local mode=$2
    local started_at=$3
    local finished_at=$4
    local exit_code=$5
    local log_file=$6

    mkdir -p "${STATE_DIR}"
    {
        printf '狀態：%s\n' "${state}"
        printf '工作：%s\n' "${mode}"
        printf '開始：%s\n' "${started_at}"
        if [[ -n ${finished_at} ]]; then
            printf '結束：%s\n' "${finished_at}"
        fi
        if [[ -n ${exit_code} ]]; then
            printf '結束碼：%s\n' "${exit_code}"
        fi
        printf '日誌：%s\n' "${log_file}"
    } >"${STATUS_FILE}"
}

run_job() {
    local mode=$1
    local log_file=$2
    local started_at
    local finished_at
    local exit_code
    local result

    started_at=$(date --iso-8601=seconds)
    mkdir -p "${LOG_DIR}"
    write_status "執行中" "${mode}" "${started_at}" "" "" "${log_file}"

    printf '=== tmux OpenBMC %s：%s ===\n' "${mode}" "${started_at}" |
        tee -a "${log_file}"

    set +e
    set -o pipefail
    "${SCRIPT_DIR}/build.sh" "${mode}" 2>&1 | tee -a "${log_file}"
    exit_code=${PIPESTATUS[0]}
    set -e

    finished_at=$(date --iso-8601=seconds)
    if ((exit_code == 0)); then
        result="成功"
    else
        result="失敗"
    fi
    printf '\n=== %s；結束碼 %d；%s ===\n' \
        "${result}" "${exit_code}" "${finished_at}" | tee -a "${log_file}"
    write_status "${result}" "${mode}" "${started_at}" "${finished_at}" \
        "${exit_code}" "${log_file}"
    return "${exit_code}"
}

start_job() {
    local mode=$1
    local timestamp
    local log_file

    require_tmux
    if has_session; then
        echo "tmux session '${SESSION_NAME}' 已在執行，未啟動重複工作。" >&2
        echo "使用 ./scripts/tmux-build.sh attach 查看。" >&2
        exit 1
    fi

    mkdir -p "${LOG_DIR}"
    timestamp=$(date '+%Y%m%d-%H%M%S')
    log_file="${LOG_DIR}/${mode}-${timestamp}.log"

    tmux new-session -d -s "${SESSION_NAME}" -n "${mode}" \
        -c "${PROJECT_ROOT}" \
        -- /usr/bin/env bash "${SCRIPT_DIR}/tmux-build.sh" __run \
        "${mode}" "${log_file}"

    echo "已在背景啟動 OpenBMC ${mode}。"
    echo "查看畫面：./scripts/tmux-build.sh attach"
    echo "查看狀態：./scripts/tmux-build.sh status"
    echo "持續看日誌：./scripts/tmux-build.sh follow"
    echo "安全離開 tmux：先按 Ctrl+B，放開後再按 D。"
}

show_status() {
    require_tmux
    if has_session; then
        echo "tmux session '${SESSION_NAME}' 正在執行。"
        tmux list-panes -t "${SESSION_NAME}" \
            -F '目前程式：#{pane_current_command}'
    else
        echo "目前沒有執行中的 tmux 建置 session。"
        if [[ -f ${STATUS_FILE} ]] && grep -Fqx '狀態：執行中' "${STATUS_FILE}"; then
            echo "警告：上次狀態仍是執行中，可能曾關機或被外部中止。" >&2
        fi
    fi

    if [[ -f ${STATUS_FILE} ]]; then
        echo
        cat "${STATUS_FILE}"
    else
        echo "尚無建置狀態紀錄。"
    fi
}

show_log() {
    local log_file

    log_file=$(latest_log || true)
    if [[ -z ${log_file} || ! -f ${log_file} ]]; then
        echo "尚無 tmux 建置日誌。" >&2
        exit 1
    fi
    echo "日誌：${log_file}"
    tail -n 100 "${log_file}"
}

follow_log() {
    local log_file

    log_file=$(latest_log || true)
    if [[ -z ${log_file} || ! -f ${log_file} ]]; then
        echo "尚無 tmux 建置日誌。" >&2
        exit 1
    fi
    echo "追蹤：${log_file}"
    echo "按 Ctrl+C 只會停止查看，不會停止背景建置。"
    tail -n 100 -f "${log_file}"
}

case "${ACTION}" in
    configure|build)
        start_job "${ACTION}"
        ;;
    attach)
        require_tmux
        if ! has_session; then
            echo "目前沒有執行中的 tmux 建置；請使用 status 或 log 查看結果。" >&2
            exit 1
        fi
        if [[ -n ${TMUX:-} ]]; then
            exec tmux switch-client -t "${SESSION_NAME}"
        else
            exec tmux attach-session -t "${SESSION_NAME}"
        fi
        ;;
    status)
        show_status
        ;;
    log)
        show_log
        ;;
    follow)
        follow_log
        ;;
    __run)
        if [[ $# -ne 3 ]] ||
           [[ ${2:-} != configure && ${2:-} != build ]]; then
            echo "內部執行參數錯誤。" >&2
            exit 2
        fi
        run_job "$2" "$3"
        ;;
    -h|--help|help)
        usage
        ;;
    *)
        usage >&2
        exit 2
        ;;
esac
