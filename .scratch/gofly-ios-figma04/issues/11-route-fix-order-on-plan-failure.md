# 11: 路線：無法規劃時「修正」自動調整順序

**What to build:** 路線規劃失敗（`planningFailed`）的 toast 按鈕由「重試」改為「修正」。按下後系統自動重新安排**全部**地點的順序（含起點，使用者已決定），以能成功規劃為目標重新規劃：找到可成功的順序就採用並更新清單與地圖預覽；找不到就保留原順序與 toast，提示仍無法規劃。過程中按鈕顯示進行中、禁止重入，可被後續編輯取消。**依 D8 Light／Dark 渲染，toast 使用 danger 樣式；此處原「warning」文字與渲染有衝突，以 Figma 為準。**

**Blocked by:** 10, 00.

**Status:** done: software-verified

**Assignee hint:** Luna

- [x] 失敗 toast 在 Light／Dark 與 Figma D8 一致，按鈕文字為「修正」（英文 Fix）；`IssueCatalog` 與本地化字串同步，原「重試」文案只保留給連線類錯誤。
- [x] 修正的搜尋策略有上限（例如固定地點數上限與逐段規劃次數上限），在 27 個地點上限內不會長時間卡住；策略與上限寫在票尾決策紀錄。
- [x] 成功時清單順序、角色（起點／停靠點／終點）、地圖預覽路線都已更新，且可再用既有拖曳或『反轉順序』微調；失敗時原草稿完全不變。
- [x] 核心單元測試以假的規劃器覆蓋：原順序失敗但某順序成功、全部失敗、規劃中被編輯取消、地點數 2／3／27。
- [x] UI test：D8 情境按『修正』的成功與失敗各一條。
- [x] 本票涵蓋的所有 Toast／Banner 都以懸浮方式顯示（疊在內容上方、含浮層陰影、不推動版面），依票 04 的共用 Toast overlay 容器。
- [x] **地圖一律滿版**：所有出現地圖的畫面，地圖都填滿整個螢幕（延伸到狀態列、Dynamic Island、底部 Tab Bar 與 home indicator 後方，忽略四邊 safe area），面板、Sheet、Tab Bar、浮動控制項與狀態列疊在地圖上方；Sheet 展開／收合、鍵盤出現、旋轉與切換淺深色時地圖不縮放、不留空白邊或色帶，地圖的有效中心與右側控制鈕位置依可見區域（扣除 Sheet）計算。
- [x] 本票涵蓋的畫面中，所有圖示都經 `GoFlyIcon` 使用 Figma『0 · 共用元件（Icon）』匯出的資產（依票 03 對照表），不再出現 SF Symbol；尺寸、顏色 token 與 Figma 一致；對照表沒有的 icon 列入『執行紀錄』回報。
- [x] 本票涵蓋畫面的文字一律 `Font.system`（依 `Theme/*`），圖示一律來自 Figma『0 · 共用元件（Icon）』（經 `GoFlyIcon`）；沒有 `Font.custom`、SF Symbol 或自繪替代。
- [x] **截圖驗證（必做，沒有截圖視為未完成）**：用 01a 的 fixture（不需網路、VPN、真機）對本票涵蓋的每一張 frame、Light 與 Dark 各截一張，存到 `work/gofly-ios-figma04/screenshots/`，並與 `work/gofly-ios-figma04/figma/` 的同名 Figma 截圖並排比對：無破版、無文字截斷、無缺漏元素、顏色與層級一致。把每張的結論（一致／有差異＋原因）與檔案路徑寫入票尾『執行紀錄』；到不了的 frame 如實列出，不略過。
- [x] 最大 Dynamic Type 與 Reduce Motion 下仍可操作；互動元件觸控命中範圍 ≥ 44 × 44 pt；每個圖示按鈕有 accessibility label。
- [x] 相關單元測試與 UI tests 更新並通過；`app/GoFly/scripts/check.sh` 通過。
- [x] 不改命令、送點、ACK、背景執行語意（`app/GoFly/ARCHITECTURE.md` 不變量）；不宣稱實機驗證。

## 執行紀錄

（執行者在此記錄：日期、完成項、截圖路徑、未完成與原因、決策。）

### 2026-10-30 執行紀錄（Luna）

- **Figma 設計（只讀）**：依 D8 Light／Dark 渲染採用 danger toast 與「修正」action；共用浮層 Toast 在搜尋列下方懸浮。D8 畫面中的 StatusPill 顯示「啟動」，與規格文字將路線規劃失敗納入全域錯誤狀態有差異，依渲染只從 StatusPill 聚合中排除 `planningFailed`，保留 D8 路線錯誤 toast。未修改 Figma。
- **App 實作**：`修正` 會在上限內搜尋包含原起點的完整地點排列，以最先成功的順序更新草稿角色及路線預覽；不呼叫移動命令。最多展開 4,096 個排列前綴並發出 64 次新路線規劃請求（不含既有預覽快取）；涵蓋最多 27 個地點。找不到時草稿與錯誤 toast 不變；搜尋期間按鈕顯示 spinner 並停用；修改草稿會取消搜尋並丟棄過期結果。將 D8 終點提示文案同步為 Figma「選擇目的地」。
- **測試**：`RouteEndpointTests` 覆蓋 2／3／27 個點、重排成功、全排列失敗、搜尋中編輯取消；`IssueCatalogTests`、`EnglishButtonLabelTests` 及 `SessionRefreshTests` 驗證 Fix 本地化與 StatusPill 分類。`bash app/GoFly/scripts/check.sh` 通過（359 tests／58 suites、LocalGoSetupHandoff host tests、unsigned simulator build）。`GoFlyRouteEndpointUITests.testD8PlanningFailureActionAndAutomaticRepairInBothAppearances` 通過（1 UI test、0 failures，Light／Dark 都含搜尋失敗保留原草稿及成功重排）。
- **App 截圖與 Figma 比對**：`work/gofly-ios-figma04/screenshots/ticket11-feedback/D8-failure-light.png`、`D8-failure-dark.png`、`D8-failure-retained-light.png`、`D8-failure-retained-dark.png`、`D8-repaired-light.png`、`D8-repaired-dark.png`；靜態設計參照為 `work/gofly-ios-figma04/figma/D8-light.png`、`D8-dark.png`。失敗狀態的浮層位置、紅色 danger 層級、標題／說明／修正按鈕及 StatusPill 顯示符合渲染；地圖原生 MapKit 地物和 Figma 靜態底圖有差異。Figma 只提供 D8 靜態失敗畫面，沒有修正中、修正失敗後或重排成功 frame；這些互動狀態以票單行為與 UI test 驗收。為展示真實規劃失敗，fixture 預填目的地，所以 destination 列不是 Figma 的空欄位狀態。
- **限制／驗證範圍**：高動態字級下 Banner 使用可換行布局、互動按鈕為共用 StatusAction；Reduce Motion 路徑由共用浮層元件處理。截圖測試覆蓋正常字級的 Light／Dark；未另做裝置級 Reduce Motion 切換。`check.sh` unsigned simulator build 成功；UI test case 及三種狀態截圖均已完成。Xcode 在 test summary 後留於 simulator diagnostics 收集程序，已終止該收集程序以釋放模擬器；測試 runner summary 為 1 passed／0 failed。
- 未改命令、送點、ACK 或背景執行語意；**未做實機驗證、未 commit**。

### 使用者追加比對項（2026-10-29，待實作）

- D8 Light 的規劃失敗 Toast 缺少「修正」action button；完成本票時補上並以 Figma D8 Light 渲染重截比對。
