# 疑難排解

## tmux 顯示已有 session

同一份專案一次只能執行一個 configure 或 build。先查看現有工作：

```bash
./scripts/tmux-build.sh status
./scripts/tmux-build.sh attach
```

離開 tmux 且保持建置執行時，先按 `Ctrl+B`，放開後再按 `D`。不要在 tmux
建置畫面按 `Ctrl+C`，那會正常中止 BitBake。

若 `status` 說沒有 session，但狀態檔仍顯示「執行中」，通常是 VM 曾關機、
tmux server 被終止，或程序異常離開。查看最後輸出後重新執行原工作：

```bash
./scripts/tmux-build.sh log
./scripts/tmux-build.sh build
```

BitBake 通常會沿用已完成的產物。tmux 只能承受 Terminal 或 SSH 中斷；VM
關機、重新啟動或 Windows 進入睡眠仍會中斷建置。

## `build.sh` 拒絕 `/mnt/c/...`

這是預期保護。BitBake 大量使用 symlink、檔案權限、大小寫與高頻小檔案 I/O；
Yocto 官方也明確說 WSL build directory 不應放在 Windows 掛載點。依教學把整個
專案複製到 `~/src/rpi5-openbmc-portfolio` 後再建置。

## `locale` 或 sanity check 失敗

重新執行：

```bash
./scripts/install-build-deps-ubuntu.sh
locale -a | grep -i en_US
```

應看到 `en_US.utf8`。

## 磁碟空間不足

查看：

```bash
df -h ~/src/rpi5-openbmc-portfolio
du -sh work/* 2>/dev/null | sort -h
```

保留 `work/downloads` 與 `work/sstate-cache` 能加速重建。若確定不需要舊的完整
工作目錄，可在確認絕對路徑後手動處理 `work/build-rpi5/tmp`；不要刪整個專案或
不明路徑。

## `bitbake -p` 顯示 layer series 不相容

`meta-rpi5-openbmc/conf/layer.conf` 只宣告 `wrynose`。通常代表 `upstream.lock`
與本 layer 不再同版，或 `OPENBMC_DIR` 指到別的 clone。檢查：

```bash
git -C work/openbmc rev-parse HEAD
grep OPENBMC_COMMIT upstream.lock
```

兩者必須相同。不要只刪掉相容性檢查；應先移植 recipe/API。

## 編譯自訂 daemon 失敗

進入 BitBake 環境重做單一 recipe 並顯示詳細 log：

```bash
./scripts/build.sh shell
bitbake -c cleansstate rpi5-openbmc-simulator
bitbake -v rpi5-openbmc-simulator
exit
```

錯誤 log 通常位於：

```text
work/build-rpi5/tmp/work/cortexa76-*/rpi5-openbmc-simulator/*/temp/log.do_compile
```

## Pi 5 沒有開機

依序檢查：

1. 使用 Pi 5 可用的可靠 USB-C 電源與散熱。
2. 確認燒的是解壓後 raw `.img` 或直接用 `bmaptool` 寫入 `.wic.bz2`，不是把
   壓縮檔當一般檔案複製到 FAT partition。
3. 重新用 Imager 驗證 microSD。
4. 接 UART console，確認是否停在 bootloader、kernel 或 systemd。
5. 檢查綠色 activity LED pattern 與電源狀態。

## 有開機但拿不到 DHCP

用 UART 登入後執行：

```bash
ip link
networkctl --no-pager status
systemctl status systemd-networkd xyz.openbmc_project.Network.service
journalctl -b -u systemd-networkd --no-pager
```

請先使用有線 Ethernet；本教學不配置 Wi-Fi credential。確認網路有 DHCP server，
並嘗試更換網路線與 switch port。

## Web UI 打不開

在裝置上：

```bash
systemctl status bmcweb
ss -lntp | grep ':443'
journalctl -b -u bmcweb --no-pager
```

在開發主機：

```bash
curl -vk https://<BMC-IP>/redfish/v1/
```

自簽憑證會造成驗證警告，但不應造成 TCP connection refused。

## Chassis 存在但 Sensor collection 是空的

確認服務、Sensor 與 association：

```bash
systemctl status rpi5-openbmc-simulator
busctl tree xyz.openbmc_project.RPi5.Simulator
busctl introspect xyz.openbmc_project.RPi5.Simulator \
  /xyz/openbmc_project/sensors/temperature/CPU_Temperature
busctl get-property xyz.openbmc_project.ObjectMapper \
  /xyz/openbmc_project/inventory/system/chassis/RPi5/all_sensors \
  xyz.openbmc_project.Association endpoints
```

若 simulator 正常但 mapper 沒 endpoint，查看兩者本次開機 log：

```bash
journalctl -b -u rpi5-openbmc-simulator \
  -u xyz.openbmc_project.ObjectMapper.service --no-pager
```

## Sensor 顯示 unavailable 或 `NaN`

先看 kernel 是否提供 thermal zone：

```bash
find /sys/class/thermal -maxdepth 2 -name temp -print -exec cat {} \;
journalctl -u rpi5-openbmc-simulator --no-pager
```

daemon 找不到任何介於 -40 °C 與 150 °C 的 millidegree 讀值時，會把
`Available` 與 `Functional` 設為 false。這通常是 kernel/device-tree 問題，而
不是 Redfish 問題。

## `flash.sh` 說 partition 仍掛載

腳本不會替你自動卸載，以免卸錯系統磁碟。先用 `lsblk` 查清楚，再逐一卸載該
microSD 的 partition，例如：

```bash
sudo umount /dev/sdb1 /dev/sdb2
```

務必把裝置名稱換成實際 microSD；若任何 partition 是 `/`、`/home`、WSL 磁碟
或你不確定用途，立刻停止。
