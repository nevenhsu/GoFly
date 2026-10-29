# 18: F：設定子頁與共用規則（F2–F9、F6.a）

**What to build:** Figma F 區其餘 frame：主畫面骨架／狀態與錯誤規則頁、定位權限、VPN 通道、背景執行、語言、外觀、裝置與簽名、背景運行時間 sheet（遮罩黑色）。

**Blocked by:** 05.

**Status:** ready-for-agent

**Assignee hint:** Luna

- [ ] F2–F9、F6.a 對應 fixture 完成 Light／Dark 比對。
- [ ] 語言與外觀選擇列的勾選態、背景運行時間滾輪對照 Figma。
- [ ] 本票涵蓋的畫面中，所有圖示都經 `GoFlyIcon` 使用 Figma『0 · 共用元件（Icon）』匯出的資產（依票 03 對照表），不再出現 SF Symbol；尺寸、顏色 token 與 Figma 一致；對照表沒有的 icon 列入『執行紀錄』回報。
- [ ] 本票涵蓋的所有 Toast／Banner 都以懸浮方式顯示（疊在內容上方、含浮層陰影、不推動版面），依票 04 的共用 Toast overlay 容器。
- [ ] 本票涵蓋畫面的文字一律 `Font.system`（依 `Theme/*`），圖示一律來自 Figma『0 · 共用元件（Icon）』（經 `GoFlyIcon`）；沒有 `Font.custom`、SF Symbol 或自繪替代。
- [ ] **截圖驗證（必做，沒有截圖視為未完成）**：用 01a 的 fixture（不需網路、VPN、真機）對本票涵蓋的每一張 frame、Light 與 Dark 各截一張，存到 `work/gofly-ios-figma04/screenshots/`，並與 `work/gofly-ios-figma04/figma/` 的同名 Figma 截圖並排比對：無破版、無文字截斷、無缺漏元素、顏色與層級一致。把每張的結論（一致／有差異＋原因）與檔案路徑寫入票尾『執行紀錄』；到不了的 frame 如實列出，不略過。
- [ ] 最大 Dynamic Type 與 Reduce Motion 下仍可操作；互動元件觸控命中範圍 ≥ 44 × 44 pt；每個圖示按鈕有 accessibility label。
- [ ] 相關單元測試與 UI tests 更新並通過；`app/GoFly/scripts/check.sh` 通過。
- [ ] 不改命令、送點、ACK、背景執行語意（`app/GoFly/ARCHITECTURE.md` 不變量）；不宣稱實機驗證。

## 執行紀錄

（執行者在此記錄：日期、完成項、截圖路徑、未完成與原因、決策。）

### 使用者追加比對項（2026-10-29，待實作）

- F5 與 F6 依 Figma 04 渲染大幅更新，並修正返回按鈕樣式。
- F6.a 的 time input／時間選擇器依 Figma 04 渲染全面更新。
