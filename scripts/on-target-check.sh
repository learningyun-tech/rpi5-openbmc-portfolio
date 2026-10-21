#!/usr/bin/env bash
set -euo pipefail

echo "== OS =="
cat /etc/os-release

echo
echo "== Network =="
networkctl --no-pager status || true

echo
echo "== Simulator service =="
systemctl --no-pager --full status rpi5-openbmc-simulator.service

echo
echo "== Kernel thermal source =="
for zone in /sys/class/thermal/thermal_zone*; do
    [[ -e ${zone}/temp ]] || continue
    printf '%s: type=%s raw_temp=%s\n' "${zone}" \
        "$(cat "${zone}/type" 2>/dev/null || echo unknown)" \
        "$(cat "${zone}/temp")"
done

echo
echo "== OpenBMC D-Bus sensor =="
busctl get-property xyz.openbmc_project.RPi5.Simulator \
    /xyz/openbmc_project/sensors/temperature/CPU_Temperature \
    xyz.openbmc_project.Sensor.Value Value

echo
echo "== Failed systemd units =="
systemctl --failed --no-pager || true
