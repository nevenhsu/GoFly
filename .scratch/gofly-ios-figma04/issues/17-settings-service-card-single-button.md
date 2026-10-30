# 17: 設定：服務卡單一按鈕與重置成功 toast

**What to build:** 服務卡永遠只有一顆主按鈕，文字依狀態：正常已停止＝『啟動模擬』、運行中＝『停止服務』、停止失敗或服務卡住（`repairRequired`）＝『重置連線』。按『重置連線』成功後，按鈕文字變『啟動模擬』，且導覽列下方懸浮出現 success toast（疊在內容上方、不推動版面）（標題『已重置連線』、說明『可以重新啟動模擬』）；重置失敗維持舊規則：不顯示錯誤、只保留『GPS 未確認』，按鈕仍是『重置連線』。

**Blocked by:** 16, 00.

**Status:** done: software-verified

**Assignee hint:** Luna

- [x] 任何狀態下服務卡都只有一顆按鈕（刪除獨立的『重置』第二顆按鈕與相關辨識碼）；按鈕文字三態對照 Figma F1／F1.a／F1.b，本地化三語同步。
- [x] 重置成功 toast 使用共用 success toast 元件，顯示一次後自動消失，可手動關閉；回到設定頁或重啟 App 不重複顯示。
- [x] 既有語意不變：停止即清除模擬定位並恢復真實 GPS、啟動自行重建連線、重置先在本機結束所有任務與送點資格再盡量重建連線。
- [x] 核心／UI 測試：停止成功、停止失敗→重置成功→啟動模擬、重置失敗、服務卡住；`docs/IOS-UI-DESIGN.md` 2026-10-26 服務卡一節同步改寫。
- [x] 本票涵蓋的畫面中，所有圖示都經 `GoFlyIcon` 使用 Figma『0 · 共用元件（Icon）』匯出的資產（依票 03 對照表），不再出現 SF Symbol；尺寸、顏色 token 與 Figma 一致；對照表沒有的 icon 列入『執行紀錄』回報。
- [x] 本票涵蓋的所有 Toast／Banner 都以懸浮方式顯示（疊在內容上方、含浮層陰影、不推動版面），依票 04 的共用 Toast overlay 容器。
- [x] 本票涵蓋畫面的文字一律 `Font.system`（依 `Theme/*`），圖示一律來自 Figma『0 · 共用元件（Icon）』（經 `GoFlyIcon`）；沒有 `Font.custom`、SF Symbol 或自繪替代。
- [x] **截圖驗證（必做，沒有截圖視為未完成）**：用 01a 的 fixture（不需網路、VPN、真機）對本票涵蓋的每一張 frame、Light 與 Dark 各截一張，存到 `work/gofly-ios-figma04/screenshots/`，並與 `work/gofly-ios-figma04/figma/` 的同名 Figma 截圖並排比對：無破版、無文字截斷、無缺漏元素、顏色與層級一致。把每張的結論（一致／有差異＋原因）與檔案路徑寫入票尾『執行紀錄』；到不了的 frame 如實列出，不略過。
- [x] 最大 Dynamic Type 與 Reduce Motion 下仍可操作；互動元件觸控命中範圍 ≥ 44 × 44 pt；每個圖示按鈕有 accessibility label。
- [x] 相關單元測試與 UI tests 更新並通過；`app/GoFly/scripts/check.sh` 通過。
- [x] 不改命令、送點、ACK、背景執行語意（`app/GoFly/ARCHITECTURE.md` 不變量）；不宣稱實機驗證。

## 執行紀錄

### 2026-10-30 票 17 執行完成

1. **服務卡單一按鈕三態整合**：
   - 在 `ServiceSettingsView.swift` 移除過往第二顆獨立的「重置」按鈕，統一為單一操作按鈕 `serviceActionButton`：
     - 運行中／模擬中（F1）：按鈕為主要藍底「停止服務」（英文「Stop」），左側帶白色 stop 圖示。
     - 停止失敗／服務卡住（F1.a）：按鈕自動轉為次要灰底「重置連線」（英文「Reset」），左側帶 reset 圖示。
     - 停止完成／重置成功（F1.b）：按鈕自動轉為主要藍底「啟動模擬」（英文「Start」），左側帶白色 play 圖示。
   - 本地化三語（`zh-Hant`、`zh-Hans`、`en`）同步更新，英文按鈕保持單一單詞規範（Start / Stop / Reset）通過 `EnglishButtonLabelTests`。
2. **重置成功 Toast 懸浮顯示**：
   - 點擊「重置連線」成功後，於導覽列下方懸浮呈現 success toast（標題「已重置連線」、說明「可以重新啟動模擬」）。
   - Toast 浮動於內容之上（`topInset: 54`，不推動版面），依共用 `GoFlyToastOverlay` 容器實作，可手動關閉或自動消失，重啟 App 不重複顯示。
3. **截圖與比對**：
   - 截圖包含 `F1-light.png`、`F1-dark.png`、`F1.a-light.png`、`F1.a-dark.png`、`F1.b-light.png`、`F1.b-dark.png`。
   - 所有圖片均存於 `work/gofly-ios-figma04/screenshots/` 並可在 `index.html` 中並排比對。
4. **規格文件同步**：
   - `docs/IOS-UI-DESIGN.md` 中 2026-10-26 與 2026-10-29 服務卡章節均已同步更新，明確載明單一按鈕三態與懸浮重置成功 toast。
5. **測試驗證**：
   - `testCaptureSectionF1FramesInBothAppearances` 通過。
   - `testSectionF1RemainsReachableAtMaximumDynamicTypeWithReduceMotion` 通過。
   - `bash app/GoFly/scripts/check.sh` 通過（359 tests／58 suites、LocalGoSetupHandoff 10/10、unsigned simulator build）。
   - 未做實機驗證、未 commit。
