# 02 · 手動搖桿自動定位與共用 Go 瞬移

**Status:** implemented; software-verified

**Blocked by:** 01.

**Scope:** 沿用 ServiceController 的瞬移/FIFO/dispatch gate 與 ACK 提交，進入搖桿時重用有效模擬位置，否則以新鮮 GPS 建立起點；手動地圖選點使用 CandidatePin 與地點卡的 Go，兩者使用同一瞬移命令，成功留在搖桿。

**Acceptance:** warmup、歷史座標或 GPS observation 本身不被當成模擬 ACK；只有核對 ACK 更新模擬位置。沒有有效起點時不啟動假模擬；使用者可選點。Pin/card Go 共用 teleport，錯誤保留候選，成功後仍在搖桿；不新增第二 writer。

**Evidence / changes:** E1 Light/Dark 渲染於本票開始前讀取。新增進入搖桿時的有效位置檢查與 GPS→既有 teleport ACK 起點流程；新增手動搖桿地圖選點及 Go 卡片；保留 `ServiceController` 作唯一瞬移/送點 owner。E1 控制改成明確「自動漫步」主按鈕及執行中「停止漫步／更換地點」。更新三語 button 文案與 UI 測試期待值。`bash app/GoFly/scripts/check.sh` 通過：270 Core 測試、native boundary 13 個 scenario、iOS Simulator build；`git diff --check` 通過。未安裝或操作實機。

**Not verified:** iOS UI automation、裝置定位與 native ACK；軟體檢查不代替實機驗收。
