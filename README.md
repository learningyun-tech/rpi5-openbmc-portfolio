# Raspberry Pi 5 OpenBMC：建置與系統整合作品集

這是一套以版本鎖定設定建置的教學型 OpenBMC 映像：使用 Raspberry Pi 5 當作 BMC
開發板，提供 HTTPS Web UI、Redfish、SSH、D-Bus、使用者／網路／事件管理，
並把 Pi 5 的真實 SoC 溫度發布成 OpenBMC Sensor。

> 這是實驗與學習平台，不是經硬體廠商驗證的產品 BMC。Pi 5 沒有伺服器主機的
> LPC/KCS、eSPI、KVM 擷取、電源控制與韌體快閃線路；本專案刻意不把這些功能
> 偽裝成可用。

## 面試閱讀導覽

- [OpenBMC 建置流程解析](docs/openbmc-build-guide-zh-TW.md)：從版本鎖定、layer／recipe、交叉編譯到映像與實機驗證。
- [系統架構](docs/architecture.md)：C++、D-Bus Sensor、inventory association 與 Redfish 的分工。
- [實機驗收與已知限制](docs/interview-closeout-20261014-zh-TW.md)：已觀察結果、版本界線與未驗證功能。

本案重點是 Raspberry Pi 5 上的 OpenBMC 建置、部署及使用者空間整合；不是自行開發核心驅動，也不是完整伺服器 BMC 產品。


## 專案成果

建置完成後會得到：

- `rpi5-obmc-lab-image-raspberrypi5.rootfs.wic.bz2`：Linux 可用 `bmaptool`
  直接燒錄。
- `rpi5-obmc-lab-image-raspberrypi5.rootfs.wic.bmap`：加速並驗證燒錄。
- 透過 `scripts/export-image.sh` 產生的 `.img`：Windows 可用 Raspberry Pi
  Imager 的「自訂映像」燒錄。

主要能力：

| 能力 | 狀態 | 說明 |
|---|---:|---|
| Web UI / HTTPS | 部分實測 | HTTPS 已驗證；Web UI 登入與操作未列入本次驗收 |
| Redfish API | 已實測 | Manager、Chassis、CPU Sensor 查詢；詳見實機驗收報告 |
| SSH / D-Bus / systemd | 已實測 | Ubuntu 對 Pi 的 SSH、D-Bus 屬性及核心服務查詢 |
| CPU 溫度 Sensor | 已實測 | 真實 sysfs 溫度經 C++、D-Bus 到 Redfish；非同步取樣 |
| DHCP 網路管理 | 已實測（Wi-Fi） | 5 GHz Wi-Fi 重開機後取得位址；有線 Ethernet 未列入本次驗收 |
| UART | 已實測 | `ttyAMA10` 開機、登入及除錯 |
| I2C / SPI | 尚未實測 | 建置設定不等於實體周邊通訊已通過 |
| 伺服器電源／Reset | ❌ | 需要額外 GPIO 隔離與受控主機 |
| Host IPMI（KCS/BT） | ❌ | Pi 5 沒有 LPC/eSPI BMC 介面 |
| KVM / Virtual Media / SOL | ❌ | 需要額外視訊、USB gadget 或主機串列線路 |
| 線上更新 SD 卡映像 | ❌ | 本映像沒有產品級 A/B 更新配置 |

## 最快開始

建議使用 Ubuntu 24.04 實體 Linux，或 Windows 上的 WSL 2 Ubuntu。建置目錄
必須位在 Linux 檔案系統，不能放在 WSL 的 `/mnt/c`。Yocto Wrynose 官方文件
列出的參考資源是至少 140 GiB 可用空間與 32 GiB RAM；核心多、SSD 快會明顯
縮短第一次建置時間。

第一次取得專案時，先在 Ubuntu 的 Linux 檔案系統建立工作樹；若下列目錄已存在，直接使用既有工作樹，不要覆蓋：

```bash
mkdir -p ~/src
git clone --branch main https://github.com/learningyun-tech/rpi5-openbmc-portfolio.git ~/src/rpi5-openbmc-portfolio
```

以下命令只在有意建置映像時執行；僅更新 GitHub 文件不必重跑。每個階段的原理、產物及成功判準，請見[建置流程解析](docs/openbmc-build-guide-zh-TW.md)。

```bash
cd ~/src/rpi5-openbmc-portfolio
chmod +x scripts/*.sh
./scripts/install-build-deps-ubuntu.sh
./scripts/tmux-build.sh configure
./scripts/tmux-build.sh attach
# configure 成功且 tmux session 結束後：
./scripts/tmux-build.sh build
```

長時間建置建議使用上述 tmux 助手；按 `Ctrl+B`、放開後按 `D`，可離開畫面但讓
工作繼續。狀態與日誌指令見 [tmux 建置教學](docs/tmux-build-zh-TW.md)。不需要
背景 session 時，原本的 `./scripts/build.sh configure` 與 `build` 仍可使用。

Linux 原生主機燒錄：

```bash
lsblk -o NAME,SIZE,MODEL,TRAN,MOUNTPOINTS
sudo ./scripts/flash.sh /dev/sdX
```

`flash.sh` 會拒絕 partition 或仍有掛載點的磁碟，並要求再次輸入完整裝置名稱；
`/dev/sdX` 必須換成 microSD 的整顆磁碟，選錯會清除該磁碟。

Windows / WSL 2：

```bash
./scripts/export-image.sh
```

把產生的映像複製到自己的 Windows 下載目錄，再於 Raspberry Pi Imager 選擇「Choose OS → Use custom」，指定 `.img`。

完整操作請從 [繁體中文逐步教學](docs/tutorial-zh-TW.md) 開始；若使用
VMware Ubuntu 24.04，請直接依照
[VMware Ubuntu 24.04 完整安裝教學](docs/vmware-ubuntu-24.04-install-zh-TW.md)。

## 第一次開機

1. 插入燒錄好的 microSD，接上有線 Ethernet，再接 Pi 5 電源。
2. 從路由器 DHCP client 清單找主機名 `rpi5-openbmc` 的位址。
3. 預設帳號為 `root`，上游實驗映像預設密碼為 `0penBmc`（第一個字元是數字
   `0`）。立刻在隔離的實驗網路上執行 `ssh root@<IP>` 與 `passwd`。
4. 開啟 `https://<IP>/`。第一次看到自簽憑證警告是預期現象。
5. 在開發主機執行 `./scripts/smoke-test.sh <IP>` 驗證 Redfish 與真實溫度。

請勿把仍使用預設密碼或自簽憑證的裝置直接暴露到 Internet。

## 架構

```text
Pi 5 thermal_zone ──> rpi5-openbmc-simulator ──> OpenBMC D-Bus
                                                   │
                         ┌─────────────────────────┼──────────────┐
                         ▼                         ▼              ▼
                    bmcweb/Redfish             busctl        Web UI
                         │
                         ▼
        /redfish/v1/Chassis/RPi5/Sensors/temperature_CPU_Temperature
```

自訂服務同時發布 Chassis inventory 與 `all_sensors` association，因此 `bmcweb`
能把 D-Bus Sensor 正確映射到 `RPi5` Chassis。詳細設計見
[架構說明](docs/architecture.md)。

## 版本與目錄

- 上游版本鎖在 [`upstream.lock`](upstream.lock)，目前為 OpenBMC `wrynose`
  commit `b48d8890dac29b8954f47a8ce17645d5f9897782`。
- [`meta-rpi5-openbmc`](meta-rpi5-openbmc) 是本專案的 Yocto layer。
- [`config/local.conf`](config/local.conf) 是 Pi 5 建置政策。
- [`scripts/build.sh`](scripts/build.sh) 負責抓取鎖定版本、設定 layer 與建置。
- [`scripts/tmux-build.sh`](scripts/tmux-build.sh) 在可重新連線的背景 session
  執行長時間建置並保存狀態與日誌。
- [`scripts/smoke-test.sh`](scripts/smoke-test.sh) 建立短期 Redfish session 後測試。
- `./scripts/test-static.sh` 可在 Linux/WSL 快速驗證腳本與 metadata 一致性。
- `work/` 與 `artifacts/` 是產物，不納入 Git。

## 已知限制

本專案已有 Ubuntu 建置、microSD 部署、Pi 開機、5 GHz Wi-Fi、SSH 與 Redfish 的實測紀錄，範圍與限制見[實機驗收報告](docs/interview-closeout-20261014-zh-TW.md)。

版本鎖定與建置設定有助重建，但尚未從全新 clone 完成乾淨環境重建，不能宣稱已完整驗證可重現或具量產資格。UART 已實測，I2C／SPI 實體通訊及其他未驗證項目維持原標示；更新上游基準後應重新建置及驗證。

遇到問題請看 [疑難排解](docs/troubleshooting-zh-TW.md)。

## 官方參考資料

- [OpenBMC 建置說明](https://github.com/openbmc/openbmc/tree/wrynose)
- [OpenBMC Raspberry Pi EVB template](https://github.com/openbmc/openbmc/tree/wrynose/meta-evb/meta-evb-raspberrypi)
- [meta-raspberrypi 的 Pi 5 machine 設定](https://github.com/openbmc/openbmc/blob/wrynose/upstream-layers/meta-raspberrypi/conf/machine/raspberrypi5.conf)
- [Yocto Wrynose 系統需求](https://docs.yoctoproject.org/wrynose/ref-manual/system-requirements.html)
- [OpenBMC Redfish 說明](https://github.com/openbmc/bmcweb/blob/master/docs/Redfish.md)
- [Raspberry Pi 溫度監控說明](https://www.raspberrypi.com/documentation/computers/config_txt.html#monitoring-core-temperature)

本專案採 Apache-2.0 授權；上游元件各自依原授權條款散布。

## 實機驗證與已知限制

實測項目、資料路徑與尚未驗證功能，請見[實機驗收報告](docs/interview-closeout-20261014-zh-TW.md)。
