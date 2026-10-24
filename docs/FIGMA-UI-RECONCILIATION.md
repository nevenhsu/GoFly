# GoFly Figma 與 UI 規格對照

核對日期：2026-10-23。核對方式：本機 Figma Desktop Bridge（WebSocket）讀取文件樹、畫面註記及代表性畫面；未修改 Figma。這份文件記錄目前 Figma 頁面與開發規格的對應、差異和缺漏。**視覺衝突以對應 Figma 畫面為準，並在同一工作更新規格；行為、交易安全、無障礙及已實作狀態仍須分開記錄。**

## Figma 頁面對應

| Figma 頁面 | 對應文件 | 用途與結論 |
| --- | --- | --- |
| `00 · 品牌與基礎元件` | [`IOS-UI-DESIGN.md`](IOS-UI-DESIGN.md)、[`MAC-UI-DESIGN.md`](MAC-UI-DESIGN.md) | 品牌、基礎元件與共用 token 參考；平台新版畫面細節以 04／05 為準。 |
| `01 · iOS App` | [`DESIGN.md`](../DESIGN.md)、[`IOS-UI-DESIGN.md`](IOS-UI-DESIGN.md) | 舊版 iOS 流程；現行 UI 已由 04 改版頁取代，不與新版規格混用。 |
| `02 · Mac App` | [`MAC-UI-DESIGN.md`](MAC-UI-DESIGN.md) | 舊版 Mac 流程；現行 Mac 改版由 05 頁取代。 |
| `04 · iOS Redesign（Google Maps 參考）` | [`IOS-UI-DESIGN.md`](IOS-UI-DESIGN.md) | [Figma 頁面](https://www.figma.com/design/RtPV8PXCQJ2WXK3jk3kPrq/GoFly-%C2%B7-UI-%E7%B7%9A%E6%A1%86%E8%A8%8E%E8%AB%96?node-id=121-50359)；iOS 現行視覺主來源；細節見下方逐區對照。 |
| `05 · Mac Redesign（新版）` | [`MAC-UI-DESIGN.md`](MAC-UI-DESIGN.md) | [Figma 頁面](https://www.figma.com/design/RtPV8PXCQJ2WXK3jk3kPrq/GoFly-%C2%B7-UI-%E7%B7%9A%E6%A1%86%E8%A8%8E%E8%AB%96?node-id=123-61504)；Mac 現行視覺主來源；M1、M2、M3 各有淺色與深色版本。 |
| `Bug Report` | [`FIGMA-BUG-REPORT-FIX-PLAN.md`](FIGMA-BUG-REPORT-FIX-PLAN.md) | 已依 13 則釘在 8 張截圖的留言整理；本次實作範圍只採納該頁回報，舊 `01 · iOS App` 留言不納入。實作與真機驗收狀態以修正計劃紀錄為準。 |

## 04 · iOS Redesign 對照

以下畫面數不含 `0 · 共用元件` 元件板，也不代表程式已實作或驗收。

| 區域 | Figma 畫面 | 規格對照與差異 |
| --- | --- | --- |
| `0 · 共用元件` | token、按鈕、狀態、輸入與地圖元件板 | IOS 視覺 token 與規格相符；地圖位置箭頭包含 `RealArrow / 真實位置（實心藍）`（iOS systemBlue `#007AFF` 實心向量箭頭搭配白色外框與微陰影），與 `SimArrow / 模擬位置（實心）`、等待（50%）並列；StatusPill 狀態標籤全面更新為標準五態：`啟動(灰)`、`模擬中(綠)`、`暫停(黃)`、`停止(灰)`、`連線中斷(紅)`。已正式將 `STATUS · BANNER / SNACKBAR / PILL`（包含 Toast danger/warn/success、Snackbar、StatusPill 5 態，淺深共 20 個原元件）全面建立為標準 Auto Layout 規格，配置精確邊緣 padding（Toast 左右 14 pt / 上下 12 pt、Snackbar 左右 14 pt / 上下 10 pt、StatusPill 左右 12 pt / 上下 6 pt），Toast 邊線統一以元件本體 strokes 宣告，移除獨立固定框架，確保邊線與底色長寬 100% 同步完全對齊。深色主題背景色全面採用 100% 實心無透明度（opacity: 1）且較淺的 elevated surface，元件內部文字、圖示與按鈕高對比對齊，供全檔所有 UI frame 引用。`INPUTS · CONTROLS` 正式建立 `Dark · Check button / on`（高對比白底黑勾，24×24 pt）與 `Dark · Check button / off`（`secondarySystemBackground` `#2C2C2E` 底加 `#8E8E93` 邊框，24×24 pt）共用元件，供多選模式勾選按鈕引用。 |
| `A · 啟動與首次引導` | R01–R07（7 張） | 全面重新依序編號：Row 1 為首次引導 UI flow（R01–R05 共 5 張：R01 啟動、R02 定位權限、R03 定位已允許、R04 設定 VPN 通道、R05 連線說明）；Row 2 為首次引導異常狀態 UI（R06 原 R04.a，首次引導 3／3 · VPN 通道失敗 / toast 提示，水平置中 error toast 對齊 B7 樣式與顏色，帶「重試」按鈕；R07 原 R04.b，首次引導 / 連接 Mac Setup（配對裝置簽名），UI 排版對齊 R02，中央為極簡 Mac 配對圖示與「尚未配對」狀態標籤，底部移除冗餘按鈕）。淺色與深色 A 區均為 7 張對齊。與畫面相符。 |
| `B · 地圖、搜尋、地點、瞬移` | B1–B10（10 張） | 全面重新依序編號：Row 1 為瞬移 UI flow（B1–B6 共 6 張：B1 sheet 收合、B2 sheet 半開、B3 全螢幕搜尋空輸入、B4 搜尋座標與結果、B5 地點 sheet 點地圖放 Pin、B6 瞬移成功 snackbar）；Row 2 為瞬移失敗、中斷恢復與未連接 Wi-Fi UI（B7–B10 共 4 張：B7 瞬移失敗 toast，動作按鈕為「重連」，底層地點 sheet 改為高度最窄 76 pt，Go 停用；B8 瞬移中斷恢復 Resume UI，斷連後有真實 GPS，底層面板顯示「目前位置」，箭頭為實心藍 RealArrow；B9 原 B8.a，瞬移中斷 / 最後模擬位置，斷連後無真實 GPS，底層顯示「最後模擬位置」，箭頭轉為灰色；B10 原 B7.a / R01.a，地圖首頁 / 未連接 Wi-Fi error toast，水平置中 x: 16, w: 361, y: 156 pt 置於狀態 pill 下方，實心無透明度）。淺色與深色 B 區均為 10 張完整對齊。 |
| `C · 最愛地點` | C1–C4（4 張） | C1 最愛地點清單、C2 編輯最愛 sheet（修正 Dark C2 命名 typo `v` 回復完整名稱）、C3 多選模式 / 批次刪除（Dark C3 佈局與 C3 對齊：移除多選模式下不應存在之每列 star icon 星號按鈕，文字與分隔線起始位置靠齊勾選圈至 x: 43 pt；深色勾選圈按鈕選取狀態已全面替換為 `Dark · Check button / on` 共用元件實例；未選取狀態底色採用 `secondarySystemBackground` `#2C2C2E`、邊框採用 `#8E8E93`，不再透明或與 App 黑色背景混同）、C4 刪除後可復原（標示刪除後約 5 秒可復原；舊規格曾寫 2 秒，現已更正為約 5 秒）。淺色與深色 C 區均為 4 張對齊。 |
| `D · 路線` | D1–D22、D6.a（淺色 23 張、深色 23 張） | 全面重新依序編號：Row 1 Route UI flow（D1–D7 共 7 張：D1 新增路線初始狀態；D2 多停靠點滑動容器；D3 panel 收合高度最窄 76 pt；D4 Pin 設定選中的路線地點；D5 選擇終點點選即回填（頂部「正在選：終點」chip 同行最右側補上「最愛地點」純文字按鈕，點擊開啟最愛地點清單；「最近搜尋」右側補上「清空記錄」純文字按鈕；Dark D5 移除舊版靜態內嵌的最愛地點與多餘點位，淺深色結構 100% 完全對齊）；D6 路線執行模式；D7 設定移動時速 slider sheet，底層背景正式對齊 D6 路線執行模式（因僅路線運行中之控制列才配置時速 pill button），覆蓋 40% Dim overlay 並滑出半開 sheet，配置 4 檔快選膠囊：🚶 5、🚲 25、🛵 50、🚗 100 km/h，預設為 🚲 25，數值與 Slider 完整連動；Dark D6/D6.a 面板已同步補齊高對比深色 `Controls row / 來回·方向·時速`，深色已補齊 Dark D2、Dark D3、Dark D4，且 Dark D5/D6/D7 與對應說明文字水平座標完全與淺色對齊）；Row 2 路線模式狀態 UI（D8–D10、D6.a 共 4 張：D8 無法規劃路線 error toast，帶「重試」按鈕；D9 刪除路線地點 success toast，浮動於 BottomSheet 上方 y: 366 pt 帶「還原」按鈕；D10 路線中斷恢復 Resume UI，Toast 排版為 361 × 80 pt；D6.a 路線執行 / 確認結束 UI 浮窗，位於 x: 1387, y: 1380，覆蓋 35% Dim overlay 並居中彈出 320 pt 圓角 20 pt Alert Dialog，配置「取消」與「結束路線」危險紅色按鈕，防止誤觸結束進行中模擬）；Row 3 匯入路線 flow（D11–D18 共 8 張：D11 已匯入路線 GPX；D12 點選路線動作選單；D13 查看全部點位唯讀；D14 匯出系統分享 sheet；D15 匯入路線超過 10 點折疊點位；D16 匯入 GPX 系統檔案選擇器；D17 匯入成功 snackbar；D18 匯入失敗 toast 提示）；Row 4 最愛路線 flow（D19–D22 共 4 張：D19 最愛路線清單；D20 新增最愛路線 sheet；D21 最愛路線清單多選模式；D22 刪除路線 success toast，浮動於底部刪除 (2) 按鈕上方 y: 618 pt 帶「還原」按鈕；Dark D21 與 Dark D22 已選取勾選按鈕已全面替換為 `Dark · Check button / on` 共用元件實例，修正原先黑底混淆問題，與 Dark C3 統一高對比白底黑勾）。淺色與深色 D 區均為 23 張完整對齊。<br><br>**2026-10-24 StatusPill 更新**：D 區與 Dark D 區左上角已全面補齊標準 StatusPill 元件 instance：D1–D4、D8、D9 配置 `StatusPill / 啟動`（x: 16, y: 118 pt）；D6 執行模式與 D7 時速設定底層配置 `StatusPill / 模擬中`（x: 16, y: 140 pt，D7 置於 Dim overlay 之下保持畫面底層完整性）；D6.a 結束確認浮窗配置 `StatusPill / 停止`（x: 16, y: 140 pt，置於 Dim overlay 之下保持畫面底層完整性）；D10 中斷恢復配置 `StatusPill / 暫停`（x: 16, y: 140 pt）。D8 Toast 下移至 y: 156 pt（與 B7/B8 規範一致保持 8 pt 間距），D10 Toast 下移至 y: 178 pt 消除重疊。依使用者指示，D5（全螢幕選點搜尋）與 D11 以後（GPX 匯入與最愛路線清單 flow）不放置 StatusPill。淺色與深色共 20 個 frame 同步完成並經渲染驗證。 |
| `E · 搖桿與漫步` | E1–E5（5 張） | 全面重新依序編號：Row 1 搖桿與漫步 UI flow（E1–E4 共 4 張：E1 搖桿待命，Speed row 預設時速更新為 25 km/h；E2 漫步執行模式，頂部深色指示卡左側對齊 D6 配置實心導航箭頭 nav，指示文字更新為 25 km/h，右側新增「更換」outlined icon button，點擊會隨機一個新的目的地，且右側線框按鈕明確區隔左側填色圖示容器；E3 搖桿設定時速 sheet，共用 4 檔快選膠囊：🚶 5、🚲 25、🛵 50、🚗 100 km/h，預設為 🚲 25；E4 漫步目的地 Pin 獨立地點 card，尺寸 361 × 188 pt）；Row 2 漫步模式狀態 UI（E5 搖桿漫步中斷 / 恢復 Resume UI，Toast 符合 361 × 80 pt 標準，Speed chip 預設為 25）。淺色與深色 E 區均為 5 張完整對齊。 |
| `F · 設定與共用規則` | F1–F9（9 張） | 文件涵蓋設定首頁與定位、VPN、背景、語言、外觀、裝置簽名子頁；`F1 · 設定首頁` 裝置服務卡之狀態標籤已更新為標準 status pill UI（`StatusPill / 啟動` 灰點，移除舊版淡綠底色，對齊 0 區規格）；`F3 · 規則參考 · 狀態與錯誤呈現` 之 Toast UI（danger、warn、success）與 Snackbar 已全面對齊 `0 · 共用元件` Component 標準（寬度 361 pt、居中 x: 16 pt、Auto Layout 邊緣 padding 與動作/關閉按鈕精確對齊，全面採用元件 instance 呈現，消除過往純紅純橘實心底色衝突）；淺色與深色 F 區均已同步完成。與畫面內容相符。 |


淺色畫面共 58 張（A 7、B 10、C 4、D 23、E 5、F 9）；深色畫面共 58 張（A 7、B 10、C 4、D 23、E 5、F 9），淺深色畫面數與結構 100% 完全對齊。深色 D 區 Row 1 已補齊 Dark D2、Dark D3、Dark D4，並將 Dark D5、D6、D7 及說明文字右移對齊標準欄位（x: 1828、2269、2710 pt）；Row 2 已補齊 D6.a 與 Dark D6.a 確認結束浮窗（x: 1387, y: 1380 pt）。全檔 Toast、Snackbar 與 StatusPill 已完成 Component 元件化與所有 UI frame 實例替換。

2026-10-24 規格確認：D7／E3 時速設定半開 sheet 正式統一為 4 檔快選膠囊（🚶 5、🚲 25、🛵 50、🚗 100 km/h，預設為 🚲 25），Figma D7、E3、Dark D7、Dark E3 之 UI frame、說明文字與預設選中狀態已全數完成修改與視覺核對，舊版 5/15/40/60 與 5/20/60/120 註解衝突已全面排除。依 2026-10-24 使用者最新指示，D7（設定移動時速 / slider sheet）之底層背景全面由 D1 改為 D6（路線執行模式），因只有運行中之路線控制列才具備設定時速的 pill button（Speed chip「⏱ 9 ›」），並同步修復 Dark D6 與 Dark D6.a 面板控制列（補齊高對比深色 `Controls row / 來回·方向·時速`，解除原先殘留之舊版 Round trip 衝突），D7 淺深色說明文字與畫面經渲染導出驗證 100% 一致。Figma 中名為 D4a／E3a 的舊註解，以新版 D4／E3 畫面為準。

## 05 · Mac Redesign 對照

Figma 與規格的畫面數一致：淺色、深色各 34 張；M1 環境設定 E01–E08 共 8 張、M2 首次安裝 I01–I09 共 9 張、M3 裝置管理 G01–G17 共 17 張。新版 Mac 視覺與流程規格已依此分節。舊 `02 · Mac App` 畫面不再作新版基準。

唯一已確認的跨規格差異是 M2 I09 的「USB 中斷後從頭安裝、重建配對」敘述，和目前安裝交易規則不一致。實際寫入中斷須保留原 `setupID`，先查 status，只在明確可續時 resume；因此 I09 的畫面文案不可改變實際交易流程。詳見 [`MAC-UI-DESIGN.md`](MAC-UI-DESIGN.md) 與 [`AI-INSTALL.md`](AI-INSTALL.md)。

## 未來更新方式

每次 UI 工作先查閱對應平台的 04 或 05 頁及當前畫面；修改規格時列出畫面代號、差異、採納的 Figma 畫面規則，以及未實作／未驗收項目。若畫面與 Figma 註解彼此衝突，記錄該差異並以畫面為視覺依據；不要把不存在的深色或其他狀態寫成已設計。

## 2026-10-24 使用者確認：三模式 session pill 五態（Figma 待核對／同步）

瞬移／固定定位、路線、搖桿（含漫步）與設定服務 pill 共用：啟動（灰）、模擬中（綠）、暫停（黃）、停止（灰）、連線中斷（紅）。前四態都保有連線 session；停止模擬不等同 disconnect。此需求取代舊「服務待命／執行中／已暫停／受限」用詞，正常探測不造成 pill 切態。詳見 [iOS 五態規格](IOS-UI-DESIGN.md#2026-10-24-三模式-session-pill-五態規格使用者確認待實作)。

本次只同步使用者確認的需求與驗收，未重新讀取或修改 Figma，不能宣稱目前元件板、各模式及淺深色畫面已有完整五態。既有對照表是先前核對紀錄；文案、黃色語意 token 及缺少的變體須於實作前按目前 iOS 改版頁核對，App 實作及實機驗證均待完成。

### 2026-10-24 行為補充：自動續行與位置補間

使用者確認：重連成功後，斷線前正在執行且未被使用者暫停／停止的有效任務應自動續行；使用者暫停／停止、新任務取代及執行資格失效仍阻止舊任務復活。路線與漫步的 GPS 模擬箭頭位置更新須有補間移動與平滑轉向，正常 pending／探測不打斷動畫。此為跨模式行為與驗收更新，詳見 iOS 規格同日章節；不由靜態線框推定已實作或實機通過，本次未修改 Figma 或新增 prototype。

### 2026-10-24 行為補充：任務中自動 tunnel／session 修復

使用者要求三模式有效任務運行中斷線，自動 reset tunnel、重建 session 並接續原任務；修復全程保留紅色斷線狀態，原任務有效續行且取得定位 ACK 才恢復綠色模擬中。使用者暫停／停止優先於自動續行，流程需序列化且有重試上限。詳細順序、正常情境驗證與驗收見 iOS 規格同日章節；此為行為更新，本次未修改 Figma，尚未實作或實機驗證。

2026-10-24 範圍補充：本次只新增正常 App 操作與實際連線／服務結果所需的判斷及測試；不加入不可達內部狀態或非正常呼叫的防禦邏輯、全組合故障注入。具體範圍依 iOS 規格同日補充。

2026-10-24 模式切換補充：正常操作會先暫停路線／漫步再切換，方案與驗收依此流程，不新增執行中跨模式搶占／交錯的競態防禦或測試；切回原模式不自動續行。此為行為範圍更新，本次未修改 Figma。

2026-10-24 英文更新（使用者確認）：五態依序為啟動／Standby、模擬中／Running、暫停／Paused、停止／Stopped、連線中斷／Error。這是翻譯對應，沒有新增狀態或放寬斷線判斷；本次未同步修改 Figma 英文變體。

2026-10-24 最新確認取代較早第五態：繁中「錯誤」／英文 Error（紅），泛指所有共用狀態錯誤。其餘為啟動／Standby、模擬中／Running、暫停／Paused、停止／Stopped。具體連線中斷仍是 Error 的原因之一；本次未修改 Figma，第五態中英文與各變體須再同步，不能沿用先前連線專用標籤宣稱完成。

2026-10-24 Figma UI 更新：
1. **SearchField 視覺樣式對齊**：
   - `SearchField / focused`：藍色外框（Light: `#007AFF` 1.5pt、Dark: `#0A84FF` 1.5pt，caret 同步藍色），底色淺化（Light: `#F2F2F7` systemGray6、Dark: `#3A3A3C` systemGray4）。
   - `SearchField / normal`：底色同步淺化（Light: `#F2F2F7`、Dark: `#3A3A3C`）。
   - 全頁面 Light／Dark 各 14 處（共 28 處）SearchField 均已同步完成。
2. **Dark Theme STATUS · BANNER / SNACKBAR / PILL 不透明與底色調整**：
   - 所有 Dark Toast、Snackbar 與 StatusPill 背景色全面改為 100% 實心無透明度（`opacity: 1.0`，無半透明 alpha、無混合模式），底色大幅淺化提升在純黑與深色面板上的清晰度：
     - Danger Toast：底色 `#4D272A`，外框實心 `#FF453A`（1.0 opacity）。
     - Warning Toast：底色 `#523E1B`，外框實心 `#FF9F0A`（1.0 opacity）。
     - Success Toast：底色 `#244B2D`，外框實心 `#30D158`（1.0 opacity）。
     - Snackbar：底色 `#3A3A3C`，外框實心 `#545458`（1.0 opacity）。
     - StatusPills（啟動／模擬中／暫停／停止／連線中斷）：底色 `#3A3A3C`，外框實心 `#545458`（1.0 opacity）。
   - 所有在 UI frame 中的 32 處 Dark STATUS 元件實例均同步更新。
3. **INPUTS · CONTROLS 全面轉換為 Figma 共用元件與實例替換**：
   - `0 · 共用元件（正式版 token）` 與 `Dark · 0 · 共用元件（正式版 token）` 內之 `INPUTS · CONTROLS`（共 34 個元件）已全數建立為 Master `COMPONENT`：
     - SearchBar / 浮動
     - SearchField / focused、SearchField / normal
     - Switch / on、Switch / off
     - Slider / 原生黑白
     - Recenter、Follow、Progress
     - SimArrow / 模擬位置（實心）、RealArrow / 真實位置（實心藍）、SimArrow / 模擬位置（等待 50%）
     - CandidatePin / 候選 Pin、DestPin / 目前目的地（空心）
     - TabBar / 瞬移・路線・搖桿（等寬）
     - Joystick / 重新設計
     - List rows
   - 全頁面 UI frame 已替換為上述共用元件之實例（總計 290 處 Component Instances），文字覆蓋（搜尋框 query、地名、座標）、狀態高亮與位置完整保留，未來在 Section 0 調整即可全局同步。
4. **SearchField / focused 寬度跑版修復**：
   - 全螢幕搜尋畫面（Light/Dark B3、B4、D5）因左側具有返回鍵（`x: 8, w: 44`），搜尋輸入框起始點為 `x: 52`。
   - 原先元件預設寬度 361 pt 導致右邊界溢出至 413 pt（超出螢幕 393 pt 邊緣 20 pt）。
   - 已將上述 6 個畫面的 `SearchField / focused` 實例寬度統一修正為 `321 pt`（`x: 52`，右邊界 `373 pt`，保留右側邊距 20 pt），並將 Master Component 內 `icon / x` 之 constraints 設為 `horizontal: MAX`，自動貼齊右側 14 pt，解決溢出跑版問題。
5. **TabBar / 瞬移・路線・搖桿（等寬）三模式變體建構與全頁面實例模式同步**：
   - **Master ComponentSet 建立**：在 `0 · 共用元件（正式版 token）` 與 `Dark · 0 · 共用元件（正式版 token）` 分別將 `TabBar / 瞬移・路線・搖桿（等寬）` 與 `Dark · TabBar / 瞬移・路線・搖桿（等寬）` 升級為包含 `Mode=瞬移`、`Mode=路線`、`Mode=搖桿` 三態之 Master ComponentSet，保留既有 Component ID 與實例繼承。
   - **視覺樣式規則（完全對齊 B1 瞬移，無 filled color，僅 line 變深）**：
     - 選中模式（Active Tab）：圖示為純線框線條加深加粗（`strokeWeight: 2.29 pt`、Light: `#000000`、Dark: `#FFFFFF`，`strokeCap: ROUND`、`strokeJoin: ROUND`，`fills: []` 無填色），文字標籤加深（`PingFang TC Medium 10 pt`、Light: `#000000`、Dark: `#FFFFFF`），子圖層命名統一為 `Tab / <模式> / selected`。
     - 未選中模式（Inactive Tabs）：圖示為純線框細線（`strokeWeight: 1.88 pt`、Light: `#999999` `rgb(0.6,0.6,0.6)`、Dark: `#8E8E93` `rgb(0.56,0.56,0.58)`，`fills: []` 無填色），文字標籤次要色（`PingFang TC Medium 10 pt`、Light: `#999999`、Dark: `#8E8E93`），子圖層命名為 `Tab / <模式>`。
     - 全 TabBar 41 個實例已全面清除所有向量填色 overrides（清除 207 個遺留填色），確保全檔無任何藍色或灰色 filled color，完全對齊 `B1 · 地圖首頁 / sheet 收合`。
   - **元件板展示配置**：
     - Light 與 Dark 元件板寬度自動拓寬至 2269 pt（精確對齊下方 Section A 寬度 2269 pt），於右側 `x: 1800, y: 330` 配置完整的 TabBar ComponentSet 垂直展示，並附帶 `TAB BAR · 瞬移／路線／搖桿（等寬）` 專屬標題與說明文字。
     - 原元件座標 `x: 1186, y: 790` 保留單一實例預覽（`Mode=瞬移`），維持元件板版面無空白缺漏。
   - **UI 頁面實例模式全面連動（共 41 處）**：
     - Section B 地圖首頁／瞬移（8 處 Light + 8 處 Dark）：統一保持 `Mode=瞬移`（瞬移圖示與文字加深，其餘淡灰）。
     - Section D 路線規劃（8 處 Light + 8 處 Dark，含 D1、D15、D7、D4、D3、D8、D9、D2）：統一切換為 `Mode=路線`，路線圖示與文字加深，瞬移與搖桿維持灰色。
     - Section E 搖桿與漫步（4 處 Light + 3 處 Dark，含 E1、E3、E4、E5）：統一切換為 `Mode=搖桿`，搖桿圖示與文字加深，瞬移與路線維持灰色。
