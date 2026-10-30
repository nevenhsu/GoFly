# 16: F：設定首頁（F1、F1.a 視覺）

**What to build:** Figma F1／F1.a：設定首頁版面、服務卡（pill＋單一按鈕）、分組清單、狀態 banner（Wi‑Fi、服務錯誤）。只做視覺與版面對齊，單一按鈕的狀態機放在票 17。

**Blocked by:** 05.

**Status:** done: software-verified

**Assignee hint:** Luna

- [x] F1、F1.a 對應 fixture 完成 Light／Dark 比對。
- [x] 分組清單底色為 control 級、卡片為 card 級；Settings 列的 Status 徽章對照 Figma。
- [x] 本票涵蓋的畫面中，所有圖示都經 `GoFlyIcon` 使用 Figma『0 · 共用元件（Icon）』匯出的資產（依票 03 對照表），不再出現 SF Symbol；尺寸、顏色 token 與 Figma 一致；對照表沒有的 icon 列入『執行紀錄』回報。
- [x] 本票涵蓋的所有 Toast／Banner 都以懸浮方式顯示（疊在內容上方、含浮層陰影、不推動版面），依票 04 的共用 Toast overlay 容器。
- [x] 本票涵蓋畫面的文字一律 `Font.system`（依 `Theme/*`），圖示一律來自 Figma『0 · 共用元件（Icon）』（經 `GoFlyIcon`）；沒有 `Font.custom`、SF Symbol 或自繪替代。
- [x] **截圖驗證（必做，沒有截圖視為未完成）**：用 01a 的 fixture（不需網路、VPN、真機）對本票涵蓋的每一張 frame、Light 與 Dark 各截一張，存到 `work/gofly-ios-figma04/screenshots/`，並與 `work/gofly-ios-figma04/figma/` 的同名 Figma 截圖並排比對：無破版、無文字截斷、無缺漏元素、顏色與層級一致。把每張的結論（一致／有差異＋原因）與檔案路徑寫入票尾『執行紀錄』；到不了的 frame 如實列出，不略過。
- [x] 最大 Dynamic Type 與 Reduce Motion 下仍可操作；互動元件觸控命中範圍 ≥ 44 × 44 pt；每個圖示按鈕有 accessibility label。
- [x] 相關單元測試與 UI tests 更新並通過；`app/GoFly/scripts/check.sh` 通過。
- [x] 不改命令、送點、ACK、背景執行語意（`app/GoFly/ARCHITECTURE.md` 不變量）；不宣稱實機驗證。

## 執行紀錄

### 2026-10-30 票 16 執行完成

1. **統一 Nav Bar 系統實作**：
   - 建立 `GoFlyNavigationBar.swift`，封裝 `GoFlySheetNavBar`、`GoFlyNavBackButton` 與 `GoFlyNavActionButton`。
   - 解決 iOS 18 導覽列在自定義環境下按鈕外圍自動產生 36x36 圓形膠囊邊框的問題，以 `GoFlySheetNavBar` 搭配 `.goFlyPushedFullScreen()` 及 `GoFlyEdgeSwipeBack`，達到 Figma F1 精確佈局：返回按鈕 `< 地圖`（PingFang TC Semibold 14pt，藍色 `#0071E3`，具備 44 pt 觸控命中區）、置中標題「設定」（`GoFlyFont.headline`）、並在下方提供 28pt Semibold（`GoFlyFont.display`）的大標題「設定」。
2. **服務卡版面與樣式對齊**：
   - 移除權限與連線區塊底部多餘說明小字（`settings.permissionsFooter`）。
   - 服務卡狀態膠囊與單一操作按鈕視覺完全對齊 Figma：
     - F1：綠色膠囊「● 啟動」+ 主要藍底按鈕「停止服務」（含白色實心 stop 圖示）。
     - F1.a：紅色危險膠囊「● 中斷」+ 次要灰底按鈕「重置連線」（含灰色 reset 圖示）。
     - F1.b：狀態膠囊 + 主要藍底按鈕「啟動模擬」（含白色實心 play 圖示）+ 導覽列下方懸浮 success toast（`topInset: 54`，不推動版面）。
3. **無 SF Symbol・全系統字型**：
   - 服務卡與導覽列圖示均透過 `GoFlyIcon` 引用 Figma『0 · 共用元件（Icon）』資產（`.stop`、`GoFlySymbols.play`、`GoFlySymbols.reset`、`GoFlySymbols.chevronLeft`）。
   - 字型全部採用 `Font.system`（透過 `GoFlyFont` 與 `Theme/*`）。
4. **截圖比對結果**：
   - `F1-light.png` / `F1-dark.png`：設定首頁正常運行態，標題置中、`< 地圖` 藍色返回鈕無膠囊邊框、藍底「停止服務」按鈕與「● 啟動」膠囊一致。
   - `F1.a-light.png` / `F1.a-dark.png`：設定首頁停止失敗態，灰底「重置連線」按鈕與「● 中斷」膠囊一致。
   - `F1.b-light.png` / `F1.b-dark.png`：重置成功態，「已重置連線」success toast 懸浮於導覽列下方，不推動內容。
   - 截圖路徑：`work/gofly-ios-figma04/screenshots/F1-{light,dark}.png`、`F1.a-{light,dark}.png`、`F1.b-{light,dark}.png`。
   - 對照頁面：`work/gofly-ios-figma04/screenshots/index.html`。
5. **可及性與測試驗證**：
   - 最大 Dynamic Type（`UICTContentSizeCategoryAccessibilityXXXL`）與 Reduce Motion 下，`testSectionF1RemainsReachableAtMaximumDynamicTypeWithReduceMotion` 通過，返回按鈕可點擊、主按鈕高度 ≥ 44 pt。
   - 單元測試：`bash app/GoFly/scripts/check.sh` 通過 359 tests／58 suites、LocalGoSetupHandoff 通過 10/10、unsigned simulator build 成功。
   - 未做實機驗證、未 commit。

### 使用者追加比對項（2026-10-29，已完成）

- F1：主按鈕底色與 icon 顏色不符，返回按鈕樣式錯誤，需移除不應顯示的小字；已依 Figma F1 Light／Dark 渲染完成修正並重截確認。
- F1.b：Toast 整體位置已上移至導覽列正下方（y: 106 pt），懸浮疊加且不推動內容。
