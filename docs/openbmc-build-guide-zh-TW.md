# OpenBMC 建置流程解析：Raspberry Pi 5 面試專案

文件整理日期：2026-10-21。本文依作品集中的建置腳本、設定與 recipe 說明「為什麼這樣建置」。另建儲存庫與更新文件不代表重新建置或重新測試；既有實機結果來自原實驗環境，請見[實機驗收報告](interview-closeout-20261014-zh-TW.md)。

> 已有建置成果、只是更新 GitHub 文件的人，不必執行下面的安裝、configure、build 或燒錄流程。這些步驟是供閱讀、除錯與有意重新建置時使用；沒有執行的步驟不能填成已完成。

## 1. 先用一分鐘說清楚專案

這是把上游 OpenBMC、Raspberry Pi 板級支援和自訂 Yocto layer 整合到 Pi 5 的學習專案。核心展示是：自訂 C++ 服務讀取真實 Linux thermal sysfs 溫度，發布 D-Bus Sensor，再由 bmcweb 提供 Redfish 查詢。

本案不是自己從零寫 Linux 核心或 Broadcom Wi-Fi 驅動，也沒有完成另一台伺服器的電源控制、KCS/eSPI、KVM 或產品級韌體更新。面試時應說明自己的實際操作、整合理解與測試證據，而不是把上游功能都當成自己實作。

建置路徑與執行期資料路徑不同：

```text
建置：Ubuntu → OpenBMC + BSP + 自訂 layer → BitBake → ARM64 套件與系統映像
部署：系統映像 → microSD → Pi 開機 → systemd 啟動管理服務
資料：Pi thermal sysfs → C++ 服務 → D-Bus Sensor → bmcweb → Redfish 用戶端
```

## 2. 分清楚四個位置

| 位置 | 工作 | 不應混淆的事 |
| --- | --- | --- |
| Windows | 執行 VMware，保存另一份文件／原始碼副本 | 改 Windows 檔案，不代表 Ubuntu 工作樹或 Pi 已更新 |
| Ubuntu VM | 建置、測試、執行 Git、SSH 與 curl | 本作品集工作樹為 `/home/jack/src/rpi5-openbmc-portfolio`；既有實測在原實驗工作樹完成 |
| Raspberry Pi 5 | 執行已部署的 ARM64 OpenBMC 映像 | SSH 或 UART 登入後，命令是在 Pi 上執行 |
| GitHub | 保存已提交的原始碼、設定及文件 | `git push` 不會編譯程式，也不會更新 Pi |

以下專案內命令預設在 Ubuntu 的專案根目錄執行。進入 BitBake shell 後，工作目錄通常會改成建置目錄；Pi 命令會另外標示。

## 3. 先認識建置名詞與檔案分工

| 名稱 | 含義 | 本案對應 |
| --- | --- | --- |
| OpenBMC | 以 Linux 和管理服務組成的開源 BMC 軟體堆疊 | 上游 `openbmc/openbmc` 原始碼與 metadata |
| Yocto Project | 建置客製化嵌入式 Linux 的工具、流程與 metadata 生態 | 本案使用 Wrynose 基準 |
| OpenEmbedded / BitBake | metadata、共用建置機制及相依任務執行器 | 解析設定、決定任務、執行建置 |
| BSP | 板級支援，包括 machine、核心、硬體描述與開機相關設定 | `meta-raspberrypi` |
| Layer | 組織相關 recipe、設定與擴充的目錄集合 | `meta-rpi5-openbmc` |
| Recipe | `.bb` 建置描述，告訴系統如何取得、編譯、安裝及封裝軟體 | `rpi5-openbmc-simulator_1.0.bb` |
| Class | recipe 可共用的任務與政策 | `meson`、`pkgconfig`、`systemd` |
| Image recipe | 決定整份系統要納入哪些功能與套件 | `rpi5-obmc-lab-image.bb` |

本專案主要檔案：

- [`upstream.lock`](../upstream.lock)：固定上游來源及版本。
- [`scripts/build.sh`](../scripts/build.sh)：環境檢查、取得上游、設定環境及呼叫 BitBake。
- [`config/local.conf`](../config/local.conf)：硬體、發行版、映像格式及快取政策。
- [`meta-rpi5-openbmc/conf/layer.conf`](../meta-rpi5-openbmc/conf/layer.conf)：讓 BitBake 辨識本 layer 及其 recipe。
- [`image recipe`](../meta-rpi5-openbmc/recipes-core/images/rpi5-obmc-lab-image.bb)：組合 OpenBMC 功能與自訂套件。
- [`溫度服務 recipe`](../meta-rpi5-openbmc/recipes-rpi5/simulator/rpi5-openbmc-simulator_1.0.bb)：把 C++ 程式與 unit 納入系統。
- [`Wi-Fi 載入服務 recipe`](../meta-rpi5-openbmc/recipes-rpi5/wifi/rpi5-brcmfmac_1.0.bb)：納入模組載入工具、模組套件與 oneshot unit。

## 4. 建置前準備：主機、資源與相依工具

### 4.1 建置位置與資源

本案實際使用 VMware 中的 Ubuntu；建置目錄放在其 Linux 檔案系統。不要在 `/mnt/hgfs` 直接建置，也不要把 WSL 的 Windows 掛載位置當成本案建置目錄。`build.sh` 對上述常見錯誤位置設有檢查。

Yocto Wrynose 官方文件以特定參考映像說明約 140 GB 可用磁碟與 32 GB RAM 的資源需求；這不是本案映像的精確保證值。下載、sstate、暫存檔及多版本建置可能需要更多空間。腳本另以低於 140 GiB 顯示警告；磁碟總容量不等於當下可用空間。

Ubuntu 上可先查：

```bash
hostname
whoami
df -h .
free -h
nproc
```

依序確認目前機器與使用者、檔案系統可用空間、記憶體及可用 CPU 數量。不應只憑先前某一次 `df` 的數字，推定今天仍有相同空間。

### 4.2 新工作樹的取得與安裝

若原本的專案已在 Ubuntu，直接進入該目錄，不要重複 clone。只有在指定目錄尚不存在、確實要取得新工作樹時，才使用：

```bash
mkdir -p ~/src
git clone --branch main https://github.com/learningyun-tech/rpi5-openbmc-portfolio.git ~/src/rpi5-openbmc-portfolio
cd ~/src/rpi5-openbmc-portfolio
chmod +x scripts/*.sh
bash scripts/install-build-deps-ubuntu.sh
```

`git clone` 取得的是本實驗專案；後續 `build.sh` 才會取得另一份上游 OpenBMC。`chmod` 補上腳本執行權限，Git 可能因此顯示檔案模式變更，這與修改程式內容不同。安裝腳本會透過 sudo 安裝主機套件與準備 locale，並非替 Pi 安裝應用程式。

一般使用者負責建置；不要用 `sudo bash scripts/build.sh build`。需要較高權限的主機套件安裝或燒錄，與 BitBake 建置是不同操作。

### 4.3 先做快速檢查

```bash
bash scripts/test-static.sh
```

此腳本檢查 Bash 語法、專案一致性、溫度解析回歸測試及空白格式；若有 shellcheck 也會執行 lint。它在建置主機上測試，不代表已交叉建置整份 OpenBMC，或已在 Pi 驗證 D-Bus、網路及 Redfish。既有溫度解析測試為 12 項，實際結果應保留當次輸出。

## 5. 上游版本鎖定：不是每次追最新 master

`upstream.lock` 的關鍵設定是：

```text
OPENBMC_REPOSITORY="https://github.com/openbmc/openbmc.git"
OPENBMC_BRANCH="wrynose"
OPENBMC_COMMIT="b48d8890dac29b8954f47a8ce17645d5f9897782"
```

`build.sh` 以 `source` 載入它；這是會被 shell 執行的設定檔，因此只應使用可信任的專案版本。腳本預設把上游放在 `work/openbmc`，檢查其 origin，必要時取得並切換至指定 commit。

需要切換 commit 而上游已有被追蹤檔案的修改時，腳本會停止以避免覆蓋。這不是對所有情況的完整乾淨檢查：即使 HEAD 相同，本地修改仍可能影響建置，所以要額外保存工作樹狀態。

取得上游後，可在 Ubuntu 專案根目錄查：

```bash
git rev-parse HEAD
git -C work/openbmc rev-parse HEAD
git -C work/openbmc status --short
```

第一行是「實驗專案版本」，第二行是「上游 OpenBMC 版本」，兩者不同。固定這兩個版本、主機資訊及有效設定有助重建；不代表已證明 bit-for-bit 可重現。

## 6. configure 真正做了什麼？

```bash
bash scripts/build.sh configure
```

這是前景操作，回到提示符號才表示該程序結束。長時間建置的背景方式見第 10 節；兩者擇一，不要同時啟動。

腳本主要依序：

1. 檢查執行者、必要工具、locale、工作位置及磁碟可用空間。
2. 用 `flock` 防止另一個 configure／build 同時使用這份專案。
3. 取得並選定上游基準，建立 `work/build-rpi5`。
4. 使用 `meta-phosphor/conf/templates/default` 初始化環境；透過 `source ./oe-init-build-env` 讓 BitBake 所需環境在該 shell 生效。
5. 把專案 `config/local.conf` 複製到建置目錄；若尚無 `conf/local-extra.conf`，建立其範例副本。
6. 加入 `meta-raspberrypi` 與 `meta-rpi5-openbmc`，並避免重複加入相同 layer 路徑。
7. 執行 `bitbake-layers show-layers` 和 `bitbake -p`，檢查 layer 與 metadata 是否可解析。

本案 wrapper **不是直接 source Raspberry Pi EVB template**；應依目前腳本的有效 Phosphor template 與明確加入的 BSP 來解釋。

重要區分：wrapper 的 `configure` 是「準備環境並解析 metadata」；recipe 的 `do_configure` 才是個別軟體的建置設定任務。二者不是同一件事。解析成功不代表已下載所有 recipe 的來源、編譯成功、產生新映像或完成開機。

## 7. local.conf、bblayers.conf 與本機覆寫

| 設定 | 本案選擇 | 影響 |
| --- | --- | --- |
| `MACHINE` | `raspberrypi5` | 選擇板級支援、核心及硬體相關設定 |
| `DISTRO` | `openbmc-phosphor` | 選擇 OpenBMC 發行政策 |
| `PACKAGE_CLASSES` | `package_ipk` | 套件輸出採用 IPK；不是產生 Ubuntu 的 deb 套件 |
| `KERNEL_IMAGETYPE` | `Image` | 本案選擇 Pi 直接韌體開機所用的未壓縮 ARM64 核心格式 |
| `IMAGE_FSTYPES` | `wic.bz2 wic.bmap` | 產生壓縮磁碟映像與區塊對照資料 |
| `ENABLE_UART` 等 | 開啟 UART／I2C／SPI 相關設定 | 不等於所有實體匯流排皆已測試 |
| `DL_DIR` | `work/downloads` | 重用原始碼下載 |
| `SSTATE_DIR` | `work/sstate-cache` | 在相容條件下重用建置任務產物 |

`bblayers.conf` 決定載入哪些 layer；`local.conf` 放建置設定，不能互相取代。image recipe 才進一步決定系統納入哪些功能與套件。

本案另以 `phosphor-no-ipmi-rmcp` 及 distro override 選擇不依賴 IPMI 密碼模組的上游 PAM 變體；不是把 PAM 或密碼驗證整體關掉。開發映像的 root 登入政策也不應直接當成產品安全設定。

wrapper 每次執行會重新複製專案 `config/local.conf`，所以直接修改 `work/build-rpi5/conf/local.conf` 可能被下一次覆寫。持久的專案政策應修改專案設定；個人實驗可放在 `work/build-rpi5/conf/local-extra.conf`，該檔建立後會保留。

RAM 不足時，可在本機 extra 設定考慮降低 `BB_NUMBER_THREADS` 與 `PARALLEL_MAKE`，但兩者分別控制任務數及部分編譯工作的平行度，不是同一個旋鈕。設定較小不保證解決每一種記憶體不足問題。需接受受限韌體授權時，應先閱讀對應授權與 BitBake 訊息，再針對必要項目設定；不要一概接受未知授權旗標。

## 8. BitBake 怎麼把原始碼變成映像？

正式 build 呼叫的目標是：

```text
bitbake rpi5-obmc-lab-image
```

這不是單獨編譯 `main.cpp`。BitBake 解析 image、recipe、class 與設定，建立相依任務圖，安排工具鏈、函式庫、核心、服務及映像所需的工作。

```text
各 recipe：do_fetch → do_unpack → do_patch → do_configure → do_compile
                                                ↓
                       do_install → do_package → 套件輸出與相關 QA
                                                ↓
image：選取所需套件 → do_rootfs → do_image / 映像格式任務 → 完成映像
```

這是概念化主線，省略 sysroot 等其他任務；真實執行是相依圖，不是所有 recipe 排成同一條直線。不同 recipe 可平行執行，已符合條件的任務也可跳過或使用 sstate。

| 任務 | 做什麼 | 常見誤解 |
| --- | --- | --- |
| `do_fetch` | 依 `SRC_URI` 取得來源 | wrapper clone 上游，不等於所有元件的來源都已抓完 |
| `do_unpack` / `do_patch` | 準備來源、套用指定補丁 | 不是直接修改正在執行的 Pi |
| `do_configure` | 設定單一軟體的建置選項 | 不是 wrapper 的 configure 模式 |
| `do_compile` | 使用該 recipe 的工具鏈編譯 | 目標程式通常要為 ARM64 建置，主機工具則另有 native 任務 |
| `do_install` | 安裝至 recipe 的 `${D}` 封裝暫存區 | 不是安裝到 Ubuntu 的 `/usr/bin` |
| `do_package` | 將暫存內容分成套件 | 一份 recipe 可能產出多個套件 |
| `do_rootfs` | 把選定套件組成目標 rootfs | 不只是把某一個執行檔複製進資料夾 |
| 映像格式任務 | 依設定產生可部署映像 | image、套件及單一程式是不同產物 |

`DEPENDS` 主要描述建置相依，供系統準備 recipe 所需工具／函式庫與 sysroot；`RDEPENDS` 描述執行時套件相依。只有 build-time dependency，不表示相應套件一定會以相同形式進入最終映像。

## 9. 自訂程式如何進入 OpenBMC？

### 9.1 C++ 溫度服務

溫度服務 recipe 的 `SRC_URI` 引用本地 `main.cpp`、`meson.build` 和 systemd unit；`DEPENDS` 包含 Boost、sdbusplus 與 systemd，並繼承 `meson pkgconfig systemd`。

分工是：Meson 描述 C++23 程式與連結需求；Yocto class 把它接進交叉建置流程；程式安裝進封裝區；unit 隨套件安裝；`SYSTEMD_AUTO_ENABLE` 設定自動啟用；image recipe 的 `OBMC_IMAGE_EXTRA_INSTALL` 再把該套件選進系統。

因此，寫好 recipe 或 `show-recipes` 查得到 recipe，仍不代表映像已安裝該套件。還要看 image 選取、建置結果、manifest，以及目標上的檔案與服務。

### 9.2 Wi-Fi 模組載入服務

Wi-Fi recipe 加入 `kmod` 與 `kernel-module-brcmfmac` 執行相依，並啟用執行 `modprobe brcmfmac` 的 oneshot unit。它使用上游 Broadcom 驅動，不是新寫一份 Wi-Fi 核心驅動。

本案曾確認 systemd 的 kmod 整合未啟用，因此另用獨立 modprobe 工具載入模組。`Before=` 只設定與 supplicant 的先後關係，不會單靠這一行啟動對方。oneshot 的 `active (exited)` 可表示一次性工作成功，並非必須有常駐程序。

模組載入、無線晶片韌體、Wi-Fi 認證、NIC 啟用、DHCP 是不同階段。本 recipe 不能替代 AP 密碼佈署；本案實測的 5 GHz 設定是在燒錄後另行建立。

## 10. 正式建置與 tmux：先判斷哪個工作完成

長時間建置可用專案的 tmux 助手，先執行：

```bash
bash scripts/tmux-build.sh configure
bash scripts/tmux-build.sh status
```

第一行只啟動背景 configure 工作；其結束碼不代表 BitBake 已完成。必要時使用 `bash scripts/tmux-build.sh attach` 觀看，或用 `log`／`follow` 查日誌。等 status 顯示這次 configure 成功、結束碼 0 且 session 已結束，再執行：

```bash
bash scripts/tmux-build.sh build
bash scripts/tmux-build.sh status
```

等這次 **build** 成功並核對日誌，才能記錄映像建置結果。不要把 configure 的成功、舊 build 的成功或背景啟動訊息當成新映像已完成；也不要只用 `configure && build` 串接兩個非同步啟動命令來等待。

`attach` 只是進入畫面；`Ctrl+B` 放開後按 `D` 可離開畫面而保持工作。tmux 不能讓 BitBake 跨 Ubuntu 關機繼續運作。日誌與狀態預設在 `work/tmux`，屬本機產物。

不需背景工作的情況，也可用前景的 `bash scripts/build.sh build`；與 tmux 方式擇一。操作細節見[tmux 建置教學](tmux-build-zh-TW.md)。

## 11. 產物、快取與版本證據

預設目錄分工如下：

| 位置 | 內容 | 是否放進 GitHub 原始碼儲存庫 |
| --- | --- | --- |
| `work/openbmc` | 上游工作樹 | 不整份再上傳，保留來源與版本鎖定即可 |
| `work/downloads` | 下載快取 | 否 |
| `work/sstate-cache` | 任務產物快取 | 否 |
| `work/build-rpi5/tmp` | 中間產物、套件、recipe 日誌 | 否 |
| `work/build-rpi5/tmp/deploy/images/raspberrypi5` | 映像與部署資料 | 原始碼倉庫不直接收整個目錄 |
| `artifacts` | 本機匯出、紀錄與備份資料 | 否；公開證據應另做節錄與去識別 |

Ubuntu 專案根目錄可列出目前產物：

```bash
find work/build-rpi5/tmp/deploy/images/raspberrypi5 -maxdepth 1 -type f \
    \( -name '*.wic.bz2' -o -name '*.wic.bmap' -o -name '*.manifest' \) -print
```

`.wic.bz2` 是經 bzip2 壓縮的磁碟映像；`.wic.bmap` 描述映像的 mapped ranges 與校驗資訊，讓工具能有效率地處理需要複製的區塊；`.manifest` 記錄映像所含套件。檔名及時間戳以當次部署目錄為準，不應把舊檔名寫死成每次重建的結果。

對選定的壓縮映像做 `bzip2 -tv` 可檢查壓縮資料完整性；`sha256sum` 可識別該檔案的位元內容。兩者都不等於 Pi 已能開機。bmap 卡片讀回驗證通過，也只涵蓋 mapped ranges，不是整張卡所有未使用空間都比對一致。

下載快取保存來源；sstate 保存可重用的任務產物；目前工作樹與 task 簽章／狀態決定還需要做什麼。增量建置很快，可能是正常重用，不一定代表什麼也沒建。不要為了更新 README 或 GitHub 就刪除 `work`、執行清除所有快取或強迫整份重建。

實際重建時應保存：實驗專案 commit、上游 commit、兩個工作樹的修改狀態、主機版本、有效設定、當次 build 退出碼、日誌及映像雜湊。只有檔名或只有 `upstream.lock`，不足以證明某個既有映像對應哪一次完整建置。

## 12. 失敗時在哪一層找證據？

要查 BitBake 有效設定，可在沒有其他 configure／build 運作時進入：

```bash
bash scripts/build.sh shell
```

這會開啟子 shell；即使 shell 模式，也會準備環境並重新複製建置設定，不是純唯讀查詢。以下查詢在該 shell 執行：

```bash
bitbake-layers show-layers
bitbake-layers show-recipes rpi5-brcmfmac
bitbake-getvar MACHINE
bitbake-getvar -r systemd PACKAGECONFIG_CONFARGS
```

查完用 `exit` 回到原本 shell。子 shell 的環境不會反向套用到父 shell。

| 現象 | 優先查什麼 |
| --- | --- |
| recipe 找不到 | layer 是否加入、名稱是否正確、相容性或 mask 訊息 |
| 來源下載失敗 | 失敗 recipe 的 fetch 日誌、網路與指定版本是否可取得 |
| 編譯失敗 | BitBake 指出的 `log.do_compile`，不是只看最後一行總結 |
| rootfs／封裝失敗 | 套件相依、安裝路徑、package QA 與對應任務日誌 |
| 套件在 manifest，但服務不正常 | Pi 的 unit、執行檔、相依與 `journalctl` |
| Wi-Fi 有連線但沒 IPv4 | NIC 啟用、networkd 設定與 DHCP，不只重輸密碼 |
| D-Bus 有值但 Redfish 查不到 | inventory association、Sensor Collection URI、權限及 bmcweb 日誌 |
| `Cannot initialize environment` | 哪支服務呼叫環境工具、平台是否支援；不要猜快閃位址寫入 |

警告與錯誤要依退出碼和具體結果判斷；不要把整份日誌有 `error` 字串就直接當作同一個根因。也不要用刪除鎖檔、刪工作樹或隨意修改 bootloader environment 作為第一個修復步驟。

## 13. 建置成功之後，還要驗證什麼？

這些是不同的驗收關卡：

| 關卡 | 證據 | 還不能推論 |
| --- | --- | --- |
| 主機測試 | 語法、metadata 一致性與溫度解析測試通過 | 整份映像已建置 |
| 解析 | `bitbake -p` 成功 | 所有來源可下載、所有程式可編譯 |
| 完整 build | 當次目標 build 退出碼 0 與產物 | Pi 開機或網路一定成功 |
| 部署 | 確認目標卡、備份、寫入與讀回結果 | 所有管理功能都正常 |
| 實機啟動 | UART、boot ID 與服務狀態 | 重開機後網路必定恢復 |
| 管理資料鏈 | sysfs、D-Bus、HTTPS／Redfish 查詢 | 量產資格、完整同步或長時間穩定 |

燒錄會覆寫目標磁碟，本文不提供預設真實裝置名稱或自動燒錄命令。重新部署時，必須先確認卡片身分、容量、掛載狀態及可還原備份；舊紀錄中的 `/dev/sdb` 不能跨重開機或插拔直接沿用。

Pi 已開機並登入後，可做以下唯讀查詢：

```bash
hostname
tty
systemctl is-active rpi5-brcmfmac.service wpa_supplicant-nl80211@wlan0.service rpi5-openbmc-simulator.service bmcweb.socket
ip -4 addr show dev wlan0
grep -H . /sys/class/thermal/thermal_zone*/type /sys/class/thermal/thermal_zone*/temp
busctl get-property xyz.openbmc_project.RPi5.Simulator \
    /xyz/openbmc_project/sensors/temperature/CPU_Temperature \
    xyz.openbmc_project.Sensor.Value Value
```

`52350` 毫攝氏度等於 `52.35` 攝氏度；D-Bus `d` 表示 double。各層查詢不是同時取樣，讀值不必每次完全相同。應核對單位、合理範圍、更新行為與錯誤處理，不能只挑一筆相同值就宣稱校正完成。

接著由 Ubuntu 而非 Pi 自己對自己發出 SSH／HTTPS 查詢。Redfish 應先列出 `/redfish/v1/Chassis/RPi5/Sensors`，再使用 `Members` 回傳的 URI；本案已驗證的單筆路徑是 `/redfish/v1/Chassis/RPi5/Sensors/temperature_CPU_Temperature`。

HTTPS 要同時驗證可信任憑證與主機名稱；`--resolve` 可把名稱指定到實驗 IP，但不能替代憑證驗證。現有 `scripts/smoke-test.sh` 仍含 `curl -k`，其 TLS 警告不是安全修復；既有憑證驗證證據來自另一組未用 `-k` 的手動查詢。測試時不要公開密碼、PSK、私鑰或 session token。

## 14. 面試常見追問與本案答法

**為什麼不直接在 Pi 用 g++ 編譯？** 單一程式的原生編譯與整套系統整合不同。本案用 Yocto 同時管理工具鏈、函式庫、套件、服務及映像政策；Ubuntu 上的解析回歸測試則是另一種快速驗證。

**我有 recipe，為什麼映像還沒有程式？** recipe 只描述如何建置；還要被目標的相依關係或 image 選進來。依序查 recipe 可見性、實際 build、套件內容、manifest 及 Pi 檔案，不只看 `.bb` 存在。

**systemd enabled 就表示服務正常嗎？** enabled 是啟用政策；active 是當下狀態；程式功能仍要另查資料與日誌。socket activation 的 socket 和被啟動服務，也不是同一個 unit。

**這次修的是 kernel driver 嗎？** 本案 Wi-Fi 修正是把已有模組及載入工具打包，透過 systemd oneshot 執行 modprobe；不是從零實作 brcmfmac。溫度服務則是讀現有 sysfs 的使用者空間程式。

**這份公開原始碼保證能重現舊映像嗎？** 有版本鎖定、設定與操作證據，但尚未從全新 clone 完成一次乾淨環境重建，不能宣稱 bit-for-bit 可重現。燒錄後的密碼、Wi-Fi 與憑證等佈署狀態，也不能當成已內建在 recipe。

**專案還缺什麼？** I2C／SPI 實體周邊通訊、2.4 GHz 問題、部分開機警告、產品更新與長期穩定性等，依驗收報告列為未完成或未驗證；不把支援開關或上游功能寫成已實測成果。

## 15. 更新文件與更新韌體是兩條流程

```text
只更新說明：修改 Markdown → 檢查差異 → 選定檔案提交 → git push
修改韌體：修改程式／設定 → 主機測試 → BitBake 建置 → 部署 → Pi 驗證 → 保存證據
```

更新本作品集文件不會改變 Pi 正在執行的映像，也不會使既有測試紀錄自動變成新版本的實測結果。日後沿用 `learningyun-tech/rpi5-openbmc-portfolio` 與 `main` 正常提交即可；不需刪除儲存庫、重建 `.git`、清除快取或 force push。

## 16. 參考資料與閱讀順序

以下外部文件可能隨上游更新；本案行為應先對照鎖定版本及有效設定，而非直接套用最新範例。

- [本專案建置腳本](../scripts/build.sh)
- [本專案建置設定](../config/local.conf)
- [Yocto Wrynose：系統需求](https://docs.yoctoproject.org/wrynose/ref-manual/system-requirements.html)
- [Yocto Wrynose：建置概念、layer 與快取](https://docs.yoctoproject.org/wrynose/overview-manual/concepts.html)
- [Yocto Wrynose：任務參考](https://docs.yoctoproject.org/wrynose/ref-manual/tasks.html)
- [OpenBMC 官方專案（本案上游 commit）](https://github.com/openbmc/openbmc/tree/b48d8890dac29b8954f47a8ce17645d5f9897782)
- [繁體中文操作教學](tutorial-zh-TW.md)、[tmux 操作](tmux-build-zh-TW.md)、[架構說明](architecture.md)
- [實機驗收與已知限制](interview-closeout-20261014-zh-TW.md)
