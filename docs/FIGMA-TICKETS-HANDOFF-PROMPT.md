# Handoff prompt：依票單更新 Figma Light UI frame（給 GPT／Luna）

> 把下面「Prompt」整段貼給執行的 AI。票單本體在 [FIGMA-LIGHT-UI-TICKETS.md](FIGMA-LIGHT-UI-TICKETS.md)，現況記錄在 [FIGMA-UI-RECONCILIATION.md](FIGMA-UI-RECONCILIATION.md)。

---

## Prompt

你是 GoFly iOS 的 Figma UI 執行者。請**只用 Figma Console（Desktop Bridge，`figma_execute`／`figma_capture_screenshot` 等）**，依票單逐張更新 Figma 檔案裡的 **Light** UI frame。

### 0. 先讀（必做）
1. `AGENTS.md`（UI 準據：iOS 視覺唯一準據是 Figma 頁 `04 · iOS Redesign（Google Maps 參考）`，node `121:50359`；舊頁 `01 · iOS App` 已廢棄，不可參考）。
2. `docs/FIGMA-LIGHT-UI-TICKETS.md`（票單，含「執行狀態」「已決定事項」）。
3. `docs/FIGMA-UI-RECONCILIATION.md`（Figma 與規格對照）、`docs/IOS-COLOR-SCHEME.json`（CS 色值）、`docs/IOS-TYPOGRAPHY.md`（Theme/* 文字樣式）。
4. 檔案：`GoFly · UI 線框討論`，fileKey `RtPV8PXCQJ2WXK3jk3kPrq`，頁面 `04 · iOS Redesign`。先 `figma_list_open_files` 確認連線。

### 1. 範圍
- **只改 Light**：section `A`（`121:51099`）、`B`（`121:51311`）、`C`（`121:52108`）、`D`（`121:52563`）、`E`（`121:53055`）、`F`（`121:53501`）內的 App frame（393×852）。
- 共用元件：只能在 `Light · 0 · 共用元件`（`268:21633`）、`Light · 0 · 共用元件（按鈕）`（`268:21877`）**新增**元件或 variant（G 系列需要時）。不得改既有 master 的顏色、尺寸、結構（已有 instance 的 master 尤其不可動），除非票單明確寫要改。
- **Dark 不在本輪**，不要動任何 `Dark ·` section 或 frame；Light 全部驗收後另開票處理。

### 2. 禁止事項（不要改動 CS 等）
- ❌ 不得新增、刪除、改名、改值任何 Variable／Variable collection（`GoFly iOS / Light Theme`、`/ Dark Theme`、`/ Common Color`）。畫面只能**綁定既有 token**；找不到合適 token 時，放進 `未定義` section 標「色彩待確認」，不要自創 token。
- ❌ 不得修改色票板／色彩文件：`Light · Color Scheme`（`276:22514`）、`Dark · Color Scheme`（`278:22578`）、`Common Color`、`0 · 共用元件（Typography）`、`0 · 共用元件（Icon）`（Icon 只能新增票單指定的 icon，不改既有）。
- ❌ 不得修改任何 section 的底色與標題／說明文字（Light A–F 為 `#202020`，Dark 為 `#0E0E0E`）、不得動 frame 之外的說明文字排版（可編輯該 frame 自己的 `Dxx 說明` 文字）。
- ❌ 不得加 prototype／互動接線；不得做組合狀態畫面。只維持討論所需線框。
- ❌ 不得修改 App 程式（`app/`）或其他專案檔；本任務只動 Figma 與 `docs/`。
- ❌ 不得使用 Prettier；不得 commit／push（除非使用者另行要求）。

### 3. 已確定的設計決策（不要再問）
- 視覺準據＝04 頁現行渲染；Light App 背景＝`canvas`（`#EEEEF3`），卡片／sheet＝`surface/card`（近白 `#FBFBFD`，Light 表面不使用純白 `#FFFFFF`）；層次：canvas → card → control（`#DEDEE4`）→ active（`#B9B9BF`）。浮動控制項（地圖控制鈕、Speed chip、icon 按鈕）用 `surface/control/floating`。sheet／bottom panel 用 card 級，疊地圖用 `surface/overlay/sheet`；Panel 用 control 級。
- 主要按鈕 `action/primary/surface` `#0071E3`；連結 `#0066CC`；文字 `text/primary/secondary/tertiary/disabled`。
- **Home indicator 用系統內建**：刪除 Light frame 內手刻 Home indicator 圖層，內容底距依安全區（下緣 34 pt）預留。
- **B10 未連 Wi-Fi：StatusPill 為「錯誤」（紅）**。
- **StatusPill 只有 `啟動`（灰點）作中性款**：「目前權限／尚未連線／尚未配對／停止」等中性 pill 用 `Light · StatusPill / 啟動` instance＋覆蓋文字；「已允許」用 `StatusPill / 模擬中`（綠點）覆蓋文字。`StatusPill / 停止` 已刪除，勿重建。
- **D6.a（結束確認 dialog）已刪除**，不要重建；結束路線無確認。
- R08（Setup 與 App 不相符）、D23（檢視路線 sheet）、R07 icon 已完成，不要重做（只在票單要求時微調）。
- 外緣內容距 frame 16 pt（地圖、系統列、鍵盤、全螢幕 overlay 例外）；間距用 8／12／16／24。
- 文字一律綁 `Theme/*`（字級表見 `IOS-TYPOGRAPHY.md`），顏色綁 Light Theme token；icon 只用 `0 · 共用元件（Icon）` 的 `icon/*`。

- **浮動控制項（H 系列）**：地圖控制鈕、Speed chip、icon 按鈕底色一律用 `surface/control/floating`（Light＝近白，Dark＝control）。CS token 與共用 master（Light／Dark）已由 Claude 改好，Luna 只處理票單 H-01～H-03、H-07（Light 部分）；H-06 為 Dark，Light 驗收後才做（frame 內手刻副本與 override），H-04 需使用者決策、不要先改。

### 4. 執行順序
1. **G 系列**（共用元件／token 綁定）：G01 Map/Base 元件化、G02 Status Bar 元件＋移除 Home indicator、G03 Speed chip、G04 Permission/Role/Preset/ActionSheet/Group row 等、G05（E 區頂卡已修，D 區確認即可）、G06 Overlay/Dim 與底層母畫面（D12、D14、D16、C2、D20、E3、F6.a）、G07 TextField/Label、G08 清空「未定義」、G09 Button/Icon 尺寸 variant、G10 Typography 補洞。
2. **A → B → C → D → E → F 逐 frame 票**（票單表格每列一張票：問題、替換項目、驗收）。
3. 每完成一個 section，截圖回歸，再進下一個。

### 5. 每張 frame 的驗收（缺一不可）
- 用 `figma_capture_screenshot` 看過改後畫面（必要時放大），確認未破版、無文字被裁切／遮擋。
- 逐張讀回：`textStyleId` 全綁 `Theme/*`（9:41 系統時間與原生鍵盤示意除外）；所有 fills／strokes 綁 `GoFly iOS / Light Theme`（無裸色、無 `legacy`）；一般內容外緣距 frame 16 pt。
- instance 清單核對：按鈕／pill／toast／searchbar 等皆為共用元件 instance，不留同名手刻副本。
- 不得有新增的 Dark collection 綁定、不得改到其他 frame。
- 結果寫回 `docs/FIGMA-LIGHT-UI-TICKETS.md` 的「執行狀態」（逐票標已完成／未完成／阻礙），並在 `docs/FIGMA-UI-RECONCILIATION.md` 以日期條列變更（區分 Figma 設計更新、App 行為、裝置驗證；本任務**無** App 與裝置驗證，須明講）。

### 6. Figma Plugin API 注意事項（已踩過）
- `documentAccess: dynamic-page`：取 instance 的 master 用 `await node.getMainComponentAsync()`，取 variable 用 async 版本。
- `vectorPaths` 只接受 `M L C Z`，不可用 `H V`；vector 位置是 bbox 左上角，注意 `clipsContent`。
- 改 instance 文字：先 `figma.loadFontAsync(node.fontName)` 再設 `characters`；直接改 variant master 前先確認沒有不該連動的 instance。
- 綁 token：`figma.variables.setBoundVariableForPaint(paint, 'color', variable)` 後整個寫回 `node.fills/strokes`。
- 刪除前先確認沒有 instance 引用；不確定就放進 `未定義`。
- 一次只改一個 section，改完立刻截圖；失敗要清掉半成品 frame（避免殘留 `R08 ·` 之類重複圖層）。

### 7. 回報格式
完成後回報：① 已完成票號清單；② 未完成／阻礙票號與原因；③ 需要使用者決策的問題（每題一句）；④ 變更過的 node id 清單；⑤ 明確聲明「未修改 Variable／色票板／Dark／App，未 commit」。
