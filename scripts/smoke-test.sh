#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' 'WARNING: curl -k skips TLS certificate verification; isolated trusted lab use only.' >&2
host=${1:-}
user_name=${BMC_USER:-root}

if [[ -z ${host} ]]; then
    echo "用法：./scripts/smoke-test.sh <BMC-IP>" >&2
    exit 2
fi
host=${host#https://}
host=${host%/}
base_url="https://${host}"

for command_name in curl jq; do
    if ! command -v "${command_name}" >/dev/null 2>&1; then
        echo "缺少 ${command_name}。" >&2
        exit 1
    fi
done

if [[ -z ${BMC_PASSWORD:-} ]]; then
    read -r -s -p "${user_name}@${host} 的密碼：" BMC_PASSWORD
    echo
fi

headers=$(mktemp)
body=$(mktemp)
cleanup() {
    if [[ -n ${token:-} && -n ${session_location:-} ]]; then
        curl -ksS --connect-timeout 10 -X DELETE \
            -H "X-Auth-Token: ${token}" \
            "${base_url}${session_location}" >/dev/null || true
    fi
    rm -f -- "${headers}" "${body}"
}
trap cleanup EXIT

payload=$(jq -cn --arg user "${user_name}" --arg password "${BMC_PASSWORD}" \
    '{UserName: $user, Password: $password}')
http_code=$(printf '%s' "${payload}" | curl -ksS --connect-timeout 15 \
    -D "${headers}" -o "${body}" -w '%{http_code}' \
    -H 'Content-Type: application/json' --data-binary @- \
    "${base_url}/redfish/v1/SessionService/Sessions")
unset BMC_PASSWORD payload

if [[ ${http_code} != 201 ]]; then
    echo "建立 Redfish session 失敗（HTTP ${http_code}）：" >&2
    jq . "${body}" 2>/dev/null || cat "${body}" >&2
    exit 1
fi

token=$(awk 'BEGIN{IGNORECASE=1} /^X-Auth-Token:/ {sub(/\r$/, "", $2); print $2}' "${headers}")
session_location=$(awk 'BEGIN{IGNORECASE=1} /^Location:/ {sub(/\r$/, "", $2); print $2}' "${headers}")
if [[ -z ${token} || -z ${session_location} ]]; then
    echo "Redfish session 回應缺少 token 或 Location。" >&2
    exit 1
fi

redfish_get() {
    local path=$1
    local label=$2
    echo
    echo "== ${label} (${path}) =="
    curl -ksS --fail-with-body --connect-timeout 15 \
        -H "X-Auth-Token: ${token}" "${base_url}${path}" | jq .
}

redfish_get "/redfish/v1/" "Service Root"
redfish_get "/redfish/v1/Managers/bmc" "BMC Manager"
redfish_get "/redfish/v1/Chassis/RPi5" "Pi 5 Chassis"
redfish_get "/redfish/v1/Chassis/RPi5/Sensors" "Sensor Collection"
redfish_get "/redfish/v1/Chassis/RPi5/Sensors/temperature_CPU_Temperature" \
    "Real SoC Temperature"

echo
echo "Redfish smoke test 全部通過。"
