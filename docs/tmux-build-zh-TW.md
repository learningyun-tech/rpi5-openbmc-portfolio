# 使用 tmux 執行 OpenBMC 長時間建置

OpenBMC 第一次建置可能需要數小時。`tmux` 讓工作在獨立的終端 session 中持續
執行；關閉目前的 Terminal 或 SSH 斷線，不會終止建置。關閉、暫停或重新啟動
整台 Ubuntu VM 仍會中斷工作。

本專案的 `scripts/tmux-build.sh` 已封裝常用操作，不需要記住 tmux 指令。

## 1. 確認靜態測試

```bash
cd ~/src/rpi5-openbmc-portfolio
chmod +x scripts/*.sh
./scripts/test-static.sh
```

必須看到 `Project validation passed.` 和 `靜態檢查全部通過。`。

## 2. 在背景執行 configure

```bash
./scripts/tmux-build.sh configure
```

這條命令立即返回提示字元，但 configure 已在背景執行。進入即時畫面：

```bash
./scripts/tmux-build.sh attach
```

要離開畫面但保持工作執行：

1. 按 `Ctrl+B`。
2. 放開兩個按鍵。
3. 按 `D`。

不要按 `Ctrl+C`，因為那會中止畫面內的建置程式。

## 3. 不進入 tmux 也能查看進度

```bash
./scripts/tmux-build.sh status
./scripts/tmux-build.sh log
```

- `status` 顯示 session 是否仍存在，以及最近工作的結果與結束碼。
- `log` 顯示最近 100 行。
- `follow` 持續顯示新日誌；在 `follow` 畫面按 `Ctrl+C` 只會停止查看，不會中止
  背景工作。

```bash
./scripts/tmux-build.sh follow
```

成功的 configure 狀態包含：

```text
狀態：成功
工作：configure
結束碼：0
```

## 4. 在背景正式建置映像

configure 成功後：

```bash
./scripts/tmux-build.sh build
```

可以立刻進入畫面，也可以只看 log：

```bash
./scripts/tmux-build.sh attach
```

或：

```bash
./scripts/tmux-build.sh follow
```

安全離開後，可關閉 Ubuntu Terminal；只要 VM 繼續運行，建置便會持續。

## 5. 如何判定完成

```bash
./scripts/tmux-build.sh status
```

成功應顯示：

```text
目前沒有執行中的 tmux 建置 session。

狀態：成功
工作：build
結束碼：0
```

建置失敗會顯示 `狀態：失敗` 與非零結束碼。查看錯誤附近的輸出：

```bash
./scripts/tmux-build.sh log
```

修正原因後，重新執行 `./scripts/tmux-build.sh build`；BitBake 通常會沿用已完成
的產物。

## 6. 防止重複建置

若同名 session 正在運行，助手會拒絕再啟動一份 configure 或 build。這可避免
兩個 BitBake 程序同時寫入相同的 `work/build-rpi5`。

若 `status` 顯示「執行中」，但同時顯示沒有 tmux session，通常代表 VM 曾突然
關機或程序被外部終止。先用 `log` 看最後輸出，再重新執行相同工作。

## 7. 日誌位置

日誌與狀態儲存在：

```text
work/tmux/status.txt
work/tmux/logs/
```

`work/` 已由 `.gitignore` 排除，不會把大型或暫時性 log 加入版本控制。
