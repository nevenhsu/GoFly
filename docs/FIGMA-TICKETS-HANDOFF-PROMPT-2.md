# Handoff prompt #2：Light UI frame 第二輪（給 GPT／Luna）

> 把「Prompt」整段貼給執行的 AI。第一輪規則與禁止事項沿用 [FIGMA-TICKETS-HANDOFF-PROMPT.md](FIGMA-TICKETS-HANDOFF-PROMPT.md)，本文件只寫**增量**。票單：[FIGMA-LIGHT-UI-TICKETS.md](FIGMA-LIGHT-UI-TICKETS.md)；現況：[FIGMA-UI-RECONCILIATION.md](FIGMA-UI-RECONCILIATION.md)。

---

## Prompt

你是 GoFly iOS 的 Figma UI 執行者，這是**第二輪**。請先完整讀 `docs/FIGMA-TICKETS-HANDOFF-PROMPT.md`（第 1–7 節的範圍、禁止事項、已定決策、Plugin API 注意事項、驗收與回報格式**全部照舊**），再讀本文件。只用 Figma Console（Desktop Bridge）。

### 0. 第一輪結果（Claude 已抽查，屬實）
- 已完成並讀回：Light A–F 66 張 393×852 frame，64 張有 `System / StatusBar` instance、Home indicator 已全部移除（0 個殘留）、28 張地圖 frame 用 `Map / Base`、0 個未綁定填色；Variable 數量未被改動（Light 87、Dark 87、Common 14）；Dark 未動。
- Claude 在第一輪之後**已自行完成**（不要重做、不要還原）：
  - CS／色票：Light 無純白表面（canvas `#EEEEF3`、card／floating `#FBFBFD`、control `#DEDEE4`、active `#B9B9BF`），新 token `surface/control/floating`（Light＝card、Dark＝control `#3A3A3C`）；`Recenter`、`FitRoute`、`Button / Speed chip` Default、`Button / Icon` Standard／Route Enabled 已綁 floating（Light／Dark master）。
  - D-05：D6.a 孤立說明文字（Light `222:16535`、Dark `222:16634`）已刪除。
  - R08、D23、R07 icon、StatusPill 停止刪除、E 區頂卡、F3 Toast／Snackbar master。

### 1. 本輪範圍（Light 為主）
禁止事項不變：不改 Variable／collection、不改色票板、不改 section 底色／標題、不動 Dark frame、不加 prototype、不改 App、不 commit。
**本輪例外（使用者已授權）**：可以**調整共用元件 master 的結構**，僅限 G11（Slider）；可在兩個 `Light · 0 · 共用元件` section 新增元件。

### 2. 本輪票（依序執行）

**P0 · 先處理剛發現的問題**
1. **G11 · Slider／Input 自適應寬度共用元件 — 已由 Claude 完成，Luna 不要重做**
   - `Light · Slider / 原生黑白`（`313:30644`）與 `Dark · Slider / 原生黑白`（`313:30746`）改為 **Component set**，variant 屬性 `Value`＝0…100（每 5 一檔，共 21 個）；軌道與已走軌道用 SCALE constraints，Thumb 放在 `Thumb zone`（SCALE）內置中，所以 instance 任意改寬度時進度比例不變。
   - D7（`158:6131`）、E3（`158:6503`）Light 已改用 `Value=20` instance（寬 361，Min／Max 為獨立文字）。**Dark D7／E3 尚未替換**（Light 驗收後另票：Dark 用 `313:30746` `Value=20`）。
   - `Text Field / Neutral`（Light `268:22284`、Dark `249:16574`）六個 variant 改為 **Auto Layout**（左右 padding 14／16、icon 與文字間距 4，文字區 Fill container、Focused 游標緊貼文字），寬度可任意拉伸；`SearchField`（normal／focused／Compact）與 `SearchBar` 以 constraints 左右拉伸、貼上／清除／設定固定靠右、placeholder 單行截斷。實測 361／280／260／220 寬皆正確，B3／B4／D5 原本「輸入框右緣被裁切」已因此消失。
   - Luna 只需：在 frame 內使用 instance 時**不要再手動設定內層寬度**；若發現任何 frame 的搜尋欄／輸入欄還是固定寬度的手刻副本，改為 instance 並拉到內容寬度。
2. **D10 面板泛藍（H-02）**：D10（`193:9158`）的 `Panel / 執行模式控制`（`238:9223`）、FitRoute、Recenter、「來回／方向」手刻按鈕全綁 `map/route`（`#33608F`），整塊深藍。Panel 改 `surface/card`；FitRoute／Recenter reset overrides（回 `surface/control/floating`）；panel 內「結束」「繼續」改 `Light · Button / Text` Neutral／Primary instance。與 D10.a（`238:9101`）僅差頂部 toast。
3. **B3／B4（`121:51543`／`121:51632`）**：① 輸入框修正後，B3 右側同時出現「貼上」與「清除 ✕」重疊（B3 為空輸入，空輸入時只應顯示貼上、不顯示 ✕；有輸入文字時顯示 ✕、隱藏貼上）→ 依狀態只顯示一個；② **半灰半白**：截圖顯示上半灰、下半白，疑似搜尋結果區塊與 canvas 色階不一致（card `#FBFBFD` vs canvas `#EEEEF3`）。核對底層 frame／鍵盤區／結果區的綁定，統一為「頁面底＝canvas、列表區＝card」其一，並回報採用哪種。
4. **7 個未綁 Theme 的文字層**（讀回：A–F 內除 `9:41` 外仍有 7 個 `textStyleId` 為空）：列出並補綁 `Theme/*`。

**P1 · 浮動控制項（H 系列，使用者要求近白）**
- **H-01** D6（`121:52798`）、D7、D10、D10.a：手刻 `Button / icon / 來回｜方向`（36×36，底 `#D1D1D6`＋黑描邊）→ `Light · Button / Icon` instance（Type Route／Standard，最接近 36 的尺寸；若無 36，用 Medium 40 並回報），圖示 `icon/repeat`、`icon/direction-forward`；移除手刻副本。
- **H-03** D8、D9、B10、D10.a 的 `Recenter`／`FitRoute` 有 local override（底綁 `surface/control`），Reset overrides。
- **H-07** 掃描 Light frame 內其他仍直接綁 `surface/control`／`control/active` 的浮動控制項，改綁 `surface/control/floating`（或 reset）。
- **H-04（需使用者決策，先不要改）**：Neutral 按鈕與 Progress 軌道是否也近白。
- **H-05**：只核對 B3／B4／D5／C1–C4／D19–D22 輸入欄底色是否近白，回報清單。

**P2 · 第一輪未完成的 frame 票（逐票照票單表格；已完成的不要重做）**
- 共用：G04（Group row variants：With value／With chevron／Status）、G09（icon 控制替換）。
- A：A-01–A-07。B：B-02–B-04、B-08–B-09。C：C-01（黑色實心圓改 icon＋淺底圓）、C-02、C-04。D：D-01–D-04、D-09、D-11–D-16。E：E-01、E-04、E-05（見下）、E-07。F：F-01、F-04–F-06。
- 每個 section 完成後截圖回歸；列表／設定列優先元件化（`List rows`、`Group row`）。

**P3 · 使用者已決定（照做，不要再問）**
- **G08-1／G08-2（兩個待確認顏色）**：`#1C1C1E` 執行提示底色（5 個 paint）與 `#6B6B73` dialog 說明字（1 個 paint）**都捨棄**，一律改用現有 CS token，不新增 token、不保留裸色、不再放「未定義」。
  - 把這 6 個 paint 所在的元素找出來，依用途改綁現有 Light Theme token：執行提示卡底色 → `surface/card`（疊地圖用 `surface/overlay/card`）；其上文字 → `text/primary`／`text/secondary`；dialog 說明字（D6.a 已刪，若為孤立副本）→ 直接刪除該副本與其色票。
  - 清空「未定義」區的「色彩待確認」兩組色票（`未定義 · 執行提示卡底色`、`未定義 · Dialog 說明字色` 及其 label／hex）。
- **E-05（暫停提示）**：**保留 `Top / 執行指示`（Paused）與 warning Toast 兩者**，不要移除任何一層。E5（`193:9287`）Light 維持現狀：頂部 Paused Top＋其下 warn Toast（含「繼續」）；只需確認兩者皆為共用元件 instance、間距 8 pt（Top 在 y=58，Toast 緊接其下，互不重疊）、文字綁 `Theme/*`。同樣原則套用到 B8／B9／D10：既有的「pill＋Toast＋Top」組合不要拆。（此決定取代上一版「同時只顯示一層提示」的建議；票單 E-05 驗收條件同步改為「Top 與 Toast 皆保留、不重疊」。）

### 3. 驗收與回報（照第一輪）
每張 frame：截圖讀回、`textStyleId` 全綁 `Theme/*`（9:41 與原生鍵盤除外）、fills／strokes 全綁 Light Theme／Common Color token、外緣距 16 pt、控制項皆為共用元件 instance。結果寫回票單「執行狀態」與對照文件（區分 Figma 設計更新／App／裝置驗證，並聲明本輪無 App 與裝置驗證）。回報：① 已完成票號 ② 未完成與原因 ③ 需使用者決策（每題一句；P3 兩題已決定，不必再列）④ 變更的 node id ⑤ 聲明「未修改 Variable 定義／色票板／Dark frame／App，未 commit」。

## Dark 共用元件對齊 Light（2026-10-29，Figma 設計更新；無 App／裝置驗證）

- `Dark · 0 · 共用元件（按鈕）`、`Dark · 0 · 共用元件` 的 board 已以 Light board 為準重建（版面、元件集、Size 軸、新增元件全部同 Light），所有填色／描邊／陰影由 Light Theme token 逐名對應到 Dark Theme token；元件名稱 `Light ·` → `Dark ·`，board 底色／圓角沿用原 Dark。
- Dark A–F 內舊元件 instance 已全數換成新元件（共 168 個，含巢狀 Checkbox 2 個）；舊 board 已刪除。
- Slider thumb 在 Dark 綁 `color/icon/primary`（Light 綁 canvas 會與 Dark 底同色）。
- 待查：Light 按鈕板的 `Button / Icon` 巢狀 `Icon/Settings/Enabled`、`Location · Favorite／Copy Icon` 主元件不在本頁（沿用原指向，未對應 Dark）。

## Dark A–F frame 對齊 Light（2026-10-29，Figma 設計更新；無 App／裝置驗證）

- Dark A–F 各 section 的 frame、說明文字、section 內容已以 Light A–F 為準重建（Light 為準：多餘的 Dark frame 刪除、缺少的補上，例如 Dark F 多出的 2 張、D9 已移除）；Light 色彩 token 逐名對應 Dark Theme token，instance 全數指向 `Dark ·` 共用元件。
- 例外：D2.a `Row / 拖曳中（台北 101）` Light 為未綁定白底，Dark 改綁 `surface/control`；地圖 pin 白點（Ellipse）沿用 Light 的未綁定值。
- 每個 section 的標題保留 `Dark · ` 前綴。

## Dark Color Scheme 重新分階（2026-10-29，Figma Dark Theme token 更新；Light 未動；無 App 驗證）

階梯：canvas `#0B0B0D`（2026-10-29 由 `#050506` 微調亮） → 第 2 階 `#1A1A1C`（card／navigation／overlay card、sheet、tab-panel；即 Tab、Sheet、info card）→ 第 4 階 `#2C2C2F`（control／input／secondary action／overlay panel／floating；即 sheet 上的 Button 與 list）→ 第 7 階 `#48484D`（control/active；active、focused）。連動：`map/canvas` `#131315`、`surface/control/disabled` `#242427`、`line/separator` `#48484D`；`surface/input` 與 `action/secondary/surface` 改 alias `surface/control`。status 底色未調整，待看新底色後決定。App 端色值尚未同步。
