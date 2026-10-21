# 架構說明

## 建置層次

```text
OpenBMC wrynose（鎖定 commit）
├── OpenEmbedded-Core / BitBake
├── meta-openembedded
├── meta-phosphor
├── meta-raspberrypi（raspberrypi5 machine）
└── meta-rpi5-openbmc（本專案）
    ├── rpi5-obmc-lab-image
    └── rpi5-openbmc-simulator
```

本專案不修改 OpenBMC 上游檔案；它是優先級 12 的獨立 Yocto layer。升級時只要
更換 `upstream.lock`，再處理 layer API／recipe 相容性即可。

## 執行期資料流

自訂 daemon 每兩秒掃描 `/sys/class/thermal/thermal_zone*`。它優先選擇 type
包含 `cpu` 或 `soc` 的 thermal zone；找不到時才使用第一個有效溫度來源。

daemon 發布：

| D-Bus path | Interface | 用途 |
|---|---|---|
| `/xyz/openbmc_project/inventory/system/chassis/RPi5` | `Inventory.Item` | 名稱與在位狀態 |
| 同上 | `Inventory.Item.Chassis` | Chassis 類型 |
| 同上 | `Inventory.Decorator.Asset` | 製造商、型號、序號 |
| `/xyz/openbmc_project/sensors/temperature/CPU_Temperature` | `Sensor.Value` | °C 讀值、範圍與單位 |
| 同上 | `Sensor.Threshold.Warning` | 75 °C 警告 |
| 同上 | `Sensor.Threshold.Critical` | 85 °C 嚴重告警 |
| 同上 | `Availability` / `OperationalStatus` | thermal zone 讀取狀態 |
| 同上 | `Association.Definitions` | 把 Sensor 關聯至 `RPi5` Chassis |

association 包含兩組 tuple：

```text
(chassis,   all_sensors, /xyz/openbmc_project/inventory/system/chassis/RPi5)
(inventory, sensors,     /xyz/openbmc_project/inventory/system/chassis/RPi5)
```

Object Mapper 依此建立反向 endpoint；`bmcweb` 查詢 Chassis 的 `all_sensors`
association，最後生成 Redfish Chassis Sensor collection。

## 為何使用自訂 daemon

`dbus-sensors` 很適合由 hwmon、I2C 或 Entity Manager 動態配置的產品 Sensor。
Pi 5 SoC thermal zone 是教學映像一定存在、資料模型單純的來源；小型 daemon 可
同時示範：

- sdbusplus Asio object server
- OpenBMC inventory model
- Sensor.Value 與 threshold interfaces
- Object Mapper association
- bmcweb 的 D-Bus → Redfish 映射
- Yocto recipe 與 systemd service 整合

日後接入多顆實體 Sensor 時，應優先改用 `dbus-sensors` 與 Entity Manager，而
不是把所有驅動邏輯堆進這個示範程式。

## 映像內容的取捨

`rpi5-obmc-lab-image` 直接繼承 `obmc-phosphor-image` class，但只選擇適合單板
電腦的 image features。沒有加入：

- Host power GPIO 與 host IPMI
- KVM、Virtual Media、SOL
- Fan-control policy
- BMC/BIOS flash manager
- PMCI、SPDM、TPM

這樣既保留 OpenBMC 的管理平面，又避免許多沒有硬體後端、開機必然失敗的
daemon。

## 安全模型

- bmcweb 只以 HTTPS 提供介面，但初始憑證是自簽。
- 上游開發映像有已知預設 root 密碼，必須第一次開機立即更換。
- smoke test 使用 Redfish session token，結束時刪除 session。
- `flash.sh` 不會自動卸載磁碟；目標有任何掛載點即拒絕。
- daemon 的 systemd unit 啟用 `NoNewPrivileges`、`ProtectHome` 與唯讀系統目錄。

若要部署到非隔離網路，還需要正式憑證、密碼政策、防火牆、更新／rollback、
Secure Boot、持久化策略與平台級威脅模型；這些不在實驗映像範圍內。
