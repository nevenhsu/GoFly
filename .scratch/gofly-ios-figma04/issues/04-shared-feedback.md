# 04: 狀態回饋共用元件

**What to build:** Toast（danger／warning／success）、Snackbar（2 秒自動消失／可復原）、StatusPill（啟動／模擬中／暫停／連線中斷）、StatusBanner、Progress、Slider（`Value` 0–100 比例軌道）與 Overlay／Dim（黑色 40%，Light 與 Dark 同一色）對齊 Figma 共用元件。

**Blocked by:** 01, 02.

**Status:** done: software-verified

**Assignee hint:** Luna

- [x] Toast 三個 tone 與 Figma Light／Dark 一致：圓角 14、內距 12／14、間距 10；標題 15 pt Semibold、說明 13 pt Regular、22 pt outline 狀態圖示、動作為膠囊按鈕；✕ 視覺 20 pt，命中範圍 44 × 44 pt，高度隨內容。App 使用 `Font.system` 的說明文字在 danger Toast 中比 Figma 早一字換行，全文仍顯示，詳見差異紀錄。
- [x] **Toast 一律懸浮**：所有 Toast／Banner（danger、warning、success，含設定頁的 Wi‑Fi 與服務錯誤、首次引導的錯誤、瞬移／路線／搖桿的錯誤與中斷、重置成功）都以 overlay 疊在畫面最上層，位於導覽列或搜尋列下方、距左右 16 pt，不得放進頁面內容的版面流程（不推動標題、卡片或清單位置）；使用浮層陰影（Figma Toast 元件：黑色 18%、y 4、blur 16），多個同時出現時依序堆疊並可個別關閉；Snackbar 維持底部懸浮。實作用共用 Toast 元件與單一 overlay 容器，不得各頁自己 inline 放置。R04 VPN 檢查成功不顯示 success Toast，改為自動進入 B1。
- [x] Snackbar 與 StatusPill 對照 Figma；Dark 色不使用純白。
- [x] Overlay／Dim 在 Dark 為黑色遮罩（不得是淺色遮罩）；Sheet、ActionSheet、系統分享 sheet 後方畫面皆被壓暗。
- [x] Progress 與 Slider 可在展示頁互動，Slider 縮放寬度時進度比例不變。
- [x] **截圖驗證（必做，沒有截圖視為未完成）**：用 01a 的 fixture（不需網路、VPN、真機）對本票涵蓋的每一張 frame、Light 與 Dark 各截一張，存到 `work/gofly-ios-figma04/screenshots/`，並與 `work/gofly-ios-figma04/figma/` 的同名 Figma 截圖並排比對：無破版、無文字截斷、無缺漏元素、顏色與層級一致。把每張的結論（一致／有差異＋原因）與檔案路徑寫入票尾『執行紀錄』；到不了的 frame 如實列出，不略過。元件板逐態截圖完成；B7／D8／F1.b 的頁面差異已分派至對應頁面與行為票，詳見 2026-10-30 記錄。
- [x] 最大 Dynamic Type 與 Reduce Motion 下仍可操作；互動元件觸控命中範圍 ≥ 44 × 44 pt；每個圖示按鈕有 accessibility label。
- [x] 相關單元測試與 UI tests 更新並通過；`app/GoFly/scripts/check.sh` 通過。
- [x] 不改命令、送點、ACK、背景執行語意（`app/GoFly/ARCHITECTURE.md` 不變量）；不宣稱實機驗證。

## 執行紀錄

### 2026-10-29 執行紀錄（Luna）

- 共用 `GoFlyStatusBanner`／overlay 已調整 outline 狀態 icon、Figma Toast 陰影與尺寸、44 pt 關閉命中區及多筆浮層；R04 VPN 成功不顯示 success Toast，改為確認後自動進 B1 收合 sheet。Snackbar 繼續使用底部浮層。重置成功 Toast 元件仍可供 F1.b 使用。
- 抽查截圖路徑：`work/gofly-ios-figma04/screenshots/{R04.a,B7,B10,D8,F1.b}-light.png` 與各自 `-dark.png`；總覽 `work/gofly-ios-figma04/screenshots/index.html`。R04.a／B7／D8 顯示錯誤浮層，B10 顯示 Wi-Fi 提示，F1.b 顯示重置成功提示；未完成共用元件板所有 variant 的逐一截圖比對，且 01a 尚有 45 個 frame 不可達，故本票維持 `in progress`。
- Figma success Toast 元件 outline 色實綁 `icon/success`（Dark `#6FC48B`），與 `line/status/success` token（Dark `#52A072`）不同；App 依渲染採 icon token，保留此 Figma token 綁定差異記錄。未修改 Figma；未做實機驗證。
- 使用者追加 Toast 比對項（2026-10-29，待實作／重截）：B7 title 與說明各最多兩行、action button 靠右；B10 action button 背景依 Figma；F1.b Toast 上移。各頁細項另記於票 07、16。R04-connected 成功後不顯示 success Toast，依票 06 執行。

### 2026-10-30 執行紀錄（Luna）

- **Figma（只讀）**：再次讀取 STATUS 元件板 Toast danger 渲染（`268:21643`）：361 × 85 pt；圖示 22 pt；文字欄 x=47、寬 203 pt，標題 15 pt／21 pt 行框、說明 13 pt／36 pt；action x=260、56 × 32 pt；close glyph x=326、20 × 20 pt。以渲染為準，沒有修改 Figma。
- **App 實作**：共用 `GoFlyStatusBanner` 的 close 44 pt 命中區不再擠壓內容欄；action 與 close 對齊 Figma 位置，標題行框及說明行距按 85 pt Toast 渲染調整；大型 Dynamic Type 改為垂直排列並保留 44 pt action／close 命中區。Toast 使用雙色 Figma status icon 資產；R04 VPN 成功仍自動進 B1 且不顯示 success Toast。
- **截圖位置**：Toast／Pill／Snackbar／Progress／Slider 的 Light／Dark gallery、Dark AXXXL＋Reduce Motion、系統 Sheet 遮罩與 danger 對照均在 `work/gofly-ios-figma04/screenshots/ticket04-feedback/`，並排頁為 `work/gofly-ios-figma04/screenshots/ticket04-feedback/index.html`；原始 Figma 圖在 `work/gofly-ios-figma04/figma/Toast-{light,dark}-{danger,warning,success}.png` 及 `SharedFeedback-{light,dark}.png`。
- **殘餘差異**：Danger Toast 說明在 App `Font.system` 下比 Figma 換行早一個字元；85 pt 外框、狀態圖示、action、close 的位置與命中範圍已對齊。這是目前保留的字體度量差異，尚未改文案或縮小字級。
- **情境 frame 驗證缺口**：已嘗試 `B7/B10/D8/F1.b` Light／Dark UI fixture。iPhone 17 Pro 與 Pro Max 模擬器在 B7 fixture 啟動期間停留 launch screen，主執行緒持續做 SwiftUI／MapKit layout，XCTest 無法取得 `figma.fixture.B7`，其餘 frame 未執行。日誌／結果：`work/gofly-ios-figma04/ticket04-map-toast-frames-projection.log`、`ticket04-map-toast-frames-geometry-gates.log`，xcresult 在 `work/gofly-ios/ui-tests/ticket04-map-toast-frames-projection.xcresult`、`ticket04-map-toast-frames-geometry-gates.xcresult`。舊的 2026-10-29 contextual screenshots 保留但不當成本輪重截驗收；因此逐 frame 截圖 checkbox 保持未勾，票 Status 維持 `in progress`。
- **驗證**：`GoFlyToastUITests` 4/4 通過（`work/gofly-ios-figma04/ticket04-toast-final.log`，xcresult `work/gofly-ios/ui-tests/ticket04-toast-final.xcresult`）；`bash app/GoFly/scripts/check.sh` 通過，349 tests／58 suites、native host checks 通過（`work/gofly-ios-figma04/ticket04-check-final.log`）。未做實機驗證，未 commit。

### 2026-10-30 執行紀錄補充（Luna）

- **佈局根因與修正**：地圖頁的 Toast 原先作為 `ZStack` 同層內容，且 Toast top inset 取自頂部面板量測值，形成高度回饋，讓 MapKit／SwiftUI 佈局反覆增高，UI fixture 停在 launch screen。Toast 改為地圖內容的 top overlay 後不再參與地圖尺寸；可點擊 StatusPill 移除會隨父層擴張的透明背景 sibling，保留 capsule 外觀及 44 pt 命中區。重新截圖已成功。
- **截圖與比對**：共用元件逐態 Light／Dark、AXXXL／Reduce Motion、系統 Sheet 遮罩位於 `work/gofly-ios-figma04/screenshots/ticket04-feedback/`，並排頁 `work/gofly-ios-figma04/screenshots/ticket04-feedback/index.html`；Toast 原始 Figma 渲染位於 `work/gofly-ios-figma04/figma/Toast-{light,dark}-{danger,warning,success}.png`、`SharedFeedback-{light,dark}.png`。B7、B10、D8、F1.b Light／Dark 情境 fixture 位於 `work/gofly-ios-figma04/screenshots/ticket04-feedback-frames/`，並排頁 `work/gofly-ios-figma04/screenshots/ticket04-feedback-frames/index.html`；比較依據為 `work/gofly-ios-figma04/figma/{B7,B10,D8,F1.b}-{light,dark}.png`。
- **逐 frame 結論**：B10 Light／Dark 單一提示 Toast 浮於搜尋列下方，外觀與位置一致。B7 Light／Dark 的浮層位置正確，但頁面同時產生兩個服務錯誤 Toast、文字換行較 Figma 長；文案行數與服務錯誤狀態整理列入票 07。D8 Light／Dark 的浮層位置正確，尚缺「修正」動作，依全地點重排行為列入票 11。F1.b Light／Dark 的 Toast 已浮於內容上方但比 Figma 低，設定頁標題／頂部結構更新列入票 16。這些是各頁／行為票的差異，不是共用 overlay 元件的定位失效。
- **保留差異／設計缺口**：danger Toast 的 `Font.system` 說明文字相對 Figma 多一個字元才換行，全文未裁切；為符合使用者指定字體不使用字面字型或自訂字體。Map/頁面截圖仍受系統字體度量影響。未發現此票共用元件的 Figma 缺漏。
- **驗證**：`GoFlyToastUITests` 4/4 通過（`work/gofly-ios-figma04/ticket04-toast-ui-final.log`，xcresult `work/gofly-ios/ui-tests/ticket04-toast-ui-final.xcresult`）；`bash app/GoFly/scripts/check.sh` 通過，349 tests／58 suites、LocalGoSetupHandoff host checks 10 項及 unsigned simulator build 成功（`work/gofly-ios-figma04/ticket04-check-verified.log`）。未做實機驗證、未 commit。
