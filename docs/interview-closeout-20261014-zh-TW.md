# Raspberry Pi 5 OpenBMC：實機驗收與面試展示

文件整理日期：2026-10-19。本文件依據 Ubuntu 建置主機與 Pi 實機已回報的輸出整理，並不代表在文件更新當日重新執行全部測試。較早教學中的「待測」是當時狀態；請以下列實測範圍與限制為準。

Windows 工作區與 Ubuntu 建置目錄是不同副本。展示程式與映像版本時，應以 Ubuntu 實際建置內容為準，不要用 Windows 副本直接覆蓋已驗證的 Ubuntu 專案。

## 專案定位

使用 Yocto 自訂 layer 為 Raspberry Pi 5 建置 ARM64 OpenBMC 映像。自訂 C++ 服務讀取 Linux thermal sysfs 的 Pi 5 SoC／CPU 溫度，轉成 D-Bus Sensor；bmcweb 再透過 Redfish 提供管理查詢。Pi 5 在此是低成本的 BMC 學習平台，不具備真實伺服器的 host power control、KCS/eSPI、KVM 或產品級韌體更新線路。

```text
Pi 5 SoC 溫度 → Linux thermal sysfs → 自訂 C++ 服務 → D-Bus Sensor → bmcweb／Redfish
```

## 已有實機證據

本報告整理的是另建作品集儲存庫前的實驗輸出；溫度查詢腳本已修正 Sensor URI 並加入 TLS 限制警告，但新儲存庫的初始提交並不是以下既有映像的建置版本。**不能把新的 commit ID 當成原映像來源，也不宣稱已用新工作樹完成乾淨環境重建。**

上游基準由 `upstream.lock` 鎖定為 OpenBMC `wrynose` commit
`b48d8890dac29b8954f47a8ce17645d5f9897782`。

本次燒錄、讀回驗證及實機啟動使用的壓縮映像為
`rpi5-obmc-lab-image-raspberrypi5-20261008121245.wic.bz2`。
使用者於 Ubuntu 執行 `sha256sum` 回報該檔案的 SHA-256：

```text
cb630c95e153846e2700ccb1411a69634286cb00ad6ab3c6d6fa47116c91c67d
```

這是 `.wic.bz2` 壓縮檔的雜湊，不能直接拿來與未壓縮的 `.wic` 或整張 microSD 比對。卡片寫入另有 bmap 讀回驗證；其通過代表 bmap 列出的 mapped ranges 符合校驗值，不代表整張卡的未使用區域都逐位元比對過。

| 驗收項目 | 已觀察結果 |
| --- | --- |
| 原始碼品質 | Ubuntu 主機上的溫度解析回歸測試 12 項通過，涵蓋正常換算、缺檔、NaN／Inf、尾端垃圾字元與範圍檢查；冒煙測試路徑修改後，`scripts/test-static.sh` 仍以結束碼 0 通過。這不等同於已對 Pi 完整重跑網路測試。 |
| 映像與燒錄 | Yocto 建置結束碼為 0；新映像 manifest 含 `rpi5-brcmfmac`、`kmod` 與 brcmfmac kernel modules；`.wic.bz2` 壓縮檢查通過。microSD 燒錄結束碼為 0，bmap 讀回驗證通過。 |
| 重新開機 | Pi 開至 `ttyAMA10` 登入提示；重開機後 `rpi5-brcmfmac.service`、`wpa_supplicant-nl80211@wlan0.service`、`rpi5-openbmc-simulator.service` 與 `bmcweb.socket` 均回報 `active`。 |
| 網路管理 | 重開機後自動連至實驗室 5 GHz Wi-Fi，`wpa_state=COMPLETED`，`wlan0` 取得 DHCP IPv4 位址。Ubuntu 對 Pi 的 SSH 顯示不同來源與目的 IP，證明是跨主機連線。 |
| HTTPS／Redfish | Ubuntu 使用 `--cacert`、匹配憑證主機名稱的 URL 與 `--resolve` 查詢 CPU Sensor，未使用 `-k`，取得 HTTP 200、攝氏讀值、`Status.Health=OK`。未登入查詢 `/redfish/v1/Managers` 得到 HTTP 401，登入後得到 HTTP 200；Service Root 可匿名取得 HTTP 200。 |
| 溫度資料 | Pi 的 `thermal_zone0/type` 為 `cpu-thermal`。連續取樣的 sysfs 值由 `54000` 變到 `52350` 毫攝氏度，D-Bus `Value` 由 `54` 變到 `53.45` 攝氏度；兩層讀值都會變動。先前 Redfish 回應過 `52.35 Cel`。 |

溫度取樣並非原子操作。三次依序讀取 sysfs／D-Bus 的結果為 `54.00／54.00`、`52.35／54.00`、`52.35／53.45` °C。C++ 服務約每 2 秒更新一次，先後查詢可能看到不同更新週期；這些結果支持資料會更新，但**不能宣稱每次查詢都精確同步，也未完成感測精度校正**。Redfish 的 `75`／`85` °C 門檻是專案設定的展示門檻，並非 Pi 的官方硬體規格。

## 實際驗證的資料介面

- Linux 來源：`/sys/class/thermal/thermal_zone0/temp`，對應 `cpu-thermal`，單位為毫攝氏度；例如 `52350 / 1000 = 52.35` °C。
- D-Bus service：`xyz.openbmc_project.RPi5.Simulator`。
- D-Bus object：`/xyz/openbmc_project/sensors/temperature/CPU_Temperature`。
- D-Bus interface：`xyz.openbmc_project.Sensor.Value`；`Value` 為攝氏溫度，`Unit` 為 `xyz.openbmc_project.Sensor.Value.Unit.DegreesC`。
- Redfish Sensor：`/redfish/v1/Chassis/RPi5/Sensors/temperature_CPU_Temperature`，回應包含 `Reading`、`ReadingUnits: Cel` 與 `Status`。

Redfish 的 Sensor ID 與 D-Bus object 名稱不完全相同；應先查詢 Sensor Collection 的 `Members`，再使用其中的 URI，不要自行推測路徑。

## 展示順序

1. **目標與邊界（30 秒）：** 說明為何用 Pi 5 學習 OpenBMC，並明確區分實驗平台與產品 BMC。
2. **建置與整合（45 秒）：** 指出 Yocto layer、Wi-Fi driver 的 systemd oneshot、C++ Sensor 服務及 12 項解析測試；展示映像 manifest 與建置成功記錄。
3. **資料路徑（75 秒）：** 在 Pi 讀 `thermal_zone0/temp` 與 D-Bus `Sensor.Value`，再由 Ubuntu 以 HTTPS 查 Redfish Sensor。說明毫攝氏度除以 1000，以及不同取樣時間造成的差異。
4. **恢復與除錯（30 秒）：** 展示重開機後服務自動啟動、Wi-Fi 完成認證、DHCP、Ubuntu SSH 與 Redfish 可用；簡述曾以 manifest、systemd、journal 和網路狀態逐層定位問題。

可用的面試介紹：

> 我以現有 OpenBMC、Raspberry Pi BSP 與自訂 Yocto layer，在 Raspberry Pi 5 上進行建置、部署與整合驗證。資料路徑是 Linux thermal sysfs、C++ 服務、D-Bus Sensor 到 Redfish。我實際執行解析測試、映像檢查、microSD 讀回驗證，以及重開機後的 Wi-Fi、SSH 與 Redfish 查詢。這是嵌入式使用者空間的系統整合學習專案，不是自行開發 kernel driver，也不是完整的伺服器 BMC 產品。

- `trace-enable.service` 曾顯示 `Cannot initialize environment`；裝置缺少 `/etc/fw_env.config`。目前只能說這是待處理的開機服務問題，尚未證實完整根因，也未修改 bootloader environment。
- Broadcom 驅動在 UART 重複輸出 `brcmf_p2p_send_action_frame: Unknown Frame`。已觀察到 Pi 仍可完成 5 GHz Wi-Fi 認證、取得 IP 並提供 SSH／Redfish；應把訊息列為待追蹤的驅動日誌，不宣稱它已修復。
- 原 2.4 GHz 網路曾在重開機後連線失敗；目前完成重開機驗證的路徑是 5 GHz。2.4 GHz 問題尚未定位，不能宣稱備援切換可用。
- 5 GHz 的密碼與設定是燒錄後在 Pi 上佈署的；重新燒錄新卡或新映像時，需要重新佈署，不應把它說成已內建於 Yocto recipe。切勿把 Wi-Fi 密碼、PSK、root 密碼或私鑰放進作品集。
- 自簽 HTTPS 憑證在實驗網路中以指定 CA 檔驗證；產品化仍需正式憑證、帳號與更新策略。
- `scripts/smoke-test.sh` 已修正 Sensor URI，並通過 Bash 語法、空白格式與既有靜態／解析測試，但**此修改版尚未完整對 Pi 執行**。它仍使用 `curl -k`，只能視為受限實驗環境中的 API 冒煙測試，不能作為 TLS 憑證驗證通過的證據；上表的 TLS 結果來自另一組不使用 `-k` 的手動查詢。
- UART 已實測；I²C／SPI 的建置設定或介面啟用，不等於已完成實體周邊讀寫測試。尚未取得本專案 I²C／SPI 實體通訊的驗證輸出。
