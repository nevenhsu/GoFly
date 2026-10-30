# 03: 按鈕、Icon Button 與輸入欄共用元件

**What to build:** 按鈕板（Figma Light／Dark『0 · 共用元件（按鈕）』）所有元件在 App 有唯一實作並可在元件展示頁（`GoFlyComponentGallery`）檢視：Icon Button（Standard／Route／Ghost／Clear／More／MapControls／Copy，Large 44／Medium 40／Small 36／Extra Small 32，Enabled／Disabled，外框 `line/separator` 0.5 pt）、Icon + Text 與 Text 按鈕（Primary／Neutral／Danger／Ghost，四種尺寸與 Inline，內容置中）、Check、Status action、Text Field（Default／Focused／Disabled）。

**Blocked by:** 01, 02.

**Status:** done: software-verified

**Assignee hint:** Luna

- [x] 每個 variant 與 Figma 按鈕板逐一比對（尺寸、底色、邊線、字級、置中）；視覺小於 44 pt 者命中範圍仍 ≥ 44 pt。
- [x] Primary 按鈕文字與圖示為純白；Enabled 圓形 Icon Button 外框為 0.5 pt `line/separator`。
- [x] Text Field 三態：Default 使用 control 色、Focused 使用 active 色並有 primary 外框、Disabled 對照 Figma。
- [x] 展示頁 Light／Dark 截圖與按鈕板一致；既有畫面改用共用元件，不留重複手刻副本。
- [x] **圖示一律使用 Figma『0 · 共用元件（Icon）』**：每個畫面的圖示都對應該目錄的 `icon/*` 共用元件（匯出的資產經 `GoFlyIcon` 使用），不得用 SF Symbol 或自繪圖形替代；目錄沒有的圖示列出回報。
- [x] **圖示一律匯出成資產，不使用 SF Symbol**：Figma『0 · 共用元件（Icon）』目前渲染出 53 個 `icon/*`（票單原記 52；已依只讀 Icon board 截圖更正數量），全部匯出為單色 template 資產（`.imageset`，向量 PDF 或 SVG，命名與 Figma 一致，例如 `icon/star` → `icon-star`），由單一 `GoFlyIcon` 入口（enum 或等價型別）統一提供，可著色、尺寸可指定、隨 Dynamic Type 縮放的容器內使用。App 內既有的 `GoFlySymbols` 與所有 `Image(systemName:)`、`Label(systemImage:)` 全數改用 `GoFlyIcon`，完成後 UI 層沒有殘留 SF Symbol（系統原生控制，如導覽返回鈕、原生鍵盤、分享 sheet，不在範圍）。建立並維護對照表（寫入票尾）：每個 `icon/*` ↔ 資產名；App 用了但目錄沒有的圖示，列出清單回報，不自行新增、不挑相近圖示。新增單元測試：53 個資產都存在且為 template 渲染，`GoFlyIcon` 無遺漏 case。
- [x] **截圖驗證（必做，沒有截圖視為未完成）**：用 01a 的 fixture（不需網路、VPN、真機）對本票涵蓋的每一張 frame、Light 與 Dark 各截一張，存到 `work/gofly-ios-figma04/screenshots/`，並與 `work/gofly-ios-figma04/figma/` 的同名 Figma 截圖並排比對：無破版、無文字截斷、無缺漏元素、顏色與層級一致。把每張的結論（一致／有差異＋原因）與檔案路徑寫入票尾『執行紀錄』；到不了的 frame 如實列出，不略過。
- [x] 最大 Dynamic Type 與 Reduce Motion 下仍可操作；互動元件觸控命中範圍 ≥ 44 × 44 pt；每個圖示按鈕有 accessibility label。
- [x] 相關單元測試與 UI tests 更新並通過；`app/GoFly/scripts/check.sh` 通過。
- [x] 不改命令、送點、ACK、背景執行語意（`app/GoFly/ARCHITECTURE.md` 不變量）；不宣稱實機驗證。

## 執行紀錄

### 2026-10-30 執行紀錄（Luna）

- 完成共用 `GoFlyButtonStyle`、`GoFlyIconStyle`、`GoFlyStatusActionStyle` 與 `GoFlyTextFieldState`；按鈕 type／size／disabled 樣式、Primary 白字白圖、Enabled 圓形外框、Text Field 三態及 ≥44 pt 命中區接上 token。Ghost／Clear／More disabled 維持透明底，修正了第一輪截圖中錯誤出現灰色圓底的情況。
- 新增 `GoFlyIcon` 及 Figma 向量資產；既有 `GoFlySymbols`、Settings gear、speed presets 和畫面圖示改用該入口。UI Swift 檔沒有 `Image(systemName:)` 或 `Label(systemImage:)` 殘留；品牌 logo 與系統原生控制不屬於 `icon/*`。
- Icon board 實際有 53 個 `icon/*`（票單原記 52）；已修正票單與 Tracker。另匯入 9 個 `map/*` 與 4 個 `speed/*` 多色向量資產，經同一 `GoFlyIcon` 入口呈現。
- App 與 Figma 並排：按鈕外觀／狀態／大小／文字樣式、Text Field 三態與 Light／Dark 色彩層級符合 board。App gallery 以手機長頁呈現、Figma 是橫向元件板，版面形式不同；共用元件本身的 variant 呈現相符。Check 的選取狀態以 primary 圓底加 `icon/check` 組成，符合 Figma Check component；Icon board 未提供獨立 `icon/okfill`。D1 的「＋ 新增停靠點」是按鈕文案中的加號字元，非獨立 icon；Icon board 沒有 `icon/plus`，因此保留 Figma 文字且沒有新增或替代資產。`map/node-waypoint` 只提供靜態數字 1，Figma 未定義動態編號變體；後續地圖註記維持頁面本身的路線節點呈現。
- Light／Dark Figma 對照圖：`work/gofly-ios-figma04/figma/SharedButtons-light.png`、`SharedButtons-dark.png`、`SharedIcons-light.png`。App gallery 截圖共 18 張，逐張路徑為 `work/gofly-ios-figma04/screenshots/ticket03-components-verified/shared-button-components-{light,dark}-{0..8}.png`；Text Field：`work/gofly-ios-figma04/screenshots/ticket03-field-verified/C4-fields-{light,dark}.png`；最大 Dynamic Type：`work/gofly-ios-figma04/screenshots/ticket03-components-verified/shared-button-targets-axxxl.png`。並排總覽：`work/gofly-ios-figma04/screenshots/ticket03-components-verified/index.html`。狀態列在 gallery 截圖中隱藏，以免捲動畫面遮住頂部元件；此設定只在 Debug 共用元件展示頁。
- 測試：`bash app/GoFly/scripts/check.sh` 通過（348 Swift tests／58 suites、Native host checks、unsigned Simulator build）；UI tests `testCaptureSharedButtonComponentsLightAndDark` 與 `testSharedIconButtonsKeepFortyFourPointTargetsAtAccessibilitySize` 通過；`GoFlyFieldUITests.testSearchFieldProgressAndSliderMatchSharedSpec` 通過（44 pt）。UI 截圖使用 iPhone 17 Pro Simulator fixture，未做實機驗證。未改命令／送點／ACK／背景執行不變量；未 commit。

#### `icon/*` → `.imageset` 對照

| Figma component | Asset name | Figma component | Asset name |
| --- | --- | --- | --- |
| `icon/alert` | `icon-alert` | `icon/arrow-right` | `icon-arrow-right` |
| `icon/battery-full` | `icon-battery-full` | `icon/bookmark` | `icon-bookmark` |
| `icon/check` | `icon-check` | `icon/chevron-down` | `icon-chevron-down` |
| `icon/chevron-left` | `icon-chevron-left` | `icon/chevron-right` | `icon-chevron-right` |
| `icon/chevron-up` | `icon-chevron-up` | `icon/close` | `icon-close` |
| `icon/copy` | `icon-copy` | `icon/direction-forward` | `icon-direction-forward` |
| `icon/direction-reverse` | `icon-direction-reverse` | `icon/expand` | `icon-expand` |
| `icon/external-link` | `icon-external-link` | `icon/flag` | `icon-flag` |
| `icon/gear` | `icon-gear` | `icon/globe` | `icon-globe` |
| `icon/grip` | `icon-grip` | `icon/help` | `icon-help` |
| `icon/history` | `icon-history` | `icon/hourglass` | `icon-hourglass` |
| `icon/joystick` | `icon-joystick` | `icon/locate` | `icon-locate` |
| `icon/mac` | `icon-mac` | `icon/moon` | `icon-moon` |
| `icon/more` | `icon-more` | `icon/nav` | `icon-nav` |
| `icon/paste` | `icon-paste` | `icon/pause` | `icon-pause` |
| `icon/phone` | `icon-phone` | `icon/pin` | `icon-pin` |
| `icon/play` | `icon-play` | `icon/repeat` | `icon-repeat` |
| `icon/repeat-off` | `icon-repeat-off` | `icon/reset` | `icon-reset` |
| `icon/route` | `icon-route` | `icon/route-folder` | `icon-route-folder` |
| `icon/route-list` | `icon-route-list` | `icon/search` | `icon-search` |
| `icon/select` | `icon-select` | `icon/shield` | `icon-shield` |
| `icon/shuffle` | `icon-shuffle` | `icon/signal` | `icon-signal` |
| `icon/speed` | `icon-speed` | `icon/star` | `icon-star` |
| `icon/star-filled` | `icon-star-filled` | `icon/stop` | `icon-stop` |
| `icon/success` | `icon-success` | `icon/swap-horizontal` | `icon-swap-horizontal` |
| `icon/swap-vertical` | `icon-swap-vertical` | `icon/trash` | `icon-trash` |
| `icon/wifi` | `icon-wifi` | — | — |
