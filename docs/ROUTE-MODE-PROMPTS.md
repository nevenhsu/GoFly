# Route Mode 實作與審查 prompts（2026-10-24）

兩段 prompt：A 給 Sonnet 5.5 依序實作並回報；B 給 Opus 5.5 核對成果。B 可在每個任務完成後執行，也可在全部完成後執行一次。

開始前請確認工作樹乾淨：目前 `slim/plan-v1` 有大量未提交變更（含 `GoFlyMapView.swift`、`GoFlyRoutePanel.swift` 相關檔案）。先提交或另開分支保存，否則 A 會在第 0 步停下回報。

---

## A · 實作（Sonnet 5.5）

```text
你在 /Users/neven/Documents/projects/ianygo 實作 GoFly iOS 的 Route Mode 改版。請依序完成任務，每完成一項就回報一次，再繼續下一項。

## 必讀（開始前讀完）
1. AGENTS.md（UI 準據、Figma 規則、實機安裝規則）。
2. docs/ROUTE-MODE-TASKS.md：唯一任務清單，含現況證據、Figma 規格、做法與驗收條件。
3. docs/IOS-UI-DESIGN.md：「2026-10-24 共用元件規格」、「地圖右下角控制」、D1／D5／D7／D9／D22 相關條目。
4. app/GoFly/README.md（建置與測試方式）。

## 視覺準據
- Figma 檔 RtPV8PXCQJ2WXK3jk3kPrq，頁面「04 · iOS Redesign（Google Maps 參考）」(121:50359)。用 figma-console 工具讀取：每個任務開始前，對該任務相關 frame 呼叫 figma_capture_screenshot，並用 figma_execute 讀尺寸、顏色、字級。
- 共用元件在同頁 section「0 · 共用元件（正式版 token）」(121:50484)，深色版在「Dark · 0 · 共用元件」(121:53698)。
- D frame ID：D1 121:52566、D2 222:11484、D3 193:8857、D4 193:8693、D5 121:52709、D6 121:52798、D6.a 222:16433、D7 158:6131、D8 222:10536、D9 222:10849、D10 193:9158、D22 222:11999；深色版名稱前綴「Dark · 」。
- 渲染畫面優先於 frame 旁的說明文字。docs/ROUTE-MODE-TASKS.md「已確認決定」與「待決與 Figma 衝突」中的決定優先於 Figma（例如：地圖右下角只有回到定位一顆按鈕，Figma 的 Follow 按鈕不實作；D1b 已廢止）。
- 只讀 Figma，不修改 Figma、不加 prototype。

## 執行順序
0. 執行 git status。若工作樹不乾淨，停止並回報，不要自行 stash、reset 或提交別人的變更。乾淨時從目前分支開新分支 route-mode-redesign。
1. C1 Toast 合併
2. C2 Snackbar（含可復原 5 秒版）
3. C4 SearchField／Slider／Progress
4. C6 TabBar
5. C7 地圖右下角只留回到定位
6. R1 共用速度偏好
7. R2 起訖空值與清單列
8. R3 選中欄位模型＋R6.1 移除 D1b
9. R5 D1／D2 面板版面
10. R4 D9 清除復原
11. R6 D6／D6.a 執行面板與結束確認
12. R7 D10 中斷恢復
13. C3、C5、R8 回歸

## 每個任務的做法
- 先讀相關程式碼，沿用既有元件、命名、註解密度與 GoFlyStyle token；不另建平行元件。
- 新增或修改的 UI 文案同步更新 app/GoFly/Resources 的 zh-Hant、zh-Hans、en 三份 Localizable.strings。
- 補單元測試（app/GoFly/Tests/GoFlyCoreTests）或 UI test（app/GoFly/UITests），覆蓋該任務的驗收條件。
- 驗證：
  - bash app/GoFly/scripts/check.sh（核心測試＋unsigned simulator build）必須通過。
  - 跑該任務相關的 UI test（xcodebuild test，scheme GoFly，iOS Simulator）。
  - 在 iOS Simulator 以淺色與深色各截一張對應畫面，與 Figma 截圖並排比對；截圖放 work/gofly-ios/route-mode/<任務編號>/。
- 行為或規格有變時，在同一任務更新 docs/IOS-UI-DESIGN.md 與 docs/ROUTE-MODE-TASKS.md（任務狀態改為「已實作，待審查」，不寫「已完成」或「已實機驗證」）。
- 每個任務一個 commit，只 git add 該任務的檔案。訊息格式：feat(ios): <任務編號> <摘要>，結尾附 Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>。不 push、不開 PR。

## 禁止事項
- 不執行 Prettier。
- 不安裝到實機、不執行 scripts/install-ios-test.sh 的 --action apply（需使用者另行授權）。
- 不改動與任務無關的檔案；不刪除或改寫既有測試來讓測試通過。
- 遇到規格不明、Figma 與文件衝突且文件沒有決定、或測試因既有問題失敗時，停下回報，不要猜。

## 每個任務完成後的回報格式
### <任務編號> <名稱> — 已實作，待審查 | 阻塞
- 變更檔案：路徑清單
- 做法摘要：2–4 行
- 驗收條件逐條：✅／❌＋證據（測試名稱、截圖路徑）
- 測試：執行的指令與結果（通過數／失敗數；失敗附輸出）
- 與 Figma 的差異：列出並說明原因（無則寫「無」）
- 文件更新：哪些段落
- commit：hash
- 待決問題：無則寫「無」

全部完成後給總表：每個任務的狀態、commit、未解問題。
```

---

## B · 審查（Opus 5.5）

```text
你在 /Users/neven/Documents/projects/ianygo 審查 Sonnet 實作的 GoFly iOS Route Mode 改版，分支 route-mode-redesign。只審查、不修改程式碼。

## 依據
1. AGENTS.md。
2. docs/ROUTE-MODE-TASKS.md（任務、現況證據、驗收條件、已確認決定、Figma 衝突）。
3. docs/IOS-UI-DESIGN.md「2026-10-24 共用元件規格」「地圖右下角控制」與 D 區條目。
4. Figma RtPV8PXCQJ2WXK3jk3kPrq 頁「04 · iOS Redesign（Google Maps 參考）」：共用元件 section 121:50484（深色 121:53698），D frame ID 見任務清單或 docs/ROUTE-MODE-PROMPTS.md。用 figma-console 截圖與讀取數值，只讀不改。
5. Sonnet 的進度回報（使用者會貼上）。

## 審查步驟（每個任務）
1. git log／git show 該任務 commit，確認只動了相關檔案，沒有夾帶無關變更或刪改既有測試。
2. 逐條對照驗收條件，以程式碼與測試為證據判定；Sonnet 回報的 ✅ 只作參考，必須自行核對。
3. 視覺：開 work/gofly-ios/route-mode/<任務編號>/ 的淺深色截圖，與 Figma 對應 frame 截圖比對尺寸、間距、顏色、字級、文案。已確認決定優先於 Figma（例如地圖右下角只有一顆回到定位按鈕、D1b 已廢止、預設選中起點）。
4. 自行執行 bash app/GoFly/scripts/check.sh 與該任務相關的 UI test，記錄結果。
5. 檢查三語字串齊全、深色模式、Dynamic Type 最大字級、VoiceOver 標籤與 .isSelected trait、44 pt 命中範圍。
6. 檢查文件：任務狀態只寫「已實作，待審查」，沒有宣稱實機驗證；規格變更有同步寫入。

## 重點風險（特別檢查）
- R2／R3：草稿模型加入空值後，路徑規劃、反轉、GPX 唯讀、最愛路線比對（GoFlyRoutePanel.matchingFavoriteRecord）、session 復原是否都正確處理空欄位。
- R1：路線與搖桿共用速度後，session 復原與偏好保存是否一致；舊版 5/20/60/120 是否完全移除。
- C7：所有 mode 與 panel 高度下按鈕與 panel 上緣間距固定 16 pt；指北移除後回到定位會重設正北。
- R6：結束後保留最後模擬位置，不清除裝置定位；dialog 開啟時背景不可互動。
- C1／C2：合併後所有既有呼叫點（瞬移、搖桿、首次引導）沒有退化。

## 輸出格式
先給總結：通過／需修正的任務數。
每個任務：
### <任務編號> — 通過 | 需修正 | 阻塞
- 驗收條件：逐條 ✅／❌，附證據（檔案:行號、測試名稱、截圖）
- 問題：嚴重度（阻擋／重要／次要）＋描述＋重現方式＋建議修正
- 與 Figma 的差異：可接受（引用決定）或需修正
最後列出：需要使用者決定的事項，以及可直接交回 Sonnet 的修正清單（依任務編號）。
不要寫「已實機驗證」；實機驗收需使用者授權後另行安裝。
```
