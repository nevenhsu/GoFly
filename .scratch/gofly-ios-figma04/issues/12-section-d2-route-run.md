# 12: D：路線執行、中斷與速度（D6、D7、D10、D10.a）

**What to build:** Figma D 區：路線執行面板與 `Top / 執行指示`、設定移動速度 sheet（遮罩、膠囊、slider）、路線中斷與恢復（Resume UI）。

**Blocked by:** 05.

**Status:** done: software-verified (2026-10-31 speed-chip CS alignment; Figma wireframe unchanged)

**Assignee hint:** Luna

- [x] D6、D7、D10、D10.a 對應 fixture 完成 Light／Dark 比對。
- [x] Pause／play 圖示為白色；執行面板與 Top 底色一致；D7 slider 與預設膠囊 5／25／50／100 行為不變。
- [x] 遮罩在 Dark 為黑色壓暗。
- [x] 本票涵蓋的所有 Toast／Banner 都以懸浮方式顯示（疊在內容上方、含浮層陰影、不推動版面），依票 04 的共用 Toast overlay 容器。
- [x] **地圖一律滿版**：所有出現地圖的畫面，地圖都填滿整個螢幕（延伸到狀態列、Dynamic Island、底部 Tab Bar 與 home indicator 後方，忽略四邊 safe area），面板、Sheet、Tab Bar、浮動控制項與狀態列疊在地圖上方；Sheet 展開／收合、鍵盤出現、旋轉與切換淺深色時地圖不縮放、不留空白邊或色帶，地圖的有效中心與右側控制鈕位置依可見區域（扣除 Sheet）計算。
- [x] 本票涵蓋的畫面中，所有圖示都經 `GoFlyIcon` 使用 Figma『0 · 共用元件（Icon）』匯出的資產（依票 03 對照表），不再出現 SF Symbol；尺寸、顏色 token 與 Figma 一致；對照表沒有的 icon 列入『執行紀錄』回報。
- [x] 本票涵蓋畫面的文字一律 `Font.system`（依 `Theme/*`），圖示一律來自 Figma『0 · 共用元件（Icon）』（經 `GoFlyIcon`）；沒有 `Font.custom`、SF Symbol 或自繪替代。
- [x] **截圖驗證（必做，沒有截圖視為未完成）**：用 01a 的 fixture（不需網路、VPN、真機）對本票涵蓋的每一張 frame、Light 與 Dark 各截一張，存到 `work/gofly-ios-figma04/screenshots/`，並與 `work/gofly-ios-figma04/figma/` 的同名 Figma 截圖並排比對：無破版、無文字截斷、無缺漏元素、顏色與層級一致。把每張的結論（一致／有差異＋原因）與檔案路徑寫入票尾『執行紀錄』；到不了的 frame 如實列出，不略過。
- [x] 最大 Dynamic Type 下仍可操作；本票速度 sheet 沒有自訂動畫、使用系統 sheet presentation，Reduce Motion 由系統動畫行為處理；互動元件觸控命中範圍 ≥ 44 × 44 pt；每個圖示按鈕有 accessibility label。
- [x] 相關單元測試與 UI tests 更新並通過；`app/GoFly/scripts/check.sh` 通過。
- [x] 不改命令、送點、ACK、背景執行語意（`app/GoFly/ARCHITECTURE.md` 不變量）；不宣稱實機驗證。

## 執行紀錄

（執行者在此記錄：日期、完成項、截圖路徑、未完成與原因、決策。）

### 2026-10-30 App implementation（票 12；Figma 04 只讀）

- **完成項**：移除 `Top / 執行指示` leading icon 的控制色底，保留透明背景與 44 × 44 pt 命中區；Warning Toast action 使用 `text/primary`，Light／Dark 與 Figma 渲染一致。D7 速度 sheet CTA 上間距 20 pt、底部可視間距 40 pt；利用系統 sheet 的 safe area inset 保持底部距離。最大 Dynamic Type 時改用大 detent，避免固定高度壓縮內容。D10／D10.a 暫停狀態的底部按鈕依使用者確認均為 play＋「繼續」；D10 系統中斷顯示 warning toast，D10.a 使用者暫停不顯示 toast。命令、送點、ACK 與背景執行語意未變。
- **Light／Dark 截圖與對照**：D6 `work/gofly-ios-figma04/screenshots/D6-light.png`／`D6-dark.png`；D7 `D7-light.png`／`D7-dark.png`；D10 `D10-light.png`／`D10-dark.png`；D10.a `D10.a-light.png`／`D10.a-dark.png`（均與 `work/gofly-ios-figma04/figma/` 同名圖並排）。D7 速度 sheet 的額外大字級截圖：`work/gofly-ios-figma04/screenshots/ticket12-feedback/D7-speed-sheet-accessibility-large-text.png`。D7 幾何及 D10 暫停／banner 的判斷測試皆通過。D6／D10／D10.a 的 Top icon 無底色；D10 warning action 文字色符合主題；D10.a 無 Toast。
- **保留的視覺差異**：執行 fixture 目前的路線目的地、距離／時間／速度與進度值，和 Figma 靜態 D6／D10／D10.a 不同；MapKit 道路、地名、POI 也不能逐像素重現 Figma 靜態 `Map / Base`。這些不影響本票元件層級驗收，截圖比對已記錄為 fixture／原生地圖差異。Figma D10 輔助說明寫「重試」，但渲染 Toast action 為「繼續」；依渲染。D10.a 靜態畫面與說明文字對播放／暫停按鈕不一致；使用者確認此暫停狀態應為 play＋「繼續」，App 依此呈現。Figma 未修改。
- **測試**：`testD7SpeedSheetUsesTwentyPointTopAndFortyPointBottomInsets`（Light／Dark＋大字級）通過；`testExecutionHeadersUseSemanticTextColorsInBothAppearances` 通過，涵蓋 D6／D7／D10／D10.a 與 E2／E2.a／E4 的 Light／Dark。E5 fixture 在先前探索執行未進入中斷漫步狀態，留待票 15 的 E5 驗收，不列入本票測試範圍。`bash app/GoFly/scripts/check.sh` 通過：359 tests／58 suites、LocalGoSetupHandoff tests、unsigned simulator build。Reduce Motion 未切換 simulator 系統設定；本票速度 sheet 沒有自訂動畫，僅依賴系統 sheet 行為。**未做實機驗證**。

### 2026-10-31 Speed chip CS alignment

- **Figma／設計規格**：04 `Chip / Preset` Light Selected instance 讀回為 `color/surface/card` 填色、`color/icon/accent` 描邊與 accent 文字；使用者確認 Dark Selected 為 `color/surface/control` 填色及 `color/icon/accent` 描邊。Default 兩主題均為 `color/surface/card` 填色與 `color/line/border` 描邊。Figma 04 保持唯讀；D7／E3 靜態 frame 未更新，D7 畫面仍呈現先前的藍色實心選取態，與本次確認的 CS mapping 有可見差異。
- **App 實作**：`GoFlySpeedSheet` 按以上 token 更新 Default／Selected 的底色、描邊與選取文字；快選值、點選／slider 行為及速度偏好不變。
- **驗證**：`bash app/GoFly/scripts/check.sh` 最初失敗於 `GoFlySetupBootstrap.swift:651`：`.luminanceToAlpha()` 回傳的 `some View` 不支援 `.renderingMode`。將 `.renderingMode(.template)` 移至 `Image` modifier 階段後，check 通過：59 setup tests、359 tests／58 suites、LocalGoSetupHandoff host tests 與 unsigned simulator build。UI test 首次呼叫因未傳入專案 bundle ID 覆寫而未進入測試；補上 `GOFLY_BUNDLE_ID`／`PRODUCT_BUNDLE_IDENTIFIER` 後，`testD7SpeedSheetUsesTwentyPointTopAndFortyPointBottomInsets`（Light／Dark／Accessibility XXXL）及 `GoFlySpeedUITests` 兩項均通過。
- **新截圖**：`work/gofly-ios-figma04/screenshots/ticket12-feedback/D7-speed-sheet-spacing-light.png`、`D7-speed-sheet-spacing-dark.png`、`D7-speed-sheet-accessibility-large-text.png`。`work/gofly-ios-figma04/screenshots/index.html` 的 D7 App columns 已連結新 Light／Dark 圖，並加入 Accessibility XXXL 圖片；Figma D7 references 未修改。**未做實機驗證**。
