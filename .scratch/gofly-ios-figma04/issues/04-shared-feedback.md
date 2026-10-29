# 04: 狀態回饋共用元件

**What to build:** Toast（danger／warning／success）、Snackbar（2 秒自動消失／可復原）、StatusPill（啟動／模擬中／暫停／連線中斷）、StatusBanner、Progress、Slider（`Value` 0–100 比例軌道）與 Overlay／Dim（黑色 40%，Light 與 Dark 同一色）對齊 Figma 共用元件。

**Blocked by:** 01, 02.

**Status:** in progress

**Assignee hint:** Luna

- [ ] Toast 三個 tone 與 Figma Light／Dark 一致：圓角 14、內距 12／14、間距 10；標題 15 pt Semibold、說明 13 pt Regular、22 pt outline 狀態圖示、動作為膠囊按鈕；✕ 視覺 20 pt，命中範圍 44 × 44 pt，高度隨內容。
- [ ] **Toast 一律懸浮**：所有 Toast／Banner（danger、warning、success，含設定頁的 Wi‑Fi 與服務錯誤、首次引導的錯誤、瞬移／路線／搖桿的錯誤與中斷、重置成功）都以 overlay 疊在畫面最上層，位於導覽列或搜尋列下方、距左右 16 pt，不得放進頁面內容的版面流程（不推動標題、卡片或清單位置）；使用浮層陰影（Figma Toast 元件：黑色 18%、y 4、blur 16），多個同時出現時依序堆疊並可個別關閉；Snackbar 維持底部懸浮。實作用共用 Toast 元件與單一 overlay 容器，不得各頁自己 inline 放置。R04 VPN 檢查成功不顯示 success Toast，改為自動進入 B1。
- [ ] Snackbar 與 StatusPill 對照 Figma；Dark 色不使用純白。
- [ ] Overlay／Dim 在 Dark 為黑色遮罩（不得是淺色遮罩）；Sheet、ActionSheet、系統分享 sheet 後方畫面皆被壓暗。
- [ ] Progress 與 Slider 可在展示頁互動，Slider 縮放寬度時進度比例不變。
- [ ] **截圖驗證（必做，沒有截圖視為未完成）**：用 01a 的 fixture（不需網路、VPN、真機）對本票涵蓋的每一張 frame、Light 與 Dark 各截一張，存到 `work/gofly-ios-figma04/screenshots/`，並與 `work/gofly-ios-figma04/figma/` 的同名 Figma 截圖並排比對：無破版、無文字截斷、無缺漏元素、顏色與層級一致。把每張的結論（一致／有差異＋原因）與檔案路徑寫入票尾『執行紀錄』；到不了的 frame 如實列出，不略過。
- [ ] 最大 Dynamic Type 與 Reduce Motion 下仍可操作；互動元件觸控命中範圍 ≥ 44 × 44 pt；每個圖示按鈕有 accessibility label。
- [ ] 相關單元測試與 UI tests 更新並通過；`app/GoFly/scripts/check.sh` 通過。
- [ ] 不改命令、送點、ACK、背景執行語意（`app/GoFly/ARCHITECTURE.md` 不變量）；不宣稱實機驗證。

## 執行紀錄

### 2026-10-29 執行紀錄（Luna）

- 共用 `GoFlyStatusBanner`／overlay 已調整 outline 狀態 icon、Figma Toast 陰影與尺寸、44 pt 關閉命中區及多筆浮層；R04 VPN 成功不顯示 success Toast，改為確認後自動進 B1 收合 sheet。Snackbar 繼續使用底部浮層。重置成功 Toast 元件仍可供 F1.b 使用。
- 抽查截圖路徑：`work/gofly-ios-figma04/screenshots/{R04.a,B7,B10,D8,F1.b}-light.png` 與各自 `-dark.png`；總覽 `work/gofly-ios-figma04/screenshots/index.html`。R04.a／B7／D8 顯示錯誤浮層，B10 顯示 Wi-Fi 提示，F1.b 顯示重置成功提示；未完成共用元件板所有 variant 的逐一截圖比對，且 01a 尚有 45 個 frame 不可達，故本票維持 `in progress`。
- Figma success Toast 元件 outline 色實綁 `icon/success`（Dark `#6FC48B`），與 `line/status/success` token（Dark `#52A072`）不同；App 依渲染採 icon token，保留此 Figma token 綁定差異記錄。未修改 Figma；未做實機驗證。
- 使用者追加 Toast 比對項（2026-10-29，待實作／重截）：B7 title 與說明各最多兩行、action button 靠右；B10 action button 背景依 Figma；F1.b Toast 上移。各頁細項另記於票 07、16。R04-connected 成功後不顯示 success Toast，依票 06 執行。
