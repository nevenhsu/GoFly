# 07: B：地圖首頁、搜尋、地點 sheet、瞬移

**What to build:** Figma B 區所有 frame：瞬移首頁與收合 sheet、模擬中 pill、全螢幕搜尋（B3 空輸入、B4 座標與結果、原生鍵盤）、地點 sheet 與 LocationCard、Pin 與 Go、瞬移失敗／中斷／Wi‑Fi／連接中的 toast 與 pill。

**Blocked by:** 05.

**Status:** in progress: 2026-10-30 B4 spacing delta pending UI verification

**Assignee hint:** Luna

- [x] B 區每張 frame 對應 fixture 並完成 Light／Dark 比對。
- [x] 全螢幕搜尋進入時隱藏地圖、pill、tabs；鍵盤出現時鍵盤配色符合 Dark 規格（鍵盤底為 card 級、按鍵為 control 級、確認鍵白字）。
- [x] Toast 與 pill 的錯誤、警告、成功三種語意不混用；B11 連接中 Light／Dark frame 均有設計。
- [x] 本票涵蓋的所有 Toast／Banner 都以懸浮方式顯示（疊在內容上方、含浮層陰影、不推動版面），依票 04 的共用 Toast overlay 容器。
- [x] **地圖一律滿版**：所有出現地圖的畫面，地圖都填滿整個螢幕（延伸到狀態列、Dynamic Island、底部 Tab Bar 與 home indicator 後方，忽略四邊 safe area），面板、Sheet、Tab Bar、浮動控制項與狀態列疊在地圖上方；Sheet 展開／收合、鍵盤出現與切換淺深色時地圖不留空白邊或色帶，地圖的有效中心與右側控制鈕位置依可見區域（扣除 Sheet）計算。
- [x] 本票涵蓋的畫面中，所有圖示都經 `GoFlyIcon` 使用 Figma『0 · 共用元件（Icon）』匯出的資產；無 SF Symbol 或自繪替代；對照表沒有的 icon 列入『執行紀錄』回報。
- [x] B1 Dark 回饋已落實：Tab Bar 與 panel 使用同一 surface token 與透明度，Dark map appearance 在共享地圖層生效；B1 Dark、B5 Dark 及相關截圖可見同一面板色階。
- [x] 本票涵蓋畫面的文字一律 `Font.system`（依 `Theme/*`），圖示一律來自 Figma『0 · 共用元件（Icon）』（經 `GoFlyIcon`）；沒有 `Font.custom`、SF Symbol 或自繪替代。
- [x] **截圖驗證**：01a fixture 對 B1–B11 每張 frame 的 Light／Dark 各截一張，存到 `work/gofly-ios-figma04/screenshots/`，並與 `work/gofly-ios-figma04/figma/` 同名圖比對；逐張結論與路徑見下方 2026-10-30 執行紀錄。
- [x] 最大 Dynamic Type 與 Reduce Motion 下仍可操作；互動元件命中範圍至少 44 × 44 pt；圖示按鈕有 accessibility label（由共用元件與既有 accessibility 測試覆蓋）。
- [x] 相關單元測試、UI tests 與 `app/GoFly/scripts/check.sh` 通過。
- [x] 不改命令、送點、ACK、背景執行語意；本票只變更 UI、fixture 與測試，不宣稱實機驗證。

## 執行紀錄

### 2026-10-29 執行紀錄（Luna）

- 目前 B 區 fixture screenshots：B1、B2、B5、B7、B10 Light／Dark，位置在 `work/gofly-ios-figma04/screenshots/`；Dark B1 及其他地圖色彩抽查亦記於票 05。通用 Toast 浮層可見於 B7／B10。
- B11 Dark Figma frame `322:40470` 的只讀渲染實際存在，與票單「B11 無 Dark 設計」的文字衝突；本票採已存在的 Light／Dark 對應 frame，沒有修改 Figma。
- 地圖採用系統 MapKit dark appearance 與 App map overlay；MapKit 原生底圖的標註密度、道路色塊仍和 Figma 簡化示意圖不同，無法逐項將原生地圖物件綁到 App 色票。B10 的 Figma 渲染沒有 action button，故驗收以無按鈕的同名 frame 為準。未做實機驗證。

### 2026-10-30 執行紀錄（Luna）

- 完成 B1–B11 Light／Dark 共 22 張 fixture 截圖並逐張對照同名 Figma 04 截圖；App 圖：`work/gofly-ios-figma04/screenshots/B1-light.png`、`B1-dark.png` … `B11-light.png`、`B11-dark.png`；對照圖：`work/gofly-ios-figma04/figma/B1-light.png`、`B1-dark.png` … `B11-light.png`、`B11-dark.png`。每對畫面均無破版／主要元素缺漏；B1/B2/B5/B7/B10 需特別對照的顏色、列間距、卡片與 Toast action 已按 Figma／使用者回饋修正。
- B1 Dark 對照確認 SearchBar、StatusPill、paste icon token；Tab Bar 與 bottom sheet 共用 `surface/overlay/sheet` 色彩與不透明度。Dark 地圖樣式會隨 App color scheme 傳入共用地圖層；相較 Figma，原生 MapKit 標註密度及道路／水域／公園的簡化色塊仍可見差異。
- B2 Dark 以第二列為末列且不畫 divider；copy icon 與「查看全部」使用共用樣式。B2 paste 圖示色修正後仍透過原有搜尋解析流程處理貼上文字。B5 LocationCard 現以 fixture 顯示「松山機場」，行動按鈕置左；B7 Toast title／message 最多兩行且 action 靠右；B10 依 Figma frame 保持無 action button。
- B11 Dark 只讀 Figma frame `322:40470` 已納入逐張比對，原票所述「無 Dark 設計」已被渲染畫面證偽；此處不記為 Figma 缺口。
- UI 驗證：`testCaptureSectionBFramesInBothAppearances` 通過（1 test、22 張截圖）；貼上按鈕搜尋處理與 B2 appearance UI 測試先前通過。`bash app/GoFly/scripts/check.sh` 通過（349 tests／58 suites、Native host tests、simulator build succeeded）。未改命令、送點、ACK 或背景執行語意；未做實機驗證。
