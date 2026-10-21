# VMware Ubuntu 24.04：Raspberry Pi 5 OpenBMC 完整安裝教學

本教學適用於：Windows 主機、VMware 內的 Ubuntu 24.04、Raspberry Pi 5、
16 GB microSD，以及有線區域網路。3.3 V USB-TTL UART 不是必要設備。

> 你仍需要能讀寫 microSD 的裝置，例如 USB-A microSD 讀卡機，或電腦內建
> SD 讀卡機加 microSD 轉卡。一般 USB-A 傳輸線本身不能讀寫裸 microSD。

## 0. 先理解流程

```text
Windows 專案資料夾
        │（VMware Shared Folder，只搬檔）
        ▼
Ubuntu 虛擬磁碟 ~/src/rpi5-openbmc-portfolio
        │（下載原始碼、BitBake 建置）
        ▼
rpi5-openbmc-lab.img
        │
        ├─ 方法 A：搬回 Windows，用 Raspberry Pi Imager 燒錄（建議）
        └─ 方法 B：USB 讀卡機直通 VMware，在 Ubuntu 燒錄
        ▼
microSD → Raspberry Pi 5 → Ethernet DHCP → Web / Redfish / SSH
```

16 GB microSD 是目標裝置的儲存空間，不能取代建置所需的虛擬硬碟空間。

## 1. 準備硬體

- Raspberry Pi 5 與散熱器或風扇。
- 16 GB microSD。
- USB-A microSD 讀卡機，或內建 SD 讀卡機與 microSD 轉卡。
- 一條 Ethernet 網路線，連接 Pi 5 與有 DHCP 的路由器或交換器。
- 穩定 USB-C 電源；建議使用 Raspberry Pi 27 W 電源。最低至少準備品質良好的
  5 V / 3 A 電源，避免開機或高負載時欠壓。

## 2. 設定 VMware 虛擬機資源

先關閉虛擬機，再調整設定。建議：

- 8 個 vCPU。
- 32 GB RAM 最理想；16 GB RAM 也可嘗試，但第一次建置會更慢。
- Ubuntu 虛擬磁碟至少保留 200 GB 可用空間，並確認實體 Windows 磁碟也有空間。
- 網路先用 NAT 即可；若日後 VM 找不到 Pi 5，可改成 Bridged。
- 若要從 Ubuntu 直接燒錄，虛擬機設定中必須有 USB Controller。

登入 Ubuntu 後檢查：

```bash
lsb_release -a
nproc
free -h
df -h /
```

`df -h /` 的 `Avail` 建議大於 200G。至少要保留約 140 GiB，否則 BitBake
很可能在建置途中耗盡空間。

## 3. 把專案複製進 Ubuntu 虛擬磁碟

### 方法 3A：VMware Shared Folder

在 VMware 的虛擬機設定啟用 Shared Folders，將 Windows 的專案上層資料夾
分享給 Ubuntu。若 Ubuntu 看不到 `/mnt/hgfs`，先安裝 VMware Tools：

```bash
sudo apt update
sudo apt install -y open-vm-tools open-vm-tools-desktop
sudo reboot
```

重新登入後：

```bash
ls /mnt/hgfs
mkdir -p ~/src
cp -a "/mnt/hgfs/<共享名稱>/BMC&嵌入式相關" ~/src/rpi5-openbmc-portfolio
cd ~/src/rpi5-openbmc-portfolio
chmod +x scripts/*.sh
```

把 `<共享名稱>` 改成 `ls /mnt/hgfs` 顯示的名稱。如果分享的就是專案本身，
來源可能是 `/mnt/hgfs/<共享名稱>`，不用再加 `BMC&嵌入式相關`。

**不要**直接在 `/mnt/hgfs` 內執行 BitBake。腳本也會主動阻止這個用法。

### 方法 3B：其他傳檔方式

也可用 SCP、Git、壓縮檔或 VMware 拖放把專案放到
`~/src/rpi5-openbmc-portfolio`。不論用哪一種方式，最後確認：

```bash
cd ~/src/rpi5-openbmc-portfolio
test -f upstream.lock && test -x scripts/build.sh && echo "專案就緒"
```

應看到 `專案就緒`。

## 4. 處理 Ubuntu 24.04 的 AppArmor 限制

Ubuntu 24.04 預設可能限制 BitBake 需要的 unprivileged user namespace。
依 OpenBMC 官方開發環境文件，在這台專用建置 VM 執行：

```bash
echo 'kernel.apparmor_restrict_unprivileged_userns = 0' | \
  sudo tee /etc/sysctl.d/99-bitbake.conf
sudo sysctl -p /etc/sysctl.d/99-bitbake.conf
```

確認輸出包含：

```text
kernel.apparmor_restrict_unprivileged_userns = 0
```

這會降低該 VM 對未授權 user namespace 的限制，所以建議把這台 VM 當成
專用開發環境，不要同時執行不受信任的程式。

## 5. 安裝建置工具

```bash
cd ~/src/rpi5-openbmc-portfolio
./scripts/install-build-deps-ubuntu.sh
./scripts/test-static.sh
```

安裝腳本會使用 `sudo apt`。靜態測試成功時，最後應看到所有檢查通過；若腳本
因 Windows 複製後失去執行權限，重新執行：

```bash
chmod +x scripts/*.sh
```

## 6. 下載鎖定版本並產生 BitBake 設定

請用一般使用者執行，不要加 `sudo`：

```bash
cd ~/src/rpi5-openbmc-portfolio
./scripts/build.sh configure
```

這一步會：

1. 下載 `upstream.lock` 指定的 OpenBMC `wrynose` commit。
2. 建立 `work/build-rpi5`。
3. 加入本專案的 `meta-rpi5-openbmc` layer。
4. 解析全部 BitBake metadata。

成功時最後會顯示：

```text
設定與 metadata 解析成功：.../work/build-rpi5
```

若已安裝 tmux，建議改用背景助手，避免關閉 Terminal 後工作中止：

```bash
./scripts/tmux-build.sh configure
./scripts/tmux-build.sh attach
```

離開 tmux 且保持工作執行：按 `Ctrl+B`，放開後再按 `D`。也可以在一般終端用
`./scripts/tmux-build.sh status` 或 `log` 查看結果。完整操作見
[tmux 建置教學](tmux-build-zh-TW.md)。

## 7. 視 VM 記憶體調整平行度（選用）

若 VM 只有 16 GB RAM，先編輯：

```bash
nano work/build-rpi5/conf/local-extra.conf
```

加入：

```conf
BB_NUMBER_THREADS = "6"
PARALLEL_MAKE = "-j 6"
```

如果 VM 只有 4 個 vCPU，或建置時程序被 OOM killer 終止，兩個數字都改為
`4`。按 `Ctrl+O`、Enter 儲存，再按 `Ctrl+X` 離開。

## 8. 建置 OpenBMC 映像

```bash
cd ~/src/rpi5-openbmc-portfolio
./scripts/build.sh build
```

建議的 tmux 方式是：

```bash
./scripts/tmux-build.sh build
./scripts/tmux-build.sh attach
```

第一次建置會下載大量原始碼並編譯整個 Linux 系統，可能需要數小時。不可關閉
VM，也不要讓 Windows 睡眠。中斷後通常可重跑同一條命令，BitBake 會沿用已完成
的產物。

成功後主要檔案在：

```text
work/build-rpi5/tmp/deploy/images/raspberrypi5/
  rpi5-obmc-lab-image-raspberrypi5.rootfs.wic.bz2
  rpi5-obmc-lab-image-raspberrypi5.rootfs.wic.bmap
```

確認：

```bash
ls -lh work/build-rpi5/tmp/deploy/images/raspberrypi5/*wic*
```

## 9. 產生 Windows 可燒錄的 `.img`

```bash
cd ~/src/rpi5-openbmc-portfolio
./scripts/export-image.sh
sha256sum -c artifacts/rpi5-openbmc-lab.img.sha256
ls -lh artifacts/
```

校驗成功會顯示 `OK`。接著從下列兩種燒錄方法擇一。

## 10A. 在 Windows 燒錄（建議）

這條路不需要讓 VMware 直接控制 USB 裝置，較不容易選錯 Ubuntu 系統磁碟。

1. 將 `artifacts/rpi5-openbmc-lab.img` 複製回 Shared Folder：

   ```bash
   cp artifacts/rpi5-openbmc-lab.img "/mnt/hgfs/<共享名稱>/"
   cp artifacts/rpi5-openbmc-lab.img.sha256 "/mnt/hgfs/<共享名稱>/"
   ```

2. 在 Windows 安裝並開啟 Raspberry Pi Imager。
3. 把 microSD 插入 USB-A 讀卡機，再插到 Windows 電腦。
4. 在 Imager 選 Raspberry Pi 5。
5. 選擇作業系統時，使用 `Use custom`／`使用自訂映像`，指定
   `rpi5-openbmc-lab.img`。
6. 儲存裝置只能選該張 16 GB microSD。仔細核對容量；寫入會清除整張卡。
7. 不要套用 Raspberry Pi OS 的 Wi-Fi、使用者或 SSH 自訂設定；那些不是
   OpenBMC 的設定格式。
8. 開始寫入並等待 Imager 驗證完成，再安全退出 microSD。

## 10B. 將 USB 讀卡機直通 VMware，在 Ubuntu 燒錄

1. 插入讀卡機前先在 Ubuntu 執行：

   ```bash
   lsblk -o NAME,SIZE,MODEL,TRAN,FSTYPE,MOUNTPOINTS
   ```

2. 把 microSD 插進 USB-A 讀卡機並連到 Windows。
3. 在 VMware 選 `VM > Removable Devices > <讀卡機> > Connect
   (Disconnect from Host)`。裝置旁應出現已連線記號。
4. 在 Ubuntu 再執行一次 `lsblk`，找出新出現、容量約 14～16 GB 的整顆磁碟，
   例如 `/dev/sdb`。名稱依電腦而異，**不要直接照抄 `/dev/sdb`**。
5. 若桌面自動掛載分割區，先卸載。假設分割區為 `/dev/sdX1`、`/dev/sdX2`：

   ```bash
   sudo umount /dev/sdX1
   sudo umount /dev/sdX2
   ```

   不存在的分割區出現錯誤可忽略；再次用 `lsblk` 確認 `MOUNTPOINTS` 為空。

6. 把 `sdX` 換成剛才確認的整顆 microSD 裝置，再執行：

   ```bash
   cd ~/src/rpi5-openbmc-portfolio
   sudo ./scripts/flash.sh /dev/sdX
   ```

7. 腳本會再次列出型號、容量並要求輸入完整裝置名稱。只有完全確定時才確認。
   成功後先在 VMware 中 Disconnect，再拔讀卡機。

## 11. Raspberry Pi 5 第一次開機

1. Pi 5 保持斷電，插入已燒錄的 microSD。
2. 接上散熱、Ethernet；Ethernet 另一端接有 DHCP 的路由器。
3. 最後接 USB-C 電源。
4. 等待約 3～5 分鐘。第一次啟動可能比之後久。
5. 到路由器管理頁面的 DHCP client／已連接裝置清單，尋找主機名
   `rpi5-openbmc`，記下 IP，例如 `192.168.1.123`。

沒有 UART 不影響正常操作；管理介面全部從 Ethernet 存取。

## 12. 驗證 SSH、Web UI 與 Redfish

在 Ubuntu VM 執行，將 `<PI_IP>` 換成實際位址：

```bash
ping -c 4 "<PI_IP>"
ssh "root@<PI_IP>"
```

開發映像的初始登入資料：

```text
帳號：root
密碼：0penBmc
```

密碼第一個字元是數字 `0`。首次登入後立即執行：

```bash
passwd
```

離開 SSH 後執行專案測試：

```bash
cd ~/src/rpi5-openbmc-portfolio
./scripts/smoke-test.sh "<PI_IP>"
```

腳本會要求輸入剛設定的新密碼，並檢查 Redfish Service Root、Manager、Chassis
與 Pi 5 CPU 溫度 Sensor。也可在 Windows 瀏覽器開啟：

```text
https://<PI_IP>/
```

開發映像使用自簽 TLS 憑證，第一次看到瀏覽器警告是預期現象。僅在隔離的實驗
網路接受該憑證，不要把預設密碼或自簽憑證的裝置暴露到 Internet。

## 13. 找不到 Pi 5 時

依序檢查：

1. Pi 5 Ethernet 接頭的 Link LED 是否亮起。
2. 路由器 DHCP 清單有沒有 `rpi5-openbmc` 或新裝置。
3. 電源是否足夠，microSD 是否插到底。
4. 重新用 Imager 的驗證功能燒錄。
5. Ubuntu VM 若無法連到 Pi，但 Windows 可以，將 VMware 網路改為 Bridged，
   或直接從 Windows 瀏覽器測試 `https://<PI_IP>/`。
6. 建置若出現 `/proc/self/uid_map` 或 `PermissionError`，重做第 4 步。
7. 建置若顯示 `Killed` 或 out-of-memory，降低第 7 步的 thread 數並增加 VM RAM。

## 14. 完成標準

達成下列項目即表示安裝完成：

- Pi 5 可從 microSD 穩定開機並取得 DHCP 位址。
- 可用新密碼 SSH 登入。
- `https://<PI_IP>/redfish/v1/` 有 JSON 回應。
- `smoke-test.sh` 通過。
- Redfish 可讀到 `CPU_Temperature`，數值會隨負載變動。

這個專案是在 Pi 5 上建立 OpenBMC 學習平台，不等於完整伺服器主機板 BMC。
Pi 5 本身沒有 LPC/eSPI/KCS、主機 KVM 擷取、主機電源隔離控制等硬體介面。

## 官方參考

- [OpenBMC 建置與相依套件](https://github.com/openbmc/openbmc/blob/master/README.md)
- [OpenBMC 開發環境與 Ubuntu 24.04 AppArmor](https://github.com/openbmc/docs/blob/master/development/dev-environment.md)
- [Yocto Wrynose 系統需求](https://docs.yoctoproject.org/wrynose/ref-manual/system-requirements.html)
- [OpenBMC Wrynose 的 Raspberry Pi 5 machine](https://github.com/openbmc/openbmc/blob/wrynose/upstream-layers/meta-raspberrypi/conf/machine/raspberrypi5.conf)
- [VMware USB 裝置連線說明](https://knowledge.broadcom.com/external/article/418689/connecting-usb-devices-to-a-virtual-mach.html)
- [Raspberry Pi Imager](https://www.raspberrypi.com/software/)
- [Raspberry Pi 5 電源需求](https://www.raspberrypi.com/documentation/computers/raspberry-pi.html#power-supply)
