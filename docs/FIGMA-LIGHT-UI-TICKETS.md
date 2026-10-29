# Light UI 逐 frame 優化票單（交 GPT 執行）

原始盤點日期：2026-10-28。範圍：Figma 04 · iOS Redesign 的 **Light** A–F；目前為 64 張 App frame（A8、B11、C4、D25、E7、F9）＋ F2／F3 兩張規則參考。Dark 不在本輪；Light 驗收後以同一份票單比照 Dark。
資料來源：Figma Desktop Bridge 逐 frame 讀取（instance 清單、未套 Typography 的文字層、手刻控制項、座標）＋各 section 渲染截圖。**「已量測」＝由圖層資料確認；「目視」＝由截圖判讀。** 本文件保留原始票單並記錄 Figma 執行狀態；App 未修改。

## 執行規則（所有票共用）

1. 視覺準據為 04 現行渲染；只改 Light，不碰 Dark、不加 prototype、不新增 Color Theme token（找不到語意角色的顏色放「未定義」討論）。
2. 外緣內容距 frame 16 pt（地圖、系統列、鍵盤、全螢幕 overlay 例外）；統一 8 pt grid（間距 8／12／16／24）。
3. 文字一律綁 `Theme/*`（字級表見 [IOS-TYPOGRAPHY.md](IOS-TYPOGRAPHY.md)），色綁 `GoFly iOS / Light Theme`（語意 token 見 [IOS-COLOR-SCHEME.json](IOS-COLOR-SCHEME.json)）；icon 只用 `0 · 共用元件（Icon）`。
4. 每張改完：截圖讀回、`instance` 清單核對、`textStyleId` 全綁、無 unbound paint；改完同步 [FIGMA-UI-RECONCILIATION.md](FIGMA-UI-RECONCILIATION.md)、[IOS-UI-DESIGN.md](IOS-UI-DESIGN.md)。
5. 先做 G 系列（共用元件／token），再做各區 frame 票，否則會重工。

## 放大確認紀錄（2026-10-28，1:1 截圖）

已確認屬實：B3／B4／D5 搜尋欄右緣被裁切（清除 ✕ 半截、貼上 icon 貼邊）；C1（及 C4、D5、D19）列左側為黑色實心圓；E2.a（及 E4、E5）頂卡只有「A」箭頭、無標題副標；E2 頂卡黑方塊＋近白字不可讀、「停止漫步」文字貼邊；D6.a 已由使用者刪除（不再需要「確認結束」dialog），僅剩孤立說明文字 `222:16535`。

## 原始全檔現況數據（2026-10-28 執行前盤點）

| 項目 | 數值 |
| :-- | :-- |
| Light App frame | 62（A 7、B 11、C 4、D 24、E 7、F 9）＋F2／F3 參考 |
| **D6.a 已移除** | 使用者 2026-10-28 刪除 D6.a（確認結束 dialog），結束路線不再有確認；Light D 區現為 24 張，孤立說明文字 `222:16535` 待刪，文件與規格需同步（見 D-05） |
| 未套 Theme 的文字層 | 每張地圖畫面 3 個（中山區 13、大同區 13、淡水河 12）、每張 1 個 9:41（17）、B3／B4／D5 各 1 個「確認」（16）、F2 20 個、F3 7 個 |
| `color/palette/*` 仍被使用 | `3c3c43-3c3c43` 66 次（Home indicator）、其餘 3 個各 1 次 |
| 「未定義」區待處理 | 20 組元件副本＋2 組色票（見 G08） |

---

## G 系列：共用元件／token／Typography 票（先做）

### G01 · 地圖底圖元件化（Map / Base）
- **現況**：B／D／E 共 28 張地圖畫面，各自手刻道路、建築、公園、水域，且各有 3 個未套 Theme style 的地圖標籤文字（中山區、大同區、淡水河）。
- **做法**：建 `Map / Base` 元件（顏色全綁 `color/map/*`；標籤文字套 `Theme/caption`／`Theme/footnote`＋`color/map/label-area`／`label-water`），所有地圖畫面改 instance，地圖上的 route、pin、箭頭疊在上層。
- **驗收**：36 張畫面的 `textStyleId` 空值僅剩 9:41；改 `color/map/*` 一次連動全部。

### G02 · System 元件：Status Bar／Dynamic Island；Home Indicator 用系統內建
- **現況**：62 張皆手刻；9:41 文字無 style；Home indicator 66 處綁 `color/palette/3c3c43-3c3c43` 裸 palette。
- **做法（2026-10-28 使用者決定）**：Home indicator **一律用系統內建**，不自訂：刪除 Light 62 張內手刻的 Home indicator 圖層（含 sheet 內指示條 65 個，原綁 `color/palette/3c3c43-3c3c43`），改由 iOS 裝置框／系統元件呈現；內容底距依安全區（下緣 34 pt）預留。Status Bar 建 `System / StatusBar` 元件，時間字標註為系統字。
- **驗收**：Light 無自訂 Home indicator 圖層、無 `color/palette/3c3c43-3c3c43` 引用；內容未被安全區遮擋；Status Bar 為 instance。

### G03 · Speed chip 共用元件
- **現況（已量測）**：手刻 `Speed chip` 出現在 D6、D7、D10、D10.a、E1、E1.a、E2、E2.a、E3、E4（名稱有「無單位」「Speed chip」兩種）；D6 顯示「9」、E 區顯示「25」。
- **做法**：建 `Button / Speed chip`（icon/speed + 數字 + chevron，高 36，字 `Theme/subheadlineEmphasis`），variant：Default／Disabled。
- **驗收**：10 張全改 instance；數字文字覆蓋，不改尺寸。

### G04 · 角色／權限／預設選項類元件
- 手刻清單（已量測）：`Role chip`（D5）、`Permission status`（R02、R03、R04、R06、R07；同時「未定義」已有 neutral／success 兩款）、`Preset / 5·25·50·100`（D7、E3）、`ActionSheet / 取消`（D12）、`Group / *` 設定列（F1、F1.a、F4、F5、F6、F6.a）、`Button / secondary`、`Button / primary / …`（D10）。
- **做法**：
  - `Permission status`（R02／R03／R04／R06／R07 的「目前權限」「尚未連線」「尚未配對」）→ **直接用 `Light · StatusPill / 啟動`（灰點中性 pill）instance 並覆蓋文字**，不新增 Neutral variant；R03 的「已允許」綠點款改用 `StatusPill / 模擬中`（綠點）覆蓋文字。R03 現為寬 244 的獨立膠囊，改標準 pill 高度 30、寬度隨文字。
  - **（2026-10-28 使用者決定）** `Light · StatusPill / 停止` 與 `/ 啟動` 樣式完全相同（灰點、`surface/card`、`line/border`），已刪除 Light `停止` master（無 instance 使用）；需要顯示「停止」時用 `StatusPill / 啟動` 覆蓋文字。Dark `Dark · StatusPill / 停止` 同樣重複，已一併刪除（無 instance 使用）。
  - `Chip / Preset`（Default／Selected）。
  - `ActionSheet`、`Group row`（Default／With value／With chevron／Status）。
  - D10 的 secondary／primary 改 `Light · Button / Text` 或 `Icon + Text` 既有 variant，不留 56 pt 專用手刻。
- **驗收**：上列畫面不再有同名手刻 frame；「未定義」區對應副本移除。

### G05 · Top／執行指示元件修復（影響 D6、D10、D10.a、E2、E2.a、E4、E5）
- **現況（已量測＋目視）**：共用 `Light · Top / 執行指示[2]` 存在，但 E2 實際是手刻 `Top / 漫步指示`（361×72）；E2 左側為**黑色方塊**、標題「前往 中山公園」與副標為**近白字在淺底上，幾乎不可讀**；E4 頂卡只剩一個「A」形箭頭 glyph，無標題與副標；E5、E2.a 頂卡也只有「A」。D6 則正常（黑箭頭＋標題＋副標）。
- **做法**：E2／E4／E5／E2.a／D10／D10.a 統一改 `Light · Top / 執行指示`（Active／Paused）instance，icon 用 `icon/nav`，標題 `Theme/headline`＋`color/text/primary`，副標 `Theme/footnote`＋`color/text/secondary`；E4 若要隱藏頂卡需有設計理由，否則補回內容。
- **驗收**：6 張頂卡與 D6 同一元件、文字對比 ≥ 4.5:1。

### G06 · Modal／Overlay／Dim 規則
- **現況**：D12（動作選單）、D14（系統分享）底層為**純黑滿版**；D16 底層空白白；C2、D20、E3、F6.a 的 sheet 上方是**空白白底**（沒有地圖或列表作底層）。
- **做法**：建 `Overlay / Dim`（黑 40%）元件；sheet 類畫面的底層放對應母畫面截圖層（C2→C1、D20→D19、E3→E2、F6.a→F5／F6、D12／D14→D11、D16→D11）。
- **驗收**：所有 sheet／選單畫面上方可見母畫面＋Dim，無純黑／純白空洞。

### G07 · 輸入欄位語意：SearchField vs TextField
- **現況（已量測）**：C2 的「標籤」輸入、D20 的路線名稱輸入都用 `SearchField / normal`（含搜尋 icon＋貼上 icon），語意是搜尋不是標籤輸入。
- **做法**：以 `Text Field / Neutral` 建 `TextField / Label`（無搜尋 icon、右側 Clear），C2、D20 改用；`SearchField` 只保留搜尋情境。
- **驗收**：C2／D20 無搜尋 icon、有 placeholder 與 Clear。

### G08 · 清空「未定義」區
- 20 組元件副本＋2 組色票逐項決議：納入共用（G03／G04／G07 已涵蓋 Permission status、Steps card、NavBar、BottomSheet、Favorite Row、Service card、LocationCard 獨立、Controls row、StatusPill 連接中、各文字／停用／paste 按鈕）、或確認為單一用途後保留。
- 色彩待確認兩項：執行提示底色 `#1C1C1E`（5 paint）、dialog 說明字 `#6B6B73`（1 paint）→ 決定語意角色（建議對應 `color/surface/…` inverse／`color/text/secondary`），**不新增 token**。
- **驗收**：「未定義」區只剩有決議的項目；來源畫面已改 instance。

### G09 · `Light · Button / Icon` 尺寸 variant 補完
- D 區星號／grip／close 等手刻比例不一（見 D1、D2、D9）。補 `Size=Medium 36`、`Large 44`，圖示 20／22 規格寫入 description。
- **驗收**：D1／D2／D9／D19／D21 的 icon 按鈕皆為 variant instance，命中區 ≥ 44。

### G10 · Typography 補洞
- F2（20 層）、F3（7 層）規則參考頁文字全未套 style → 套 `Theme/title`、`headline`、`subheadline`、`footnote`。
- 「確認」16 pt（B3、B4、D5）→ `Theme/button/medium`；若為 pill 內文字改 `Theme/subheadlineEmphasis`。
- **驗收**：除 9:41 與原生鍵盤外，Light 內無空 `textStyleId`。

---

## A · 啟動與首次引導

通用觀察（目視）：R01–R07 垂直版型各不相同——標題位置、步驟指示（R02–R06 頂部 3 段條）、底部 CTA 高度不一致；主標未統一用 `Theme/display`，副標未統一 `Theme/subheadline`＋`color/text/secondary`。

| 票 | Frame | QA（問題） | 替換項目 | 驗收 |
| :-- | :-- | :-- | :-- | :-- |
| A-01 | R01 `121:51102` | 目視：Logo 方塊與底部 loading 條關係鬆散，Logo 黑星未用 token；9:41 無 style。 | Logo 色 → `color/icon/primary`；loading 用 `Progress` 元件（已用，確認色綁 `color/action/primary/surface`）；Status／Home → G02。 | 垂直置中、無裸色。 |
| A-02 | R02 `121:51131` | 底部「允許定位」藍＋「略過」灰兩顆**垂直堆疊且貼近底緣**，距 Home indicator 間距不足；`Permission status` 為手刻 158×30；圖示卡 76×76 非 token。 | 兩顆 → `Button / Text` Primary Large＋Neutral Large，間距 12、底距 ≥ 34（含安全區）；狀態 → G04 StatusPill Neutral；標題 `Theme/display`。 | CTA 底距一致、pill 為 instance。 |
| A-03 | R03 `123:62048` | 狀態膠囊寬 244，比 R02 的 158 寬，兩頁切換時跳動；CTA 只有單顆「下一步」，與 R02 位置不同。 | StatusPill Success；CTA 位置對齊 R02 主按鈕；去掉 R02／R03 差異性版型。 | R02↔R03 僅文字／icon／pill 變化。 |
| A-04 | R04 `121:51246` | 步驟卡（編號圓＋文字）為手刻，卡內分隔線與左欄對齊不穩；「連線說明 ›」是文字連結，命中區小；「尚未連線」pill 手刻；步驟條與 R05 風格不同。 | Steps card → G08（未定義已有副本）轉共用元件；連結用 `Button / Text`（Tertiary）高 44；pill → G04。 | 卡內 padding 16、分隔 `color/line/separator`、命中 ≥ 44。 |
| A-05 | R05 `123:56962` | 為純說明頁，使用返回＋標題導覽列（與 R02–R04 步驟條列不同）；四步標題／副標與下方「仍然無法連線？」兩區間距不均；底部藍按鈕。 | NavBar → G08 共用 NavBar；區段標題 `Theme/headline`、說明 `Theme/footnote`；列表列用 `List rows`。 | 行距／區距 24；返回為 icon 元件。 |
| A-06 | R06 `222:10410` | **VPN 失敗版缺步驟卡樣式**：與 R04 同內容但步驟沒有編號圓、沒有灰底卡（目視），像另一個版型；toast 緊貼步驟列、與頂部條間距小。 | 內容區複用 R04 的 Steps card instance；Toast 已為 instance，檢查 361 寬＋左右 16；pill → G04。 | R06 = R04 + toast，版面其餘完全相同。 |
| A-07 | R07 `222:11858` | **無任何共用元件**；Hero icon 為黑色圓角方塊內藍矩形（占位感）；標題用 `連接 Mac 完成配對`，文案層級同 R02；無底部 CTA（文件註記刻意移除）。 | Hero → 改用 `icon/phone`＋Mac 圖示組合（Icon 目錄新增 `icon/mac` 或沿用 `icon/phone`），色綁 `color/icon/*`；pill → `Light · StatusPill / 啟動` instance，文字覆蓋「尚未配對」（G04）；標題／副標套 Theme。 | 與 R02 垂直節奏一致（圖示 y、標題 y、副標 y 相同）。 |

## B · 地圖首頁、搜尋、地點 sheet、瞬移

通用觀察：B1–B11 地圖＋SearchBar＋StatusPill＋TabBar 皆為 instance（良好）；問題集中在**全螢幕搜尋、疊層重疊、sheet 資訊密度**。

| 票 | Frame | QA（問題） | 替換項目 | 驗收 |
| :-- | :-- | :-- | :-- | :-- |
| B-01 | B1 `121:51314` | 收合 sheet 的「目前模擬位置」卡右側星號／複製按鈕在小尺寸且底距緊；sheet 標題「中山北路二段 45 號」`Theme/title`。 | Map/Base（G01）；Home／Status（G02）；星號、複製已為 instance，確認 44 pt 命中。 | 與 B2 收合版 1:1。 |
| B-02 | B2 `121:51416` | 半開 sheet 的「最愛地點」列：左 icon 星、右側 100 m 距離，與全域 list row 不一致；「查看全部」文字連結小。 | List rows instance；連結 → `Button / Text` Tertiary。 | 列高 56、分隔線內縮對齊文字。 |
| B-03 | **B3 `121:51543`** | **已量測 bug**：`SearchField / focused` instance 寬 321，但內層 `Text Field` 固定 361 → 輸入框右緣被裁切、清除／貼上區塊跑出右邊（截圖右側出現半截線）。次要：「確認」16 pt 無 Theme；history icon 18 pt 與文字間距不均。 | SearchField 內層 Text Field 設 Fill container；「確認」→ G10；歷史列 → `List rows`（icon/history）。 | 右緣距 frame 16、無裁切。 |
| B-04 | **B4 `121:51632`** | 同 B-03 的右緣裁切；結果列（icon/pin 18 pt＋2 行文字）與 B3 列高不同；「前往座標」主列字級／色階與附近地點列未區分。 | 同 B-03；結果列統一 `List rows` 兩行 variant（主 `Theme/body`、副 `Theme/footnote`＋`color/text/secondary`）。 | B3／B4 列高、左欄對齊一致。 |
| B-05 | B5 `121:51730` | 地點 sheet 浮於 TabBar 上方，Go pin 氣泡與地圖 pin 被 SearchBar／pill 擠；LocationCard 左下「Go」藍膠囊太小（高 ~32），與 Button 尺寸表不符；卡上關閉 ✕ 命中小。 | Go → `Button / Map Pin · Go`（已用）改正式 Large／Medium variant；✕ → `Button / Icon` Medium；LocationCard 保持 instance。 | Go 高 ≥ 40、✕ 命中 44。 |
| B-06 | B6 `121:51860` | Snackbar 浮在 sheet 上緣，**覆蓋「目前模擬位置」小標題**（目視）；成功訊息「已移至 台北車站」。 | Snackbar 位置：距 sheet 上緣 8 pt，不遮內容；確認 Snackbar 2 秒自動消失款色 token。 | 無文字被遮。 |
| B-07 | B7 `121:51967` | Toast（danger）下方 Go 氣泡與 pin 被切（目視：pin 頂端被 toast 遮）；StatusPill 連線中斷紅點正確。 | Toast 位置固定 y=156；地圖 pin 位置下移 ≥ 24，避免與 toast 重疊。 | pin、氣泡完整可見。 |
| B-08 | B8 `193:9013` | 暫停 toast 與 StatusPill「已暫停」疊置，間距 8 OK；底部 sheet 無 Resume CTA（刻意）。RealArrow 藍色＋pin 並存，視覺密。 | Toast warn instance 確認；地圖元素分層。 | 與 B9 版型一致，僅箭頭／標題文字差異。 |
| B-09 | B9 `202:10090` | 與 B8 幾乎相同，僅差「最後模擬位置」與灰箭頭。 | 同 B-08；兩張合併為同母版＋覆蓋。 | 一個母版兩個覆蓋。 |
| B-10 | B10 `222:11656` | Toast danger 橫向 x:16；StatusPill 仍顯示「模擬中」與「需要連接 Wi-Fi」矛盾（目視：pill 綠點「模擬中・中山區」）。 | StatusPill 改 `錯誤`（Error，紅，使用者已決定）；toast 文案不變。 | pill 為紅點「錯誤」，與 B7 一致。 |
| B-11 | B11 `239:15137` | `StatusPill / 連接中` 無共用 variant（在「未定義」）；pill 為白底無 dot，字級與其他 pill 不同；無 Dark 對應。 | G04：StatusPill 新增 `連接中`（含 spinner／灰點）；文字 `Theme/footnoteEmphasis`。 | pill 為 instance；補 Dark 另立票。 |


## C · 最愛地點

| 票 | Frame | QA（問題） | 替換項目 | 驗收 |
| :-- | :-- | :-- | :-- | :-- |
| C-01 | C1 `121:52111` | **列左側為黑色實心圓**（占位感，未見星／pin icon；文件稱「純 icon」）；「⋯」與右緣距 16 OK；列高 54 與 B2 列不同；Snackbar 與底部搜尋欄間距緊（僅 ~8）。 | 黑圓 → `icon/star`＋`color/icon/primary`（或 `icon/pin`）置於 32 pt 淺灰圓底；列 → `List rows`；Snackbar 距搜尋欄 12。 | 無純黑圓；列高統一 56。 |
| C-02 | C2 `121:52228` | **上半部整片空白**（G06）；「標籤」欄為 SearchField（含搜尋 icon＋貼上 icon，且 placeholder 寫「搜尋最愛地點」）→ 語意錯誤（G07）；「取消／刪除」文字按鈕字級小；儲存藍鈕距底緣 ~34 OK。 | 底層用 C1＋Dim；欄位 → `TextField / Label`（placeholder「標籤」）；取消／刪除 → `Button / Text`（Neutral／Danger）。 | 欄位無搜尋 icon；上方可見 C1。 |
| C-03 | C3 `121:52367` | 多選圈未選／已選（已為 `Button / Check`，良好）；列文字起點 x:43 與 C1 的 x 不同屬刻意；「刪除（2）」紅鈕全寬 361 OK，與底部搜尋欄間距 ~12。 | 刪除鈕 → `Button / Text` Danger Medium instance（48 pt，符合 04 現行渲染）；確認 `color/action/danger/surface`。 | 與 D21 刪除鈕 361×48 尺寸／位置一致。 |
| C-04 | C4 `121:52464` | 與 C1 同黑圓問題；Snackbar「復原」按鈕為 pill 手刻外框（目視比 Snackbar variant 大）。 | 同 C-01；Snackbar 可復原款 instance 檢查按鈕高 32。 | 與 C1 僅 Snackbar／列數差異。 |

## D · 路線

通用觀察：D 區 24 張。母畫面 D1–D4／D8／D9 的 route panel 為手刻（Panel、點位列、grip、關閉按鈕），D 區 icon 按鈕尺寸不一。

| 票 | Frame | QA（問題） | 替換項目 | 驗收 |
| :-- | :-- | :-- | :-- | :-- |
| D-01 | D1 `121:52566` | panel「規劃路線」標題＋星＋folder icon 排列緊；兩個點位列（起點／終點）為手刻輸入列，grip／close icon 尺寸 18/20 混用；「新增停靠點」／「檢視路線」為純文字。 | 建 `RoutePanel`、`Route / Stop row`（Default／Selected／Dragging）；icon → G09；文字鈕 → `Button / Text` Tertiary。 | 3 種狀態（D1／D2／D9）共用 Stop row。 |
| D-02 | D2 `222:11484`／D2 拖曳 `309:27349`／D3 `193:8857`／D4 `193:8693` | 同 D-01；D3 收合 76 pt 與 B1 收合不同高度規則（記錄）；D4 LocationCard 與 B5 為同一元件（良好）但按鈕尺寸需同 B-05。 | 同 D-01；D4 Go → B-05 規格。 | 四張共用 RoutePanel。 |
| D-03 | D5 `121:52709` | 「Role chip」手刻 124×30（正在選：終點）；Favorite 星＋文字手刻；「清空記錄」文字鈕；鍵盤區為灰塊占位；**搜尋欄右緣被裁切（2026-10-28 放大確認：✕ 只剩半截）**；「最近搜尋」列左側為黑色實心圓（同 C-01）。 | Role chip → G04；Favorite → `Button / Icon + Text`（Tertiary）；清空記錄 → `Button / Text`；SearchField 同 B-03。 | Chip 為 instance；右緣 16。 |
| D-04 | D6 `121:52798` | 頂部導航卡正常；Speed chip 手刻「9」且樣式與 E 區「25」不同；底部 panel 的來回／方向 icon 鈕為 `Controls row`（未定義）；「結束」灰鈕與「暫停」藍鈕等寬比不均（目視 1:2）。 | Speed chip → G03；Controls row → G08；兩顆主按鈕 → `Button / Text` Neutral Large＋Primary Large，比例 1:2 寫入規格。 | 與 D10.a 僅狀態差異。 |
| D-05 | **D6.a 已刪除（清理）** | 不補 frame。清理：刪除孤立說明文字 `222:16535`；Dark D6.a 同步刪除；[IOS-UI-DESIGN.md](IOS-UI-DESIGN.md)、[FIGMA-UI-RECONCILIATION.md](FIGMA-UI-RECONCILIATION.md)、[ROUTE-MODE-TASKS.md](ROUTE-MODE-TASKS.md) 內「D6.a／結束確認浮窗／防誤觸結束」改為「結束路線直接結束、無確認」，並與 App 行為對照（App 目前是否仍有確認需另查）。 | 無新元件；不再需要 `Dialog / Alert`。 | Figma 與規格無 D6.a 殘留；D 區計數改 24（Dark 24）。 |
| D-06 | D7 `158:6131` | 底層 D6＋Dim＋sheet；4 個 Preset 手刻 82×40 且 icon 為彩色 speed/*；slider 為 `Slider`；「完成設定」藍鈕。 | Preset → G04 `Chip / Preset`；Slider 確認 token；按鈕 instance。 | 與 E3 sheet 完全一致（同元件）。 |
| D-07 | D8 `222:10536`／D9 `222:10849` | Toast／Snackbar 已 instance；D8 底部 Start 鈕在「未定義」有 Error／Success 停用款（狀態色停用按鈕不合規）。 | 停用鈕改 `Button / Text` Disabled variant；不再用狀態色停用款。 | 無狀態色停用按鈕。 |
| D-08 | D10 `193:9158`／D10.a `238:9101` | 內含 `Button / secondary 120×56`、`Button / primary 221×56` 手刻，高度 56 與標準 Large 不符；Toast 361×80。 | → G04，改 Large variant；文字 `Theme/bodyEmphasis`。 | D10 與 D10.a 僅 toast 有無差異（D10.a 無 toast）。 |
| D-09 | D11 `123:57386` | 已匯入路線清單列：左文字右 chevron，列高、分隔線不明；底部「匯入 GPX 檔案」藍鈕。 | `List rows`（兩行＋chevron）；按鈕 instance。 | D11／D17／D18 同一列元件。 |
| D-10 | D12 `123:61268` | 背景**純黑**（G06）；ActionSheet 手刻；「刪除路線」紅字 OK。 | G06 Dim＋D11 底層；ActionSheet → G04。 | 底層可見 D11。 |
| D-11 | D13 `123:60188` | 唯讀全部點位清單：編號、座標、名稱欄對齊；不是可編輯設計（見文件備註）；表頭「匯出」連結小。 | `List rows` 表格 variant；連結 → `Button / Text`。 | 欄位對齊、行高 44。 |
| D-12 | D14 `123:60820` | 純黑底＋系統分享 sheet 示意（灰字小）。 | G06；系統 sheet 示意用 `Overlay`＋說明；字級 `Theme/footnote`。 | 底層可見。 |
| D-13 | D15 `123:57737` | 摘要＋折疊點位；「儲存為最愛路線」按鈕用 `Button / Icon` Large 44；「清空路線」在未定義。 | 清空路線 → `Button / Text`（Danger Small）；其餘列 `Route / Stop row`。 | 與 D1 panel 共用。 |
| D-14 | D16 `123:60570` | **底層空白白**；系統檔案選擇器示意字級小、灰；SearchField 右緣檢查。 | G06；SearchField 同 B-03。 | 底層為 D11。 |
| D-15 | D17 `123:60674`／D18 `123:60722` | Snackbar／Toast 在列表頁上方；D18 toast 緊貼導覽列且列表標題被遮（目視）。 | Toast y 位置規則 → 距導覽列 8 pt；若遮列表→下移或列表內容下推。 | 無文字被遮。 |
| D-16 | D19 `232:8717`／D20 `174:8027`／D21 `174:8161`／D22 `232:8717`… | 列左側黑色實心圓（同 C-01）；D20 sheet 上方空白（G06）；標籤欄同 C-02（G07）；D21 刪除鈕與 C3 同。 | 黑圓 → icon；D20 同 C-02；D21 同 C-03。 | 與 C 區對應畫面一致。 |

## E · 搖桿與漫步

| 票 | Frame | QA（問題） | 替換項目 | 驗收 |
| :-- | :-- | :-- | :-- | :-- |
| E-01 | E1 `121:53058` | 搖桿羅盤 150 pt 置中；「漫步」標題＋速度 chip；「自動漫步」藍鈕；TabBar OK。Speed chip 手刻。 | G03；按鈕 instance；方位字 `Theme/subheadlineEmphasis`（已完成）。 | 與 E1.a 結構一致。 |
| E-02 | **E2 `121:53202`** | **頂卡失效**（G05）：黑方塊＋近白字不可讀；左下「停止漫步」灰鈕**文字被裁切**（68 pt 寬、「停止漫步」4 字滿框，目視文字貼邊）；右「更換地點」藍鈕比例過大。 | Top → G05；按鈕 → `Button / Text` Neutral Large（寬 fill、1:2）；文字 `Theme/bodyEmphasis`。 | 文字不貼邊、頂卡可讀。 |
| E-03 | E3 `158:6503` | **上方空白**（G06）；StatusPill「啟動」手刻（90×30）；Preset 同 D7。 | G06／G04；與 D7 sheet 共用元件。 | 與 D7 sheet 視覺相同。 |
| E-04 | **E4 `163:7291`** | 頂卡只剩「A」glyph（G05）；地點卡下方出現第二層 sheet 邊（目視：LocationCard 與底板重疊，卡片與底緣間距不一）；「確認」pin 氣泡 OK；卡片 star／copy 為 Button instance。 | Top → G05；LocationCard 位置固定、底板收至最小高度（規則已定）；Go → B-05。 | 頂卡有內容、卡片不與底板重疊。 |
| E-05 | E5 `193:9287` | Paused Top 與 warning Toast 並存，屬於刻意保留的雙層提示；底部恢復列 OK（「恢復漫步」藍鈕）。 | 保留 `Top / 執行指示（Paused）` 與 warning Toast 兩者；各用共用元件 instance、間距 8 pt、互不重疊，文字套 Theme。 | Top 與 Toast 皆保留、不重疊。 |
| E-06 | E1.a `229:2560` | 手動待命收合；Speed chip 手刻。 | G03。 | 與 E1 同母版。 |
| E-07 | E2.a `229:2688` | 頂卡只剩「A」（G05）；底部「漫步中」收合列。 | G05。 | 同 E2。 |

## F · 設定與共用規則

| 票 | Frame | QA（問題） | 替換項目 | 驗收 |
| :-- | :-- | :-- | :-- | :-- |
| F-01 | F1 `121:53504`／F1.a `239:15235` | 裝置服務卡手刻（`Group / 裝置`）；「停止服務」灰色大鈕為 Button；設定群組列 icon（`icon/*`）＋值＋chevron 重複手刻。 | `Group row`（G04）、`Service card`（G08）；按鈕 instance；群組標題 `Theme/footnote`。 | F1／F1.a／F4–F9 共用 Group row。 |
| F-02 | F2 `121:53611` | 規則參考頁，20 個文字層無 style；編號圓手刻。 | G10；編號圓 → `Badge / Number`（A-04 同款）。 | 文字全綁 Theme。 |
| F-03 | F3 `121:53638` | Toast／Snackbar 已 instance（良好）；說明文字 7 層無 style。 | G10。 | 同上。 |
| F-04 | F4 `123:58508`／F5 `123:58641`／F6 `123:58853` | 子頁大量空白（內容 < 1/3 屏）；返回列文案「‹設定」與標題字級不一；列值灰字對比（`#8A8A8E` on `#F9F9F9`）略低。 | NavBar（G08）；Group row；值字色改 `color/text/secondary` 並量測對比 ≥ 4.5:1，不足則調用既有更深 token。 | 對比達標。 |
| F-05 | F6.a `238:9408` | **上方空白**（G06）；滾輪數字停用色偏淡；「完成設定」藍鈕。 | G06；滾輪用 `Theme/wheel`（已定義）；按鈕 instance。 | 底層可見 F6。 |
| F-06 | F7 `123:59019`／F8 `163:7175`／F9 `123:59200` | 純列表，結構正確；檢查勾選 ✓ 為 `icon/check` instance。F9 腳註長文字行寬接近邊緣。 | List rows 選取 variant；腳註 `Theme/footnote`＋邊距 16。 | 腳註不貼邊。 |

---

## CS 系列：Color Scheme 優化票（Light／Dark，先於 G 系列的色彩綁定）

資料來源：`GoFly iOS / Light Theme`、`GoFly iOS / Dark Theme` 變數實值（已量測）＋WCAG 對比計算。**這些票會改 token 值，影響全檔所有綁定畫面，執行後必須逐 section 截圖回歸；改值或合併前先與使用者確認。** 同步 [IOS-COLOR-SCHEME.json](IOS-COLOR-SCHEME.json)、Figma 色票板、[IOS-UI-DESIGN.md](IOS-UI-DESIGN.md)、[IOS-TYPOGRAPHY.md](IOS-TYPOGRAPHY.md) 內色值。對比目標：一般文字 ≥ 4.5:1，大字／圖示／邊線 ≥ 3:1（disabled 除外）。

### 重複值盤點（已量測）

| 主題 | 相同值 | 現況 | 處理 |
| :-- | :-- | :-- | :-- |
| Light | `#FFFFFF` | `canvas`、`surface/card`、`surface/input`、`icon/outline`、`text/inverse`、`icon/inverse`、overlay background／sheet（@95） | 保留 `canvas`、`text/inverse` 為來源；其餘改 alias（CS-05） |
| Light | `#F9F9F9` | `surface/navigation`、`action/disabled/surface`、overlay card／tab-panel（@95） | disabled 改值（CS-03）；overlay 兩兩 alias |
| Light | `#007AFF` | `text/accent`、`icon/accent`、`action/primary/surface`、`action/primary/filled-surface`、`primary/500` | `filled-*` 兩個冗餘（CS-05）；`text/accent` 改值（CS-02） |
| Light | `#C6C6C8` | `line/separator`、`line/control`（另 `line/border` `#C7C7CC`、`control/grabber` `#C4C4C6` 差 1–2 級） | 4 個合為 2 個（CS-04） |
| Dark | `#2C2C2E` | `surface/card`、`surface/navigation`、`surface/disabled`、`action/disabled/surface`、`icon/outline`、overlay card／sheet／tab-panel | disabled 改值（CS-03）；其餘 alias |
| Dark | `#3A3A3C` | `surface/control`、`action/secondary/surface`、overlay panel | `action/secondary/surface` alias `surface/control` |
| Dark | `#48484A` | `line/border`、`line/control` | alias |
| Dark | `#636366` | `text/disabled`、`icon/disabled`、`icon/button/disabled`、`text/button/disabled`、`text/control/disabled`、`icon/control/disabled`、`control/grabber`、`line/input/default` | 禁用字／icon 6 個 alias 成 `*/disabled`；grabber、input 邊線依 CS-04 改值 |
| 兩者 | `primary/500` 與 `action/primary/surface` | 重複 | 改 alias |

### 近似值盤點（已量測，肉眼難分）

| 主題 | 近似對 | 對比 | 問題 |
| :-- | :-- | :-- | :-- |
| Light | `surface/disabled` `#EEEEF0` vs `surface/control` `#F2F2F7` | 約 1.02 | 停用與可用控制底幾乎同色 |
| Light | `action/disabled/surface` `#F9F9F9` vs 白 | 1.05 | 停用按鈕在白底近乎消失 |
| Light | `text/secondary` `#8A8A8E` vs `text/disabled` `#9999A0` | 近 | 次要與停用字難區分 |
| Light | `line/separator` `#C6C6C8`／`line/border` `#C7C7CC`／`control/grabber` `#C4C4C6` | 肉眼同色 | 三個 token 一個視覺值 |
| Dark | `canvas` `#1E1E1E` vs `surface/input` `#1C1C1E` | 1.02 | 輸入欄與背景無法區分（只靠邊線） |
| Dark | `surface/control` `#3A3A3C` vs `line/separator` `#38383A` | 1.03 | 分隔線與控制底同色 |
| Dark | `surface/control/active` `#4C4C4F` vs `line/border` `#48484A` | 1.07 | 選取底與邊線同色 |
| Dark | `surface/control/disabled` `#242426` vs `canvas` `#1E1E1E` vs `surface/disabled` | 1.08 | 三種停用底接近 |
| Dark | `surface/card` `#2C2C2E` vs `canvas` | 1.20 | 卡片層次偏弱（可接受，需靠陰影／邊線） |

### 對比不足（已量測）

| 主題 | 組合 | 對比 | 影響 |
| :-- | :-- | :-- | :-- |
| Light | `text/secondary` 於白底／`#F2F2F7` | 3.44／3.08 | 副標、地址、座標、設定值全數低於 4.5 |
| Light | `text/accent` 與白字於 `action/primary/surface`（`#007AFF`） | 4.02 | 連結文字與主要按鈕字略低 |
| Light | 白字於 `action/danger/surface`（`#FF3B30`） | 3.55 | 紅色按鈕（刪除、結束路線）字 |
| Light | `text/warning` `#CC6600` 於 `#FFF6E6` | 3.58 | warn toast 文字 |
| Light | `text/success` `#248A3D` 於 `#F0FAF2` | 4.12 | success toast 文字 |
| Dark | `action/primary/text` `#E5E5EA` 於 `#0066CC` | 4.43 | 主要按鈕字 |
| Dark | `action/danger/text` 於 `#E14C46` | 3.14 | 紅色按鈕字 |
| Dark | `text/disabled` 於 canvas／card | 2.78／2.33 | 停用（可豁免，但需與可用態明確差異） |

### 票

- **CS-01 · 凍結並備份**（已執行，見「執行狀態」）：匯出現行兩主題 token（`figma_export_tokens` 或本文件上表）；建「回歸截圖」清單（A–F 各 section、按鈕板、共用元件板）。驗收：有 before 截圖與 token JSON。
- **CS-02 · Light 文字／強調色對比修正**（建議值，執行時以腳本驗證 ≥ 4.5）：
  - `text/secondary`（含 `icon/secondary`）`#8A8A8E` → `#6C6C70`。
  - `text/accent` `#007AFF` → `#0066CC`（連結文字）；`action/primary/surface` `#007AFF` → `#0071E3`（**使用者已決定**，白字 ≥ 4.5）；`primary/500`、`action/primary/filled-surface` 隨之連動，`primary/100–900` 色階需重算（500＝`#0071E3`），Light 內所有 `#007AFF` 的 icon／邊線／focus 外框同步改綁。
  - `action/danger/surface` `#FF3B30` → `#D70015`（與 `text/danger` 對齊）；`icon/danger`、`line/status/danger` 保留 `#FF3B30`。
  - `text/warning` `#CC6600` → `#A35200`；`text/success` `#248A3D` → `#1E7A34`。
  - 驗收：上表 Light 5 組皆 ≥ 4.5；B、C、F 區截圖無破版。
- **CS-03 · 停用態與控制底分離**：
  - Light：`surface/disabled` 與 `action/disabled/surface` 統一為 `#E5E5EA`（與 `surface/control` `#F2F2F7` 明確分層）；`text/disabled`、`icon/disabled` 維持 `#9999A0`（`text/secondary` 變深後兩者拉開）。
  - Dark：`surface/disabled`、`action/disabled/surface`、`surface/control/disabled` 合為同一值 `#242426`；`text/disabled` 系列 6 個 alias 同一 token `#6E6E73`。
  - 驗收：停用按鈕與可用 Neutral 按鈕在 Light／Dark 肉眼可辨；按鈕板狀態矩陣重新截圖。
- **CS-04 · 線條與 grabber 整併**：
  - Light：`line/separator` 保留（建議 `#D8D8DC`，hairline 專用）；`line/border`、`line/control`、`control/grabber` 合為 alias `line/border`（`#C7C7CC`）。
  - Dark：`line/separator` `#38383A` → `#404042`（與 card 對比約 1.25）；`line/border`、`line/control`、`line/input/default`、`control/grabber` 合為 alias `line/border`（`#636366`，對 card 約 2.0）；`surface/control/active` `#4C4C4F` 保留，與邊線不再同色。
  - 驗收：每主題線條類 token 只剩 `separator`、`border` 兩個視覺值（status 線另計）；分隔線在 card 上可見。
- **CS-05 · 移除冗餘 token／改 alias**：刪除 `action/primary/filled-surface`、`action/primary/filled-text`（重綁至 `action/primary/surface／text`）；`primary/500` alias `action/primary/surface`；`icon/outline` alias（Light `text/inverse`、Dark `surface/card`）；`surface/card`、`surface/input`（Light）alias `canvas`；overlay `sheet` alias `background`、`tab-panel` alias `card`（Light／Dark）；`action/secondary/surface`（Dark）alias `surface/control`。驗收：重綁後畫面零變化（像素比對）；變數數量下降並列於本文件。
- **CS-06 · Dark 輸入欄與層次**：`surface/input` `#1C1C1E` → 比 canvas 更深的 inset `#151517`（或 alias `canvas`＋靠 `line/input` 邊線，二擇一，需決定）；`surface/card` 保持 `#2C2C2E`，確認 card 與 canvas 之間靠陰影／邊線補層次；Dark `canvas/button-board`（`#101012`）、`surface/button-board`（`#1C1C1E`）僅供元件板，確認不被 App 畫面引用。驗收：B3 搜尋欄、C2／D20 欄位在 Dark 清楚可見。
- **CS-07 · Dark 主要／危險按鈕對比**：`action/primary/surface` `#0066CC` → 約 `#005FC7`、`action/danger/surface` `#E14C46` → 約 `#B83A34`，使 `#E5E5EA` 字 ≥ 4.5；執行時以腳本驗證，不足再微調。驗收：Dark 按鈕板主要／危險 variant 對比達標。
- **CS-08 · Light／Dark token 對等**：Dark 獨有 `icon/button/disabled`、`text/button/disabled`、`line/input/*`、`surface/control/active`、`surface/control/disabled`、`text/input/*`、`icon/input/default`、`text/control/disabled`、`icon/control/disabled` 在 Light 缺失（Light 以通用 token 代替）。決議：Light 補齊（alias 到通用 token）或 Dark 收斂回通用 token，兩主題 token 名稱集合必須一致。驗收：兩 collection 變數名稱 diff 為空。
- **CS-09 · Color Scheme 色票板與 JSON 同步**：色票板與 [IOS-COLOR-SCHEME.json](IOS-COLOR-SCHEME.json) 反映合併後 token（alias 顯示來源）；移除「palette/*」裸值引用（`3c3c43-3c3c43` 66 次、其餘 3 個），Home indicator 改綁決議後的 token（見 G02）。驗收：無 `color/palette/*` 被 Light 畫面引用；JSON 與 Figma 一致。

## 執行狀態（2026-10-28，Claude 已在 Figma 執行）

- **CS-01–CS-09 已完成（Light＋Dark token；Figma 色票板、[IOS-COLOR-SCHEME.json](IOS-COLOR-SCHEME.json) 已同步）**：
  - Light：`action/primary/surface` `#0071E3`、`text/accent` `#0066CC`、`text/primary` `#1C1C1E`、`text/secondary` `#6C6C70`、新增 `text/tertiary` `#8E8E93`、`text/disabled` `#AEAEB2`；danger／warning／success 文字與 icon 達對比；`surface/disabled` `#E5E5EA`；`line/separator` `#D8D8DC`、`line/border` `#C7C7CC`、新增 `line/strong`、`line/status/success|info`；`primary/*` 色階重算；`filled-*` 170 處重綁後已刪除；`card／input／icon-outline／line-control／grabber` 等改 alias；補齊 Light 缺的 Dark 對應 token。
  - Dark：`action/primary/surface` `#005FC7`、`action/danger/surface` `#B3352F`、`surface/input` `#151517`、`line/separator` `#404042`、`line/border` `#636366`、`text/disabled` `#6E6E73`、新增 `text/tertiary`；disabled、線條、surface 重複值已 alias；`filled-*` 已刪除。
  - 未執行：overlay 4 個 token 因 95% 透明度無法 alias，維持各自值（Light TabPanel＝Card 於色票板標註）；Dark 狀態色（success／warning／error）Main／Text／Border 仍同值，因 Dark toast 規格為實心亮色外框（2026-10-24 使用者確認）。
  - 回歸：已截圖核對 Light／Dark 色票板與 B 區；其餘 section（C–F、Dark C–F）尚未逐一回歸，執行 frame 票時順帶核對。
- **C–F 回歸（2026-10-28，Light＋Dark 截圖逐區核對）**：C、F 區 token 改動後無破版；發現並修正 4 項既有問題（非 token 改動造成）：
  1. Dark D8 的規劃面板、路線列、按鈕、各 icon 全綁 `surface/status/danger`／`line/status/danger`，整塊泛紅 → 改回 `surface/card`、`icon/primary`、`surface/disabled`（Light D8 的 icon 與 ✕ 同樣泛紅，一併改回中性）。
  2. Light E2／E2.a／E4／E5 與 Dark E2／E5 頂卡為手刻 `Top / 漫步指示`（黑方塊＋白字、只剩「A」等）→ 全部換成共用 `Top / 執行指示`（Active／Paused），文字覆蓋為「前往 中山公園／剩 850 m · 25 km/h」「漫步已暫停／剩 850 m · 20 km/h」。對應 G05 的 E 區部分已完成；D 區頂卡原本就是共用元件。
  3. Light F3 的 Snackbar 指向舊 master（文字白字壓白底而不可見）→ 改指 `Light · Snackbar / 2 秒自動消失`；F3 三個 Toast 一併改指 Light master。
  4. 仍待處理（未動）：Light／Dark D12、D14、D16 底層純黑／空白，C2、D20、E3、F6.a 上方空白（G06）；Dark B2 道路亮白、Dark B5 藍色大塊；B11 StatusPill 舊 master。

- **R07 Mac icon 已修（Light＋Dark）**：Hero 改為與 R02 同款淺底圓角卡（綁 `surface/control`）＋線條筆電 icon；新增 Icon 目錄元件 `icon/mac`（`313:28076`）。同時修正 Dark R02／R03／R07 Hero 底色誤綁 `icon/primary`（Hero 變成淺色卡、icon 不可見）。
- **新增 D23 · 檢視路線 sheet（全部地點）（Light `313:27817`、Dark `313:27947`）**：由 D13 為底，置於 D 區 Row 2（x:1828, y:1380）。內容對應 App `GoFlyRouteListView`：返回＋「全部點位」標題、路線節點卡（起點／停靠點 1–4／終點，grip、✕）、底部「＋ 新增停靠點」「⇅ 反轉順序」。Light 與 Dark 皆含說明文字。這是靜態 wireframe，節點卡為 D2 的列複製，尚未元件化（見 D-01）。
- 觀察（非本次造成，待另開票）：Dark B2 地圖道路呈亮白、Dark B5 出現藍色大塊（map token 未動過）。

- **後續更新（2026-10-28，晚）**：
  - **CS 層次再整併（使用者確認）**：背景／Surface／Map overlay 整併為 4 級（canvas／card／control／active）；Light：`#F2F2F7`／`#FFFFFF`／`#E1E1E6`／`#BCBCC2`，Dark：`#1C1C1E`／`#2C2C2E`／`#3A3A3C`／`#505054`。Map overlay 縮為 card、panel（control）兩級。sheet、bottom panel 用 card 級；BACKGROUND 只指 canvas。
  - **Light CS 第二輪**：停用態獨立（`#ECECF0`）、`text/tertiary` `#7B7B80`、狀態色外框實心（與 Dark 一致）、INFO 偏冷藍；Dark：停用底 `#343437`（比 sheet 亮一點點）、Neutral 按鈕與輸入欄 `#505054`、INFO 以 `#475569` 為基準、SUCCESS／WARNING 降飽和（Main `#3A8A58`／`#A87430`）、Toast 小字 `#C7C7CC`。
  - **新增／修正畫面**：D23 檢視路線 sheet（Light＋Dark）、A 區 R08 需要完成設定（Light＋Dark，齒輪 icon）、R07 Mac icon 與 Hero 底色（Light＋Dark）、Dark D8 泛紅、E 區頂卡換共用元件、F3 Snackbar／Toast 指向 Light master、D6.a 已由使用者刪除。
  - **Dark CS 優化**：色票板補同步；Success／Warning Main 達 4.5；連結／accent／focus `#4DA3FF`；tertiary `#8A8A8E`；Error Text／icon `#FF7A70`、Border `#E0605A`（細節見對照文件）。
  - **StatusPill**：Light／Dark `StatusPill / 停止` 已刪除（與 `啟動` 同樣式），R07「尚未配對」等改用 `StatusPill / 啟動` 覆蓋文字（R07 畫面尚未換 instance）。
  - **色票庫**：`GoFly iOS / Common Color` collection 新增（white／black／transparent／gray 50–950，共 14 個，Common Color 色票板已綁定）；Light／Dark 各 86 個 CS 語意 token（含 `map/*`、`speed/*`，保留因為 04 畫面仍引用）；已移除非 CS 色票：`color/legacy/*`（每主題 23 個）、`canvas/button-board`、`surface/button-board`，以及舊 `LocalGo / Wireframe` collection（19 個，影響 00／01 舊頁與 04 少量舊節點，綁定改為原值，畫面不變）。
  - **仍待處理**：G06 底層空白／純黑（D12、D14、D16、C2、D20、E3、F6.a）、Dark B2 道路亮白／B5 藍塊、B11 StatusPill 舊 master、Home indicator 改系統內建（G02）、R07 pill 換 instance、各 frame 票（A–F）與 G01／G03／G04／G07–G10 尚未執行。

## H 系列：Light 浮動控制項近白統一（2026-10-28，使用者要求）

**使用者回饋**（App 截圖，路線暫停 sheet）：地圖控制鈕、Speed chip、icon 按鈕底色太灰、太顯眼；要全部靠近白，sheet 底色也靠近白。

**已由 Claude 完成（CS 與共用元件，Luna 不要再改）**
- CS 新增語意 token `surface/control/floating`（浮動控制項底色）：Light alias `surface/card`（近白 `#FBFBFD`），Dark alias `surface/control`（`#3A3A3C`）；[IOS-COLOR-SCHEME.json](IOS-COLOR-SCHEME.json) `surface.floating` 同步。sheet／bottom panel 綁 `surface/card`（近白 `#FBFBFD`）。
- 共用元件 master 改綁 `surface/control/floating`：`Recenter`（`222:13228`）、`FitRoute`（`222:13229`）、`Button / Speed chip` Default（`313:29165`）、`Light · Button / Icon` 的 Standard Enabled（Large／Medium／Small／Extra Small）與 Route Enabled Large。D6 截圖確認 Light 地圖控制鈕與 Speed chip 為近白。
- 控制項在白色 sheet 上靠既有邊框（`line/separator`／`line/border`）與地圖上的陰影區分；若 Luna 發現白底在 sheet 上看不出輪廓，記錄為待決策，不要自行改 token。

**交給 Luna 逐一修正（只動 frame，不動 CS／master）**
| 票 | Frame | 問題（已量測） | 修正 | 驗收 |
| :-- | :-- | :-- | :-- | :-- |
| H-01 | D6 `121:52798`、D7 `158:6131`、D10 `193:9158`、D10.a `238:9101` | 控制列「來回」「方向」為手刻 `Button / icon / 來回｜方向`（36×36，底 `action/secondary/surface` `#D1D1D6`，描邊 `icon/primary` 黑），仍是灰底黑框，是截圖中最突兀的一項。 | 改為 `Light · Button / Icon`（Type=Route 或 Standard、Size 36 對應 variant；沒有 36 時用 Medium 40 並回報）instance，圖示用 `icon/repeat`、`icon/direction-forward`；移除手刻副本，必要時把「Controls row / 來回·方向·時速」收進「未定義」並標註已取代（G08）。 | 底色為 `surface/control/floating`，邊框 `line/separator`，與 Speed chip 同一視覺；4 張一致。 |
| H-02 | D10 `193:9158` | FitRoute、Recenter 與整個 `Panel / 執行模式控制`（`238:9223`）、手刻按鈕全綁 `map/route`（`#33608F` 深藍），整塊 panel 變深藍（目視確認，與 D6 完全不同）。 | Panel 改綁 `surface/card`；FitRoute／Recenter 清除 override，回到 master（`surface/control/floating`）；panel 內「結束」「繼續」改 `Light · Button / Text` Neutral／Primary instance；文字用 `text/*`。 | D10 與 D10.a 僅差「是否有頂部 toast」，panel 與控制項完全相同。 |
| H-03 | D10.a、D8 `222:10536`、D9 `222:10849`、B10 `222:11656` | `Recenter`／`FitRoute` instance 在這些 frame 有 local 覆蓋，底色綁 `surface/control`（`#E1E1E6`），與 master 不一致（D8 2、D9 2、B10 1、D10.a 2 個）。 | 對這些 instance 執行 Reset overrides（或把 fills 重綁 `surface/control/floating`）。 | 全部 Light FitRoute／Recenter 皆為 `surface/control/floating`（目前 33 個中 9 個以外已一致）。 |
| H-04 | D6、D10、D10.a、D7 | 進度條 `Progress`（`#D1D1D6` `action/secondary/surface`）與「結束」Neutral 按鈕（`#D1D1D6`）仍偏灰。 | **需使用者決策**，Luna 不要先改：是否把 Neutral 按鈕與 Progress 軌道也改為近白＋邊框，或維持灰作為次要強度。回報截圖對照兩案。 | 使用者選定後才改。 |
| H-05 | B3、B4、D5、C1–C4、D19–D22 | 搜尋欄、輸入欄在白色 sheet／頁面上的底色是否也需近白（目前 Light input alias `surface/card`，已近白）。 | 只核對，不改；若有 frame 手刻輸入底色偏灰，列入回報。 | 回報清單。 |

> 備註：H 系列不涉及 Dark（Dark 浮動控制項維持 `#3A3A3C`）。Dark 版同樣的手刻控制列（H-01、H-02 對應 Dark D6／D7／D10／D10.a）待 Light 驗收後另開票。

### 2026-10-28 Codex 執行狀態（Figma Desktop Bridge）

本輪核對 `GoFly · UI 線框討論`（`RtPV8PXCQJ2WXK3jk3kPrq`）04 頁。Light A–F 共 66 張 393×852 frame：64 張 App frame、F2／F3 兩張規則參考。F2／F3 沒有系統列；其餘 64 張都使用 `System / StatusBar` instance。已從 66 張 Light frame（含 sheet）移除 69 個手刻 Home indicator；讀回為 0 個殘留。

| 共用票 | 狀態 | 本輪結果／未完成項 |
| :-- | :-- | :-- |
| G01 | 已完成 | 新增 `Map / Base` `313:29422`；B 9 張、D 12 張、E 7 張，共 28 張改為 instance。D10 原先包在底圖內的 MapControls／Panel 已移至地圖上層。底圖色彩 paint 全綁既有 map token；中山區／大同區套 `Theme/caption`，淡水河套 `Theme/footnote` 並保留既有 map label token。逐張截圖讀回。 |
| G02 | 已完成 | 新增 `System / StatusBar` `313:28295`；64 個 Light App frame 為該元件 instance，移除 69 個手刻 Home indicator。 |
| G03 | 已完成 | 新增 `Button / Speed chip` `313:29179`（Default `313:29165`、Disabled `313:29172`）；D6、D7、D10、D10.a、E1、E1.a、E2、E2.a、E3、E4 共 10 張皆讀回為 68×36 instance，值分別為 9／25。 |
| G04 | 未完成 | StatusPill、Preset、Role、D10／D10.a 按鈕、D12 ActionSheet 已完成並沿用既有元件；Group row 的 With value／With chevron／Status variants 尚未建立。 |
| G05 | 已完成 | 核對 E2、E2.a、E4、E5、D10、D10.a 六張皆為 `Light · Top / 執行指示` instance；未改 master。 |
| G06 | 已完成 | 新增綁既有 Light `color/text/primary`、opacity 40% 的 `Overlay / Dim` `313:29274`；C2、D12、D14、D16、D20、E3、F6.a 均為 instance，母畫面在 sheet 後方可見。D7 原手刻白色遮罩也改為 instance `313:30421`，圖層順序修正後 D6 母畫面與設定 sheet 內容皆可見。 |
| G07 | 已完成 | 新增 `TextField / Label` `313:29286`（Placeholder property、右側 Clear）；C2／D20 已替換，無搜尋圖示。B3／B4／D5 另換 321 pt compact SearchField instance，清除鈕與欄寬已對齊。 |
| G08 | 未完成 | 本輪已刪除兩組「色彩待確認」色票及 label／hex，且 A–F 無對應裸色 paint；其餘 20 組元件副本仍待整理，未新增 token。 |
| G09 | 未完成 | 本輪 H-01 四張已用既有 Standard／Small 36×36 Button/Icon instances 替換來回／方向控制；D 區其他手刻 icon 控制尚待替換，未改 master／尺寸 variants。 |
| G10 | 已完成 | F2／F3 原有文字已套 Theme；本輪在 B5、B7、B8、B9 將 4 個 Go 字層補為 `Theme/captionEmphasis`，讀回 A–F（排除 9:41／原生鍵盤）無未套樣式文字。 |

逐 frame 票狀態（「未完成」表示本輪有部分修正或尚未執行，但仍有驗收項未完成）：

| 票 | 狀態 | 本輪結果／未完成項 |
| :-- | :-- | :-- |
| A-01 | 已完成 | 使用者更新 R01：改用 `Light · Progress` instance、icon 底色改 grey50；截圖／讀回確認 Logo 居中、token 填色及 Progress instance。 |
| A-02 | 已完成 | 使用者調整 R02 文字字級；截圖確認標題 28 pt、Theme style、說明與 permission pill 間距及底部 CTA 完整。 |
| A-03 | 已完成 | 使用者依 R02 調整 R03 文字字級；截圖確認標題 28 pt、Theme style，狀態 pill 與 CTA 可讀且未裁切。 |
| A-04 | 未完成 | R04／R04.a 已重排步驟卡、連線說明與狀態 pill；4 步編號修正為 1–4，錯誤 toast 移到標題上方。Steps card 共用化與連線說明 link 改用共用按鈕仍待完成。 |
| A-05 | 未完成 | R05 步驟列改為 52 pt，三列 `Steps card` 高 156 pt；Troubleshooting card 與其相隔 16 pt。2–4 編號、藍色數字底與分隔線清楚，空白佔位列已清除。導覽列與 list row 共用化仍待完成。 |
| A-06 | 未完成 | R06 pill 已換 instance；Steps card 與 toast 間距未處理。 |
| A-07 | 已完成 | 使用者標示 R07 設計更新完成；截圖複核 Hero icon、標題、說明、StatusPill 層級清楚，內容未裁切。 |
| B-01 | 已完成 | B1／B2 的 `Map / Base` 與 `System / StatusBar` 均為 instance；兩張 Favorite／Copy 控制各為 44×44 pt instances。改後截圖確認收合／半開 sheet 的標題卡位置一致，內容無裁切。 |
| B-02 | 未完成 | List row 與文字連結未元件化。 |
| B-03 | 未完成 | 自適應 SearchField 已消除右緣裁切；空欄僅顯示貼上、隱藏清除 X。頁面底為 canvas，最近搜尋列表區為 card；截圖確認。歷史列尚未元件化；鍵盤內「確認」依例外保留。 |
| B-04 | 未完成 | 自適應 SearchField 已消除右緣裁切；有值時顯示清除 X。頁面底為 canvas，座標／附近地點列表區為 card；截圖確認。結果列 variant 尚未統一。 |
| B-05 | 已完成 | B5 為共用 `LocationCard / Route` instance；卡片 Go 為 Primary Inline 77×40 pt，Star／Copy／Close 命中區均為 44×44 pt instances。截圖確認 SearchBar／StatusPill 未遮 Pin／Go，卡片與按鈕完整可見。 |
| B-06 | 已完成 | 截圖讀回確認 snackbar 未遮「目前模擬位置」標題。 |
| B-07 | 已完成 | Go 氣泡與 Pin 下移 24 pt；改後截圖完整可見。 |
| B-08 | 未完成 | 已核對 Pause StatusPill 與 warn Toast 均為共用 instance、間距 8 pt 且不重疊；保留現況。List row／母版整理仍未完成。 |
| B-09 | 未完成 | 已核對 Pause StatusPill 與 warn Toast 均為共用 instance、間距 8 pt 且不重疊；保留現況。List row／母版整理仍未完成。 |
| B-10 | 已完成 | 改為紅點「錯誤」StatusPill instance；截圖與 Wi-Fi error toast 一致。 |
| B-11 | 已完成 | 改為灰點 `StatusPill / 啟動` instance，覆蓋「連接中」；依本輪決策不新增 spinner variant。 |
| C-01 | 未完成 | 7 列 56 pt 灰圓底＋`icon/star` 已取代黑圓，截圖複核無黑圓；List rows instance 未完成。 |
| C-02 | 未完成 | G06 underlay 與 G07 TextField 已完成；取消／刪除按鈕未換共用 variant。 |
| C-03 | 已完成 | C3 `286:24717` 與 D21 `286:24751` 均讀回為 `Type=Danger, State=Active, Size=Medium` Button/Text instances，361×48，綁既有 Danger surface token；截圖確認兩頁位置與尺寸一致。原票單「Large」與 04 現行渲染的 48 pt 高度不符，依視覺準據改列 Medium。 |
| C-04 | 未完成 | 5 列 56 pt 灰圓底＋`icon/star` 已取代黑圓，截圖複核無黑圓；Snackbar action 尚未元件化。 |
| D-01 | 未完成 | RoutePanel、Stop row、按鈕與 icon 尺寸未處理。 |
| D-02 | 未完成 | RoutePanel／Stop row 與 B5 Go 尺寸未處理。 |
| D-03 | 未完成 | 搜尋欄裁切、history icon 背景已修；Role chip 已換 `Chip / Role` instance。Favorite action、清空記錄鈕未元件化。 |
| D-04 | 未完成 | Speed chip 已換 instance；Controls row 與主按鈕比例未處理。 |
| D-05 | 已完成 | D6.a 不重建；孤立 Light 說明 `222:16535` 已由 Claude 刪除，本輪只讀回狀態，未改 frame 外說明或 Dark。 |
| D-06 | 已完成 | D7 已使用 `Map / Base`＋40% `Overlay / Dim` instance；Speed chip 與四顆 Preset chip 為 instance，25 為 Selected；Slider 軌道／已選軌道／thumb 分別綁既有 `color/surface/control`、`color/action/primary/surface`、`color/canvas` token，文字套 `Theme/captionEmphasis`。完成設定為共用 Button/Text instance；改後截圖確認底圖、sheet、滑桿與按鈕完整可見，Preset 外觀與 E3 一致。 |
| D-07 | 已完成 | D8／D9 的 Start 按鈕讀回為 `Type=Primary, State=Disabled, Size=Large` instance（`303:26789`／`303:26793`）；D8、D9 截圖確認停用色為中性灰，非 success／error 狀態色。 |
| D-08 | 已完成 | D10／D10.a 的 Neutral／Primary 已換 Large Button/Text instance，尺寸為 120×56／221×56；兩張截圖與 variant／文字讀回一致。 |
| D-09 | 未完成 | D11／D17／D18 的 List row 尚未元件化。 |
| D-10 | 已完成 | G06 底層與 dim 已完成；D12 取消鈕為 Neutral Large instance；動作選單為共用 `ActionSheet / 路線動作` instance，改後截圖確認底層 D11 與四個動作列可見。 |
| D-11 | 未完成 | 唯讀點位表格列與匯出連結未處理。 |
| D-12 | 未完成 | G06 底層與 dim 已完成；系統 share sheet 字級／說明未核對。 |
| D-13 | 未完成 | 清空路線按鈕與 Route row 未元件化。 |
| D-14 | 未完成 | G06 底層與 dim 已完成；系統檔案選擇器樣式未核對。 |
| D-15 | 未完成 | D17／D18 toast 位置與遮擋尚未處理。 |
| D-16 | 未完成 | D19 6 列黑圓已換星號並調為 56 pt；D20 的 G06／G07 已完成；D21 刪除鈕與其餘列未處理。 |
| E-01 | 未完成 | Speed chip 已換 instance；CTA instance 與其餘驗收未完成。 |
| E-02 | 已完成 | Top instance 與 Speed chip 已修；Neutral／Primary CTA 調為 120×56／221×56，座標 x=16／156、底距 34 pt；改後截圖確認「停止漫步」未裁切，CTA 比例與 D6 一致。 |
| E-03 | 已完成 | StatusPill、Dim、Preset chip 已換 instance；速度 25 為 Selected。改後截圖確認設定 sheet 與 D7 相同且底層可見。 |
| E-04 | 未完成 | Top instance 與 Speed chip 已修；LocationCard／底板重疊尚未修。 |
| E-05 | 已完成 | E5 的 Paused Top 與 warning Toast 均為共用 instance，y=58／138、間距 8 pt、互不重疊；文字為 Theme styles。截圖讀回，兩層均保留。 |
| E-06 | 已完成 | E1.a Speed chip 已換 68×36 共用 instance 並讀回。 |
| E-07 | 未完成 | Top instance 與 Speed chip 已修；收合列其餘驗收未完成。 |
| F-01 | 未完成 | Service card、Group row 與 Button 未元件化。 |
| F-02 | 已完成 | F2 文字與編號 Badge 已改 Theme／instance，改後截圖可讀。 |
| F-03 | 已完成 | F3 七個未套樣式文字層已套 Theme，改後截圖無裁切。 |
| F-04 | 未完成 | F4–F6 導覽列、Group row 與值文字對比未處理。 |
| F-05 | 未完成 | G06 underlay／dim 已完成；wheel style 與按鈕尚未驗收。 |
| F-06 | 未完成 | F7–F9 List rows 與腳註邊距未處理。 |

本輪新增／替換的共用元件 node：`313:28295`、`313:29179`（variants `313:29165`／`313:29172`）、`313:29274`、`313:29286`、`313:29304`、`313:29386`、`313:29422`、`313:30237`、`313:30375`、`313:30389`。D7 Dim instance 為 `313:30421`；D12 ActionSheet instance 為 `313:30405`；E2 CTA instances `286:24765`／`286:24767` 調整為 120×56／221×56。主要 frame 範圍：R02／R03／R04／R06／R07、B1／B2／B5／B6／B7／B8／B9／B10／B11、B3／B4、C1／C2／C3／C4、D1／D2／D3／D4／D5／D6／D7／D8／D9／D10／D10.a／D12／D14／D15／D16／D19／D20／D21、E1／E1.a／E2／E2.a／E3／E4／E5、F2／F3／F6.a；G02 另覆蓋全部 64 張 App frame。Map/Base instances 為 B `313:29423`–`313:29615`、D `313:29639`–`313:29903`、E `313:29927`–`313:30071`（各以 24 為序號間隔）；未再有手刻 `Map / Apple Maps 淺色` frame。

其他新增／替換 instance node：StatusPill `313:29250`、`313:29253`、`313:29256`、`313:29259`、`313:29262`、`313:29265`、`313:29268`、`313:29271`；TextField `313:29292`／`313:29298`；Compact SearchField `313:29315`／`313:29326`／`313:29337`；Badge `313:29388`／`313:29390`／`313:29392`／`313:29394`／`313:29396`；Role chip `313:30378`；D10 buttons `313:30383`／`313:30385`；D12 cancel `313:30387`。Preset variants 為 `313:30098`／`313:30116`／`313:30134`／`313:30154`／`313:30174`／`313:30190`／`313:30206`／`313:30223`；D7／E3 Preset instances 分別為 `313:30238`／`313:30255`／`313:30274`／`313:30289` 與 `313:30305`／`313:30322`／`313:30341`／`313:30356`。StatusBar instances 為 `313:28308` 至 `313:29127`（每個 ID 間隔 13，共 64）。未修改 Variable／Variable collection、色票板、Dark、App，未 commit；未做裝置驗證或 prototype。

**H 系列追加（2026-10-28，使用者：Light card 不可純白、Dark 也統一 floating）**
- **Light CS 不再有純白表面**：canvas `#EEEEF3`、card／floating `#FBFBFD`、control `#DEDEE4`、active `#B9B9BF`，Map overlay card／sheet／tab-panel `#FBFBFDF2`、panel `#DEDEE4F2`；同步微調相近色：停用底 `#E7E7EC`、`text/secondary`／`icon/secondary` `#6A6A6F`、`text/tertiary` `#77777C`、`line/separator` `#D6D6DC`、色票板 Secondary Background `#DEDEE4`。純白只保留在「彩色按鈕上的文字／icon」（`text/inverse`、`icon/inverse`、`action/primary|danger/text`）與地圖道路／marker，屬前景色，非表面。Light A–F frame 無未綁定的純白填色（已掃描）。
- **Dark 已統一**：`surface/control/floating` Dark alias `surface/control`（`#3A3A3C`）；已改綁 Dark 共用元件 `Dark · Recenter`、`Dark · FitRoute`、`Button / Icon` Standard／Route／MapControls／Copy Enabled，另 5 個 instance override 重綁。**Dark 的 Standard／Route 圖示按鈕因此由 `#505054` 變 `#3A3A3C`**。
- 追加給 Luna：**H-06**（Dark，Light 驗收後再做）Dark D6／D7／D10／D10.a 手刻 `Speed chip`、`Controls row` 來回／方向按鈕、`MapControls` 框，改為共用元件並綁 `surface/control/floating`；**H-07** Light／Dark 掃描 frame 內仍直接綁 `surface/control`／`control/active` 的浮動控制項（Light 3 處、Dark 約 58 個 instance override）逐一改綁或 Reset overrides。

**決策更新（2026-10-28，使用者）**：① **E-05**：保留 `Top / 執行指示`（Paused）與 warning Toast，兩者皆留，驗收改為「兩者皆為共用元件 instance、間距 8 pt、不重疊」，取代「同時只一層提示」。② **G08 兩個待確認色**（`#1C1C1E` 執行提示底色、`#6B6B73` dialog 說明字）**捨棄**，只用現有 CS token（卡片底 `surface/card`／`surface/overlay/card`，文字 `text/primary`／`text/secondary`），不新增 token；清除「未定義」區對應色票。

**自適應寬度元件（2026-10-28，Claude 完成）**：Slider（Value 0–100 variants，Light／Dark）與 `Text Field / Neutral`（Auto Layout，Light／Dark）、`SearchField`／`SearchBar`（constraints）改為可自適應寬度；Light D7／E3 滑桿已換 instance。第二輪已修正 B3 空欄貼上／清除重疊；Dark D7／E3 滑桿另票處理。

## 第二輪執行順序

1. P0：D10 H-02、B3／B4 搜尋欄與背景核對、未套 Theme 文字讀回。
2. P1：H-01、H-03、H-07 浮動控制；H-05 輸入欄核對；H-04 保留待決策。
3. P2：G04／G09 與 A → B → C → D → E → F 逐票處理；每個 section 完成後截圖回歸。
4. P3：依使用者已決定事項執行 G08-1／G08-2 清理及 E-05 保留雙層提示，並更新驗收準則。
5. Dark frame 不在本輪；Dark Slider／控制項後續另票處理。

## 已決定事項（2026-10-28 使用者）

- Light `action/primary/surface` 改 `#0071E3`。
- B10 未連 Wi-Fi：StatusPill 為 **錯誤（Error，紅）**。
- Home indicator 用系統內建，不自訂（G02）。
- CS／色票已由 Claude 完成，本輪不得再改 Variable 定義或色票板。

## 未確認事項

- H-04：Neutral 按鈕與 Progress 軌道是否改為近白＋邊框，或維持目前次要灰。

### 2026-10-28 第二輪 Light 執行狀態（Figma Desktop Bridge）

| 票 | 狀態 | 執行結果／未完成項 |
| :-- | :-- | :-- |
| G11 | 已完成（Claude；本輪只讀回） | Light Slider set `313:30644` 為 21 個 Value 0–100、每 5 一檔的 variants；D7／E3 使用 Value=20、361 pt instance。未重做，也未碰 Dark Slider。 |
| P0 · D10 H-02 | 已完成 | D10 Panel `238:9223` 綁 `surface/card`；FitRoute／Recenter `238:9632`／`238:9222` 綁回 floating master 的 fills／strokes；panel 的結束／繼續本來就是 Button/Text instances。D10 截圖確認已無整塊深藍。 |
| P0 · B3／B4 | 已完成 | B3 空欄只顯示 Paste，隱藏 Clear X；B4 有輸入時只顯示 Clear X。兩張截圖確認搜尋欄右緣完整。採「頁面底＝canvas、列表區＝card」；列表區以既有 `surface/card` 綁色，原生鍵盤區維持 card。 |
| P0 · Theme 文字 | 已完成 | 全 A–F 讀回只有 4 個未套 Theme 的 `Go`（不是原估 7 個），均設為 `Theme/captionEmphasis`；再次掃描排除 9:41／原生鍵盤後為 0 個未套樣式層。 |
| P1 · H-01 | 已完成 | D6／D7／D10／D10.a 的 repeat／direction controls 換為 8 個 Standard／Enabled／Small（36×36）Button/Icon instances，圖示為 `icon/repeat`／`icon/direction-forward`；刪除手刻按鈕並逐張截圖。 |
| P1 · H-03 | 已完成 | D8、D9、B10 的 Recenter／FitRoute 視覺 overrides 清回 floating surface 與 separator；D10.a 讀回已符合 master。D8／D9／B10／D10.a 截圖複核。 |
| P1 · H-05 | 已完成（只核對） | B3／B4／D5／C1–C4／D19–D22 輸入欄均是近白 `#FBFBFD` token instance，無偏灰手刻輸入底。 |
| P1 · H-07 | 已完成（掃描） | Light 浮動 FitRoute／Recenter／Button/Icon／Speed chip 均綁 floating；未發現仍以 `surface/control` 或 `control/active` 作為浮動控制底色的節點。其他非浮動用途未改。 |
| P1 · H-04 | 未完成（待使用者決策） | 未改 Neutral 按鈕與 Progress 軌道；需決定是否近白加邊框，或維持目前次要灰。 |
| P3 · G08-1／G08-2 | 已完成 | 刪除「未定義 · 執行提示卡底色」及「未定義 · Dialog 說明字色」兩組 swatches、label、hex；A–F 未找到其對應裸色 paint，未新增 token。其餘 20 組未定義元件副本仍待 G08 完整整理。 |
| P3 · E-05 | 已完成 | E5 Paused Top 與 warning Toast 均為共用 instance，y=58／138、垂直間距 8 pt，兩層保留且無重疊，文字皆為 Theme。B8／B9 的 Pause pill＋warn Toast 亦為 instances、間距 8 pt，不拆除。 |
| P2 · G04／G09 | 未完成 | Group row variants 尚未新增；H-01 使用既有 36 pt variant，但 D 區其他手刻 icon 控制尚未全部替換。 |
| P2 · A-01–A-07、B-02–B-04、B-08–B-09、C-01–C-02、C-04、D-01–D-04、D-09、D-11–D-16、E-01、E-04、E-07、F-01、F-04–F-06 | 未完成 | 逐票狀態見上方 frame 表。B3／B4 右緣裁切及 C1／C4 黑圓視覺已修正／複核；Group/List row、按鈕與其他各票驗收尚未全部完成。 |

**A 區後續更新（2026-10-28）**：R08（`313:28214`）由使用者標示設計更新完成，本輪截圖核對，未修改。R01／R02／R03／R07 僅讀回使用者已完成的設計；R04、R04.a、R05 本輪有排版更新。

**第二輪改動 node IDs**：
- D10：`238:9223`、`238:9632`、`238:9222`。
- H-01 新 Button/Icon instances：D6 `313:30788`／`313:30795`；D7 `313:30803`／`313:30810`；D10 `313:30818`／`313:30825`；D10.a `313:30833`／`313:30840`。
- B3：空欄 value text `I313:29315;313:29305;268:22301`、隱藏 Clear instance `I313:29315;313:29306`。
- B3／B4 列表底：`313:30848`、`313:30849`（card surface，綁 `surface/card`）。
- Theme text：`I303:26673;303:26660`、`I303:26677;303:26660`、`I303:26681;303:26660`、`I303:26685;303:26660`。
- H-03 map controls：`238:9620`、`227:17099`、`238:9626`、`227:17108`、`222:13816`。
- G08 swatches／labels 刪除：`295:26456`–`295:26462`。

**A 區本輪變更 node IDs**：R04 `121:51277`、`121:51278`、`121:51279`、`121:51281`、`121:51284`、`121:51286`、`121:51289`、`121:51291`、`121:51293`、`286:24701`、`313:29256`、`315:31182`；R04.a `222:10431`、`222:12361`、`315:31187`、`315:31188`、`315:31191`、`315:31201`、`315:31206`、`315:31208`、`315:31209`、`315:31215`、`315:31194`、`315:31189`、`315:31199`、`315:31204`；R05 `123:57062`、`123:57097`、`123:57098`、`123:57099`、`123:57100`、`123:57102`、`123:57103`、`123:57104`、`123:57105`、`123:57106`、`123:57108`、`123:57109`、`123:57110`、`123:57111`、`123:57112`、`123:57115`；刪除空白佔位 `123:57147`、`123:57148`。

未修改 Variable／Variable collection、色票板、Dark frame、App，未 commit；未新增 prototype；本輪無 App 行為或裝置驗證。
