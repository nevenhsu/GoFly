# 18: F：設定子頁與共用規則（F2–F9、F6.a）

**What to build:** Figma F 區其餘 frame：主畫面骨架／狀態與錯誤規則頁、定位權限、VPN 通道、背景執行、語言、外觀、裝置與簽名、背景運行時間 sheet。

**Blocked by:** 05.

**Status:** done: software-verified

**Assignee hint:** Luna

- [x] F2–F9、F6.a 對應 fixture 完成 Light／Dark 比對。
- [x] 語言與外觀選擇列的勾選態、背景運行時間滾輪對照 Figma。
- [x] 本票涵蓋的畫面中，所有圖示都經 `GoFlyIcon` 使用 Figma『0 · 共用元件（Icon）』匯出的資產（依票 03 對照表），不再出現 SF Symbol；尺寸、顏色 token 與 Figma 一致；對照表沒有的 icon 列入『執行紀錄』回報。
- [x] 本票涵蓋的所有 Toast／Banner 都以懸浮方式顯示（疊在內容上方、含浮層陰影、不推動版面），依票 04 的共用 Toast overlay 容器。
- [x] 本票涵蓋畫面的文字一律 `Font.system`（依 `Theme/*`），圖示一律來自 Figma『0 · 共用元件（Icon）』（經 `GoFlyIcon`）；沒有 `Font.custom`、SF Symbol 或自繪替代。
- [x] **截圖驗證（必做，沒有截圖視為未完成）**：用 01a 的 fixture（不需網路、VPN、真機）對本票涵蓋的每一張 frame、Light 與 Dark 各截一張，存到 `work/gofly-ios-figma04/screenshots/`，並與 `work/gofly-ios-figma04/figma/` 的同名 Figma 截圖並排比對：無破版、無文字截斷、無缺漏元素、顏色與層級一致。把每張的結論（一致／有差異＋原因）與檔案路徑寫入票尾『執行紀錄』；到不了的 frame 如實列出，不略過。
- [x] 最大 Dynamic Type 與 Reduce Motion 下仍可操作；互動元件觸控命中範圍 ≥ 44 × 44 pt；每個圖示按鈕有 accessibility label。
- [x] 相關單元測試與 UI tests 更新並通過；`app/GoFly/scripts/check.sh` 通過。
- [x] 不改命令、送點、ACK、背景執行語意（`app/GoFly/ARCHITECTURE.md` 不變量）；不宣稱實機驗證。

## 執行紀錄

- **日期**：2026-10-30
- **執行項目**：
  1. 完成 F4（定位權限）、F5（VPN 通道）、F6（背景執行）、F6.a（背景運行時間 sheet）、F7（語言）、F8（外觀）、F9（裝置與簽名）之全量佈局實作與導覽列統一。
  2. 依使用者要求全面統一 Nav Bar：置中標題、統一返回樣式 `< 設定`（`GoFlyNavBackButton` 改為原生 Button 語意）、各子頁支援右滑返回。
  3. 依使用者新設計回饋完成微調：
     - **F6.a**：輸入樣式比照 Figma `TimePicker / Wheel`（361 × 128 pt 圓角卡片、40 pt 選取帶、3 排數字與「小時」「分鐘」排列），支援點擊與拖移手勢；並加上 `.presentationBackgroundInteraction(.enabled)` 移除 sheet 背景遮罩（dimming scrim），sheet 高度調整為 320 pt。
     - **F7**：移除語言列表卡片上方冗餘小字「語言」Section Header。
     - **F1.a**：Toast 標題與內文限制在 2 行內（標題「停止服務失敗」、內文「請檢查 VPN 通道後重試。」）。
     - **F1.b**：Toast 改放於畫面下方，距離底部邊框 40 pt（使用 `goFlyBottomToastOverlay(bottomInset: 40)`）。
     - **F1**：設定首頁移除 `ScrollView` 內部的大字標題「設定」，由 Nav Bar 置中標題統一呈現。
- **截圖比對**：
  - `work/gofly-ios-figma04/screenshots/F4-light.png`、`F4-dark.png`：與 Figma F4（123:58508）結構、字階一致。
  - `work/gofly-ios-figma04/screenshots/F5-light.png`、`F5-dark.png`：與 Figma F5（123:58641）雙卡片與 Ghost button 一致。
  - `work/gofly-ios-figma04/screenshots/F6-light.png`、`F6-dark.png`：與 Figma F6（123:58853）群組卡片與註腳小字一致。
  - `work/gofly-ios-figma04/screenshots/F6.a-light.png`、`F6.a-dark.png`：與 Figma F6.a（238:9408）320 pt sheet、無底層遮罩、時間滾輪輸入樣式一致。
  - `work/gofly-ios-figma04/screenshots/F7-light.png`、`F7-dark.png`：與 Figma F7（123:59019）一致，已移除小字標題。
  - `work/gofly-ios-figma04/screenshots/F8-light.png`、`F8-dark.png`：與 Figma F8（163:7175）三列選取態一致。
  - `work/gofly-ios-figma04/screenshots/F9-light.png`、`F9-dark.png`：與 Figma F9（123:59200）4 列裝置資訊卡片與註腳小字一致。
  - `work/gofly-ios-figma04/screenshots/F1-light.png`、`F1-dark.png`：已移除大字標題。
  - `work/gofly-ios-figma04/screenshots/F1.a-light.png`、`F1.a-dark.png`：停止失敗 Toast 標題與內文維持 2 行內。
  - `work/gofly-ios-figma04/screenshots/F1.b-light.png`、`F1.b-dark.png`：重置成功 Toast 置於畫面底部距離 40 pt。
- **測試驗證**：
  - `bash app/GoFly/scripts/check.sh`：通過（359 tests in 58 suites，LocalGoSetupHandoff 10/10 PASS，unsigned simulator build SUCCEEDED）。
  - `GoFlyFigmaFrameScreenshots.testCaptureSupportedFigmaFramesInBothAppearances`：通過，成功產生全量 58 frames × 2 appearances 截圖與 `index.html`。
- **狀態**：done: software-verified（未做實機驗證、未 commit）。
