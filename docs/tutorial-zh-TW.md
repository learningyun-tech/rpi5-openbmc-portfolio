# Raspberry Pi 5 OpenBMC 完整教學

本教學從建置主機準備、產生映像、燒錄、第一次開機，到 Web UI、Redfish 與
D-Bus 驗證完整走一次。命令預設在專案根目錄執行。

## 1. 準備硬體

建議準備：

- Raspberry Pi 5（4 GB 或以上較舒適；執行映像不等於建置映像）
- 32 GB 以上、品質良好的 microSD
- 官方 27 W USB-C 電源，或符合 Pi 5 規格的可靠電源
- 主動散熱器或有風扇的外殼
- 有線 Ethernet 與可提供 DHCP 的路由器
- microSD 讀卡機
- 選配：3.3 V USB-TTL UART（絕不可接傳統 ±12 V RS-232，也不要把轉接器
  的 5 V 接到 Pi）

Raspberry Pi 官方對 Pi 5 建議 27 W 電源；高負載時良好散熱可避免 CPU 因
80–85 °C 區間而降頻。本專案的 Sensor 警告與嚴重門檻分別設為 75 °C 和
85 °C。

## 2. 準備 Linux 建置主機

### 2.1 建議規格

- Ubuntu 22.04、24.04 或 26.04 LTS
- 140 GiB 以上可用 SSD 空間
- 32 GiB RAM（較少記憶體可嘗試限制平行度，但建置會更慢）
- 穩定網路；第一次建置會下載大量原始碼

Yocto 只能在 Linux 環境建置。WSL 2 可使用，但不是 Yocto 官方驗證的建置
主機；最重要的是 build directory 不可放在 `/mnt/c`。

### 2.2 Windows 使用者：在 WSL 2 取得作品集

先在 PowerShell 確認使用 WSL 2：

```powershell
wsl -l -v
```

若尚未安裝，可在系統管理員 PowerShell 執行：

```powershell
wsl --install -d Ubuntu-24.04
```

進入 Ubuntu 後，把作品集下載到 WSL 的 Linux 檔案系統；下列目錄若已存在，直接使用原工作樹，不要覆蓋：

```bash
mkdir -p ~/src
git clone --branch main https://github.com/learningyun-tech/rpi5-openbmc-portfolio.git ~/src/rpi5-openbmc-portfolio
cd ~/src/rpi5-openbmc-portfolio
chmod +x scripts/*.sh
```

後續所有建置命令都在 `~/src/rpi5-openbmc-portfolio` 執行。

### 2.3 安裝相依套件

```bash
./scripts/install-build-deps-ubuntu.sh
```

腳本依 Yocto Wrynose 的 Ubuntu/Debian套件清單安裝編譯器、Python、壓縮工具、
`bmaptool`、`jq` 與 `shellcheck`，並啟用 `en_US.UTF-8` locale。

## 3. 了解建置內容

`scripts/build.sh` 會：

1. 讀取 `upstream.lock`。
2. 下載 OpenBMC `wrynose` 並 checkout 鎖定 commit。
3. 使用有效的 Phosphor default template 初始化 BitBake，再明確加入 Raspberry Pi BSP layer。
4. 寫入本專案的 `config/local.conf`。
5. 加入 `meta-rpi5-openbmc` layer。
6. 建置 `rpi5-obmc-lab-image`。

原始碼、下載快取、sstate 與建置產物都放在 `work/`，不會污染上游 Git。

先只設定並解析 metadata：

```bash
./scripts/build.sh configure
```

最後看到 `Parsing of ... recipes complete` 與「設定與 metadata 解析成功」才算
通過。若這一步失敗，先不要燒錄，直接查閱疑難排解。

## 4. 建置映像

長時間建置建議透過專案的 tmux 助手執行：

```bash
./scripts/tmux-build.sh configure
./scripts/tmux-build.sh attach
```

離開即時畫面但保持工作執行：先按 `Ctrl+B`，放開後再按 `D`。configure
成功後，用同樣方式正式建置：

```bash
./scripts/tmux-build.sh build
```

可隨時在一般終端查看狀態或最近 100 行：

```bash
./scripts/tmux-build.sh status
./scripts/tmux-build.sh log
```

詳細按鍵與日誌說明見 [tmux 建置教學](tmux-build-zh-TW.md)。原本的前景建置
命令仍然有效。

```bash
./scripts/build.sh build
```

第一次完整建置依 CPU、SSD 與網路可能需要數小時。中斷後可執行同一命令續建；
BitBake 會使用 `work/downloads` 與 `work/sstate-cache`。

成功產物位於：

```text
work/build-rpi5/tmp/deploy/images/raspberrypi5/
```

檢查檔案：

```bash
ls -lh work/build-rpi5/tmp/deploy/images/raspberrypi5/*wic*
```

若要調整建置執行緒，編輯保留用的
`work/build-rpi5/conf/local-extra.conf`，不要直接編輯產生的 `local.conf`：

```bitbake
BB_NUMBER_THREADS = "8"
PARALLEL_MAKE = "-j 8"
```

## 5. 燒錄 microSD

### 5.1 Linux 原生建置主機

插入 microSD 後先辨識裝置：

```bash
lsblk -o NAME,SIZE,MODEL,TRAN,FSTYPE,MOUNTPOINTS
```

假設 microSD 是 `/dev/sdb`，先從桌面檔案管理器退出所有自動掛載的 partition，
再執行：

```bash
sudo ./scripts/flash.sh /dev/sdb
```

不要照抄 `/dev/sdb`。腳本只接受整顆 `disk`、拒絕仍掛載的裝置，最後還會顯示
型號與序號並要求輸入完整裝置名稱。

### 5.2 Windows + WSL 2

在 WSL 內將壓縮 WIC 匯出為 Windows 工具可用的 raw image：

```bash
./scripts/export-image.sh
cp artifacts/rpi5-openbmc-lab.img /mnt/c/Users/asdf7/Downloads/
cp artifacts/rpi5-openbmc-lab.img.sha256 /mnt/c/Users/asdf7/Downloads/
```

在 Windows 開啟 Raspberry Pi Imager：

1. Device 選 Raspberry Pi 5。
2. OS 選 `Use custom`，指定 `rpi5-openbmc-lab.img`。
3. Storage 仔細選 microSD。
4. 不要套用 Raspberry Pi OS 的使用者、Wi-Fi 或 SSH 自訂設定；這不是
   Raspberry Pi OS。
5. 寫入並完成驗證後退出 microSD。

## 6. 第一次開機與找 IP

1. 先接有線 Ethernet。
2. 插入 microSD。
3. 最後接電源。
4. 等候約 2–5 分鐘；第一次啟動會產生 SSH／HTTPS 金鑰，通常比後續慢。
5. 到路由器 DHCP client/lease 清單尋找 `rpi5-openbmc`。

若路由器不顯示主機名，可從序列 console 登入後執行：

```bash
networkctl status
ip -brief address
```

預設登入資料：

```text
username: root
password: 0penBmc
```

密碼第一個字元是數字 `0`。這只是上游開發預設值；找到 IP 後立刻修改：

```bash
ssh "root@<BMC-IP>"
passwd
```

只在隔離的可信任 LAN 上完成第一次登入，不要做路由器 port forwarding。

## 7. Web UI 與 Redfish 驗證

瀏覽器開啟：

```text
https://<BMC-IP>/
```

實驗映像使用裝置自簽 HTTPS 憑證，第一次瀏覽器警告是預期現象。登入後可查看
Overview、Logs、Users 與 Network。

在建置主機執行完整 smoke test：

```bash
./scripts/smoke-test.sh "<BMC-IP>"
```

腳本會安全地提示密碼、建立短期 Redfish session、讀取下列資源，最後刪除
session：

```text
/redfish/v1/
/redfish/v1/Managers/bmc
/redfish/v1/Chassis/RPi5
/redfish/v1/Chassis/RPi5/Sensors
/redfish/v1/Chassis/RPi5/Sensors/CPU_Temperature
```

最後一個回應應包含類似：

```json
{
  "Id": "CPU_Temperature",
  "Reading": 48.2,
  "ReadingUnits": "Cel"
}
```

實際欄位會隨 bmcweb 的 Redfish schema 版本略有差異；重點是 HTTP 成功、Sensor
存在，且讀值合理。

## 8. 在裝置上驗證 D-Bus

將專案的檢查腳本複製到 Pi，或逐行執行內容：

```bash
scp scripts/on-target-check.sh "root@<BMC-IP>:/tmp/"
ssh "root@<BMC-IP>" 'bash /tmp/on-target-check.sh'
```

只查溫度屬性可用：

```bash
busctl get-property xyz.openbmc_project.RPi5.Simulator \
  /xyz/openbmc_project/sensors/temperature/CPU_Temperature \
  xyz.openbmc_project.Sensor.Value Value
```

檢視服務日誌：

```bash
journalctl -u rpi5-openbmc-simulator.service -f
```

## 9. 修改程式後增量建置

修改 `meta-rpi5-openbmc/recipes-rpi5/simulator/files/main.cpp` 後，直接執行：

```bash
./scripts/build.sh build
```

若只想確認自訂 recipe 能編譯：

```bash
./scripts/build.sh shell
bitbake rpi5-openbmc-simulator
exit
```

BitBake 會偵測 layer 內的本地檔案變更並重做相依工作。

## 10. 下一步實驗

- 在 I2C 接入 TMP102、INA219 等 Sensor，改用 `dbus-sensors`/Entity Manager。
- 使用光耦或隔離電路把 GPIO 接到另一台測試主機的 Power/Reset header，再實作
  chassis control；切勿直接把不明電壓接到 Pi GPIO。
- 以受控主機 UART 製作 SOL 原型。
- 用正式 CA 簽發的憑證替換自簽憑證，並建立非 root 帳號與最小權限角色。
- 為自訂 daemon 加入 phosphor-logging 事件與自動化測試。

先理解 [架構說明](architecture.md) 與 [限制](../README.md#已知限制)，再增加會
控制實體硬體的功能。
