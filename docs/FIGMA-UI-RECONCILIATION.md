# GoFly Figma 與 UI 規格對照

核對日期：2026-10-28。核對方式：本機 Figma Desktop Bridge（WebSocket）讀取文件樹、畫面註記及代表性畫面；本次依使用者指示在 04 建立 Dark UI／按鈕板的 Light 版本、移除舊正式版 token 區、保留既有畫面元件引用，並將 Light／Dark SearchBar Settings 按鈕更新為 48 × 48 pt；Icon 與 Typography 目錄亦位於 04。這份文件記錄目前 Figma 頁面與開發規格的對應、差異和缺漏。**視覺衝突以對應 Figma 畫面為準，並在同一工作更新規格；行為、交易安全、無障礙及已實作狀態仍須分開記錄。**

## Figma 頁面對應

| Figma 頁面 | 對應文件 | 用途與結論 |
| --- | --- | --- |
| `00 · 品牌與基礎元件` | [`IOS-UI-DESIGN.md`](IOS-UI-DESIGN.md)、[`MAC-UI-DESIGN.md`](MAC-UI-DESIGN.md) | 品牌、基礎元件與共用 token 參考；平台新版畫面細節以 04／05 為準。 |
| `01 · iOS App` | [`DESIGN.md`](../DESIGN.md)、[`IOS-UI-DESIGN.md`](IOS-UI-DESIGN.md) | 舊版 iOS 流程；現行 UI 已由 04 改版頁取代，不與新版規格混用。 |
| `02 · Mac App` | [`MAC-UI-DESIGN.md`](MAC-UI-DESIGN.md) | 舊版 Mac 流程；現行 Mac 改版由 05 頁取代。 |
| `04 · iOS Redesign（Google Maps 參考）` | [`IOS-UI-DESIGN.md`](IOS-UI-DESIGN.md) | [Figma 頁面](https://www.figma.com/design/RtPV8PXCQJ2WXK3jk3kPrq/GoFly-%C2%B7-UI-%E7%B7%9A%E6%A1%86%E8%A8%8E%E8%AB%96?node-id=121-50359)；iOS 現行視覺主來源；含 Common Color 與 Light／Dark Color Scheme 色票板、Light／Dark UI／按鈕元件板、Icon 目錄及 Typography Theme text styles；舊正式版 token 區已刪除；細節見下方逐區對照。 |
| `05 · Mac Redesign（新版）` | [`MAC-UI-DESIGN.md`](MAC-UI-DESIGN.md) | [Figma 頁面](https://www.figma.com/design/RtPV8PXCQJ2WXK3jk3kPrq/GoFly-%C2%B7-UI-%E7%B7%9A%E6%A1%86%E8%A8%8E%E8%AB%96?node-id=123-61504)；Mac 現行視覺主來源；M1、M2、M3 各有淺色與深色版本。 |
| `Bug Report` | [`FIGMA-BUG-REPORT-FIX-PLAN.md`](FIGMA-BUG-REPORT-FIX-PLAN.md) | 已依 13 則釘在 8 張截圖的留言整理；本次實作範圍只採納該頁回報，舊 `01 · iOS App` 留言不納入。實作與真機驗收狀態以修正計劃紀錄為準。 |

## 04 · iOS Redesign 對照

以下畫面數不含 `0 · 共用元件` 元件板，也不代表程式已實作或驗收。

| 區域 | Figma 畫面 | 規格對照與差異 |
| --- | --- | --- |
| `0 · 共用元件` | Light／Dark token、按鈕、狀態、輸入與地圖元件板；Light／Dark 均有 LocationCard、Top / 執行指示共用元件 | 04 現有 `Light · 0 · 共用元件`、`Light · 0 · 共用元件（按鈕）` 與其 Dark 對應板；Light 使用 `GoFly iOS / Light Theme`，Dark 使用 `GoFly iOS / Dark Theme`。StatusPill 為五態且 Light 全部白底；Light Primary Active 的 Icon + Text 與 Text 四種尺寸均為藍底白字（`#007AFF`）；Neutral Active／Disabled 為 `#D1D1D6`／`#F9F9F9`。Dark 可復原 Snackbar 與自動消失款使用相同灰邊及陰影。Light LocationCard 只留 `Layout=Route`，由 C Go、B Star／Copy／Clear variants 組裝，使用 `#F9F9F9F2` 95% `color/surface/overlay/card` 與 12 pt Background Blur；Top / 執行指示有 Active／Paused Light variants。28 個仍被舊畫面引用的原母元件收在 Light 主板下方，249 個 instance ID 均保留。舊 `0 · 共用元件（正式版 token）` 已刪除；Icon／Typography 目錄分列。 |
| `A · 啟動與首次引導` | R01–R07（7 張） | 全面重新依序編號：Row 1 為首次引導 UI flow（R01–R05 共 5 張：R01 啟動、R02 定位權限、R03 定位已允許、R04 設定 VPN 通道、R05 連線說明）；Row 2 為首次引導異常狀態 UI（R06 原 R04.a，首次引導 3／3 · VPN 通道失敗 / toast 提示，水平置中 error toast 對齊 B7 樣式與顏色，帶「重試」按鈕；R07 原 R04.b，首次引導 / 連接 Mac Setup（配對裝置簽名），UI 排版對齊 R02，中央為極簡 Mac 配對圖示與「尚未配對」狀態標籤，底部移除冗餘按鈕）。淺色與深色 A 區均為 7 張對齊。與畫面相符。 |
| `B · 地圖、搜尋、地點、瞬移` | B1–B11（Light 11 張／Dark 10 張） | 全面重新依序編號：Row 1 為瞬移 UI flow（B1–B6 共 6 張：B1 sheet 收合、B2 sheet 半開、B3 全螢幕搜尋空輸入、B4 搜尋座標與結果、B5 地點 sheet 點地圖放 Pin、B6 瞬移成功 snackbar）；Row 2 為瞬移失敗、中斷恢復與未連接 Wi-Fi UI（B7–B10 共 4 張：B7 瞬移失敗 toast，動作按鈕為「重試」，底層 location card 為標準 361 × 188 pt，Go 使用 Light Primary Active 藍底白字（#007AFF）；B8 瞬移中斷恢復（frame 名稱含 Resume UI），底層維持標準瞬移收合面板，顯示「目前位置」、名稱、座標、收藏與複製，無底部 Resume CTA；斷連後有真實 GPS，箭頭為實心藍 RealArrow；B9 瞬移中斷／最後模擬位置（無真實 GPS），底層同樣維持標準瞬移收合面板，顯示「最後模擬位置」、名稱、座標、收藏與複製，無底部 Resume CTA，箭頭為灰色；B10 原 B7.a / R01.a，地圖首頁／未連接 Wi-Fi error toast，水平置中 x: 16, w: 361, y: 156 pt 置於狀態 pill 下方，實心無透明度）。Light B 區另有 B11「地圖首頁／連接中（建立 VPN tunnel）」；Dark B 區目前 10 張，缺少 B11 對應畫面。 |
| `C · 最愛地點` | C1–C4（4 張） | C1 最愛地點清單、C2 編輯最愛 sheet（修正 Dark C2 命名 typo `v` 回復完整名稱）、C3 多選模式 / 批次刪除（Dark C3 佈局與 C3 對齊：移除多選模式下不應存在之每列 star icon 星號按鈕，文字與分隔線起始位置靠齊勾選圈至 x: 43 pt；深色勾選圈按鈕選取狀態已全面替換為 `Dark · Check button / on` 共用元件實例；未選取狀態底色採用 `secondarySystemBackground` `#2C2C2E`、邊框採用 `#8E8E93`，不再透明或與 App 黑色背景混同；**2026-10-24 刪除按鈕移出 search field section，獨立浮動於底部搜尋欄上方 y: 670 pt，與 D21 完全一致**）、C4 刪除後可復原（標示刪除後約 5 秒可復原；舊規格曾寫 2 秒，現已更正為約 5 秒）。淺色與深色 C 區均為 4 張對齊。 |
| `D · 路線` | D1–D22、D2 拖曳排序、D6.a、D10.a（Light／Dark 各 25 張） | 全面重新依序編號：Row 1 Route UI flow（D1–D7 共 7 張：D1 新增路線初始狀態；D2 多停靠點滑動容器；D3 panel 收合高度最窄 76 pt；D4 Pin 設定選中的路線地點；D5 選擇終點點選即回填（頂部「正在選：終點」chip 同行最右側補上 22 pt 空心星號搭配 15 pt `Favorite` 文字，44 pt 高命中區與主文字色（Light `#000000`、Dark `#E5E5EA`），點擊開啟最愛地點清單；「最近搜尋」右側補上「清空記錄」純文字按鈕；Dark D5 移除舊版靜態內嵌的最愛地點與多餘點位，淺深色結構 100% 完全對齊）；D6 路線執行模式；D7 設定移動時速 slider sheet，底層背景正式對齊 D6 路線執行模式（因僅路線運行中之控制列才配置時速 pill button），覆蓋 40% Dim overlay 並滑出半開 sheet，配置 4 檔快選膠囊：步行 5、單車 25、機車 50、汽車 100 km/h（扁平圓潤風格的彩色向量插圖 `WF/Icon/speed.* (emoji style)`（透明背景、無底圖；橘紅＋深藍＋芥末黃配色，參考使用者提供的交通工具插畫風格；淺色、深色與選中膠囊皆可辨識），不用系統 emoji），預設 25，數值與 Slider 完整連動；Dark D6/D6.a 面板已同步補齊高對比深色 `Controls row / 來回·方向·時速`，深色已補齊 Dark D2、Dark D3、Dark D4，且 Dark D5/D6/D7 與對應說明文字水平座標完全與淺色對齊）；Row 2 路線模式狀態 UI（D8–D10、D10.a、D6.a 共 5 張：D8 無法規劃路線 error toast，帶「重試」按鈕；D9 刪除路線地點 success toast，浮動於 BottomSheet 上方 y: 366 pt 帶「還原」按鈕；D10 路線中斷恢復 Resume UI，Toast 排版為 361 × 80 pt；D6.a 路線執行 / 確認結束 UI 浮窗，位於 x: 1387, y: 1380，覆蓋 35% Dim overlay 並居中彈出 320 pt 圓角 20 pt Alert Dialog，配置「取消」與「結束路線」危險紅色按鈕，防止誤觸結束進行中模擬）；Row 3 匯入路線 flow（D11–D18 共 8 張：D11 已匯入路線 GPX；D12 點選路線動作選單；D13 查看全部點位唯讀；D14 匯出系統分享 sheet；D15 匯入路線超過 10 點折疊點位；D16 匯入 GPX 系統檔案選擇器；D17 匯入成功 snackbar；D18 匯入失敗 toast 提示）；Row 4 最愛路線 flow（D19–D22 共 4 張：D19 最愛路線清單；D20 新增最愛路線 sheet；D21 最愛路線清單多選模式；D22 刪除路線 success toast，浮動於底部搜尋欄上方 y: 666 pt 帶「復原」按鈕；**2026-10-24 修正 UI 佈局：D21 與 D22 全面廢除 Dragger Sheet 誤植結構，回復為 D19 標準全螢幕導覽佈局（具備 Status bar、Dynamic Island、NavBar，列表自 y: 108 pt 起算，無 Grabber）；D21 刪除按鈕移出 search field section 獨立浮動於 y: 670 pt；D22 回復標準清單移除被刪項目並置入浮動 Snackbar；淺深色完全對齊**）。Light／Dark D 區各 25 張，含 D2 拖曳排序示意及 D10.a 中斷恢復畫面。<br><br>**2026-10-24 StatusPill 更新**：D 區與 Dark D 區左上角已全面補齊標準 StatusPill 元件 instance：D1–D4、D8、D9 配置 `StatusPill / 啟動`（x: 16, y: 118 pt）；D6 執行模式與 D7 時速設定底層配置 `StatusPill / 模擬中`（x: 16, y: 140 pt，D7 置於 Dim overlay 之下保持畫面底層完整性）；D6.a 結束確認浮窗配置 `StatusPill / 停止`（x: 16, y: 140 pt，置於 Dim overlay 之下保持畫面底層完整性）；D10 中斷恢復配置 `StatusPill / 暫停`（x: 16, y: 140 pt）。D8 Toast 下移至 y: 156 pt（與 B7/B8 規範一致保持 8 pt 間距），D10 Toast 下移至 y: 178 pt 消除重疊。依使用者指示，D5（全螢幕選點搜尋）與 D11 以後（GPX 匯入與最愛路線清單 flow）不放置 StatusPill。淺色與深色共 20 個 frame 同步完成並經渲染驗證。 |
| `路線欄位互動更新（2026-10-26）` | D1、D5 | D1 渲染選中欄位，D5 渲染聚焦搜尋頁；第一次點擊選取欄位，再次點同一欄位開啟 D5。此互動沒有 prototype／線框 variant；保留 D1／D5 現有渲染作視覺準據，並只在 App 規格記錄行為。 |
| `路線檢視清單（2026-10-26 使用者確認）` | D13（僅版面參考） | Light／Dark D1 的操作列已將「反轉順序」改為無外框「檢視路線」，搭配共用 `View List Icon: list.and.chevron`（22 pt；英文 View）；D2 多停靠點狀態仍保留反轉順序。D13 現有渲染是 GPX 唯讀「查看全部點位」，App 的可編輯全螢幕路線清單仍沒有對應 wireframe；不得把 D13 標為可編輯設計已完成。`list.and.chevron` 不是 SF Symbol，App 直接匯出此元件向量為 asset `RouteList`。App 清單頁底部為小型文字按鈕「＋ 新增停靠點」（左）與「⇅ 反轉順序」（右），已移除「關閉檢視」（2026-10-26 使用者指示，Figma 未同步）。App 行為與 Figma 設計狀態分開追蹤。 |
| `E · 搖桿與漫步` | E1／E1.a／E2／E2.a／E3／E4／E5（各外觀7張） | 2026-10-24 本輪透過 Desktop Bridge 逐張讀取淺深色共14張渲染及圖層。E5 深色版沿用淺色恢復列＋tabs 結構。E4 漫步候選卡兩種外觀已改為純文字「確認」並移除播放 icon；孤立 CandidatePin 已移除。E1.a 已重畫為手動待命收合畫面，保留搜尋列、搖桿 tabs 與速度 pill；E3 狀態標籤改為標準「啟動」。上述修改均已截圖讀回，淺深色結構一致。E1/E2 保留搜尋列、tabs、150 pt 搖桿、速度 pill、自動漫步按鈕及停止／更換地點；不得改用 Switch。App 行為與裝置驗收不由 Figma 渲染推定，見[正式方案及票單](JOYSTICK-WANDER-REFACTOR-PLAN.md)與 `.scratch/gofly-joystick-wander/`。 |
| `F · 設定與共用規則` | 9 個 App frame＋F2／F3 兩個規則參考 frame | 文件涵蓋設定首頁與定位、VPN、背景、語言、外觀、裝置簽名子頁；`F1 · 設定首頁` 裝置服務卡之狀態標籤已更新為標準 status pill UI（`StatusPill / 啟動` 灰點，移除舊版淡綠底色，對齊 0 區規格）；`F3 · 規則參考 · 狀態與錯誤呈現` 之 Toast UI（danger、warn、success）與 Snackbar 已全面對齊 `0 · 共用元件` Component 標準（寬度 361 pt、居中 x: 16 pt、Auto Layout 邊緣 padding 與動作/關閉按鈕精確對齊，全面採用元件 instance 呈現，消除過往純紅純橘實心底色衝突）；淺色與深色 F 區均已同步完成。與畫面內容相符。 |


Light App 畫面共 63 張（A 7、B 11、C 4、D 25、E 7、F 9），另有 F2／F3 兩個規則參考 frame；Dark App 畫面共 62 張（A 7、B 10、C 4、D 25、E 7、F 9），另有兩個規則參考 frame。兩主題目前的畫面數差異是 Light B11「連接中（建立 VPN tunnel）」尚無 Dark 對應畫面。深色 D 區 Row 1 已補齊 Dark D2、Dark D3、Dark D4，並將 Dark D5、D6、D7 及說明文字右移對齊標準欄位（x: 1828、2269、2710 pt）；Row 2 已補齊 D6.a 與 Dark D6.a 確認結束浮窗（x: 1387, y: 1380 pt）。全檔 Toast、Snackbar 與 StatusPill 已完成 Component 元件化與所有 UI frame 實例替換。

2026-10-24 規格確認：D7／E3 時速設定半開 sheet 正式統一為 4 檔快選膠囊（步行 5、單車 25、機車 50、汽車 100 km/h（扁平圓潤風格的彩色向量插圖 `WF/Icon/speed.* (emoji style)`（透明背景、無底圖；橘紅＋深藍＋芥末黃配色，參考使用者提供的交通工具插畫風格；淺色、深色與選中膠囊皆可辨識），不用系統 emoji），預設 25），Figma D7、E3、Dark D7、Dark E3 之 UI frame、說明文字與預設選中狀態已全數完成修改與視覺核對，舊版 5/15/40/60 與 5/20/60/120 註解衝突已全面排除。依 2026-10-24 使用者最新指示，D7（設定移動時速 / slider sheet）之底層背景全面由 D1 改為 D6（路線執行模式），因只有運行中之路線控制列才具備設定時速的 pill button（Speed chip「⏱ 9 ›」），並同步修復 Dark D6 與 Dark D6.a 面板控制列（補齊高對比深色 `Controls row / 來回·方向·時速`，解除原先殘留之舊版 Round trip 衝突），D7 淺深色說明文字與畫面經渲染導出驗證 100% 一致。Figma 中名為 D4a／E3a 的舊註解，以新版 D4／E3 畫面為準。


### 2026-10-28 Light A–F frame 標準化、顏色 token 綁定與未定義元件

- 依 04 頁當前渲染整理 Light A–F 的 App frame；可互動內容的外緣統一距 frame 16 pt，根據畫面情境保留地圖、系統列、鍵盤與全螢幕 overlay 等滿版層。R04 以使用者更新後的版面為準，保留內容順序與垂直配置，只整理共用文字樣式、三步驟卡及 Primary CTA。
- Light A–F 原有 664 個文字層套用 Typography Theme；本輪再將 12 個 Light 搖桿 N／E／S／W 方位字套用 `Theme/subheadlineEmphasis`，並將 B11「連接中」套用 `Theme/footnoteEmphasis`，共 677 個本輪整理的文字層。Light 62 張 App frame 目前有 869 個可見文字層使用 Theme styles；其餘 148 個是系統時間、地圖標籤與原生鍵盤示意文字。D10 五個輔助文字亦套用對應 `Theme/*` style，並保留各自 Light Theme 顏色綁定。39 個一般按鈕改用 Light `Button / Text` 共用 variants；40 個 Light `Button / Text` master 改為水平 Auto Layout、標籤置中並維持原尺寸。Dark 畫面本輪未改動。
- 對應舊通用元件的 92 個 Light A–F instance 已換成 Light SearchBar、SearchField、StatusPill、Toast、Snackbar 與 TabBar 元件；6 個最愛路線清單星號按鈕與 D15「儲存為最愛路線」均使用 44 × 44 Light `Button / Icon` `Type=Standard, State=Enabled, Size=Large`。2026-10-28 Standard master 改為白底＋0.5 pt separator 邊，這些 instance 會隨 master 更新。B11 的「連接中」尚無標準 Light StatusPill variant，保留獨立元件並複製到「未定義」。
- 不吻合既有 variant 尺寸或結構的 8 個操作元件副本也收在「未定義」：B3 貼上、清空記錄，D5 Favorite 文字按鈕，D6 來回／方向列，D15 清空路線，D8／D9 狀態色停用開始按鈕，以及 D10「繼續」；來源畫面保留。B3 貼上圖示本身使用共用 `icon/paste-20`。
- 與元件用途相同的顏色即使只有相近色差，也直接改綁既有 Light Color Theme 語意 token；不保留近似裸色、不另建重複 token 或 Color Scheme 色票。共重新綁定 205 個 paint：包含各畫面與既有 token 色值相近的填色／描邊、D2 新增停靠點文字，以及 F6.a 時間輪盤的停用數字。B8 真實位置箭頭使用 `color/icon/outline`；19 個 SearchBar Settings 齒輪容器底色綁定 `color/surface/input`；B11 文字綁定 `color/text/primary`。逐 frame 回讀 62 張 Light App frame 的 5,194 個可見實心填色／描邊，全部綁定 `GoFly iOS / Light Theme`，沒有 Dark collection 或未綁色 paint。
- 只有兩個顏色目前找不到合適的既有語意角色：執行提示底色 `#1C1C1E`（5 個 paint）與 dialog 說明文字 `#6B6B73`（1 個 paint）。兩者沿用既有 Light Theme palette 值，標示為「色彩待確認」放進「未定義」供討論，不新增 Color Theme token。該區目前有 20 組元件副本及 2 組色票；來源畫面保留。R04 保留使用者更新後的內容順序與垂直位置。
- 驗收條件：Light A–F 一般內容外緣距 frame 為 16 pt；文字／標準按鈕使用共用 Theme／variants；相近色直接映射既有 Color Theme token；只有無合適語意角色的顏色放入「未定義」討論，且不建立新 theme token；R04 順序與垂直配置未回退。已讀回並截圖核對 R01、R02、R03、R04、B1、B3、B5、B7、B8、B11、C1、C2、D1、D2、D6、D8、D9、D10、D15、E1、F1、F3、F6.a 及未定義區。此為 Figma 靜態 wireframe 整理，未修改 App、未加 prototype，未做裝置驗證。

### 2026-10-28 Info Slate 與 Light Home Indicator

- Light／Dark Color Scheme 的 Info Main／Hover／Active 與 Text 改為 Slate 灰藍 `#475569`；各主題原有 Background、Border、Contrast text 保留。Figma 色票 HEX 與 `IOS-COLOR-SCHEME.json` 同步；此色彩用於低干擾的中性資訊／系統通知參考，未新增不存在的 Info action button。
- Light A–F 內 65 個 Home indicator（含 sheet 內指示條）統一重綁到既有 Light Theme palette token `color/palette/3c3c43-3c3c43`（`#3C3C43`）；Dark Home indicator 不變。
- 驗收：Light／Dark Info 主色與文字色標示 `#475569`；65 個 Light Home indicator 均為 `#3C3C43` 且保留 theme variable binding；Dark Home indicator 及 R04 版面／位置未改。Figma 色票與 R04 截圖讀回確認；未修改 App，未做裝置驗證。

### 2026-10-28 Color Scheme 優化、R07 icon 與 D23

- Light／Dark Color Scheme 調整：Light 主要色 `#0071E3`、連結 `#0066CC`、文字 `#1C1C1E`／`#6C6C70`／`#8E8E93`／`#AEAEB2`；Dark 主要 `#005FC7`、危險 `#B3352F`、輸入底 `#151517`。重複值改 alias，`action/primary/filled-*` 已刪除；對比目標一般文字 ≥ 4.5。細節與未完成項見 [FIGMA-LIGHT-UI-TICKETS.md](FIGMA-LIGHT-UI-TICKETS.md)「執行狀態」；[IOS-COLOR-SCHEME.json](IOS-COLOR-SCHEME.json) 已同步。這是 Figma 設計更新，App 色彩程式未同步、無裝置驗證。
- Light `StatusPill / 停止` 與 `/ 啟動` 樣式相同，已刪除前者（無 instance）；「停止」狀態以 `StatusPill / 啟動` 覆蓋文字呈現；Dark `StatusPill / 停止` 同樣重複，已一併刪除（無 instance）。
- R07（Light／Dark）Hero 改為淺底圓角卡＋線條筆電 icon（`icon/mac`）；Dark R02／R03／R07 Hero 底色修正。
- **層次整併（2026-10-28 使用者確認）**：背景／Surface／Map overlay 整併為 4 級，相鄰對比 ≥ 1.2。Light：canvas `#F2F2F7`、card `#FFFFFF`、control `#E5E5EA`、active `#D1D1D6`；Dark：canvas `#1C1C1E`、card `#2C2C2E`、control `#3A3A3C`、active `#4A4A4D`（Dark canvas 避開 section 底色 `#0E0E0E`）。sheet、bottom panel 用 card 級（`surface/card`；疊地圖用 `surface/overlay/sheet`，95% 透明）；Panel 用 control 級（`surface/overlay/panel`）；BACKGROUND 只指畫面最底層 canvas。Map overlay 縮為 card、panel（control）兩級，background／sheet／tab-panel 與 card 同值；`surface/navigation`、`surface/input`（Light）alias card，Dark input alias `surface/control/active`（凸起感，輸入欄比卡片亮，與 Text Field 元件一致），`surface/disabled`、`surface/control/disabled` alias control。色票板 BACKGROUND、SURFACE、MAP OVERLAY、ACTION 已改為上述色值，[IOS-COLOR-SCHEME.json](IOS-COLOR-SCHEME.json) 同步。Light 畫面底變灰、卡片白，Dark 逐層加亮；其餘畫面逐張回歸尚未完成。
- `Button / Icon + Text` 的 star icon 修正：星形向量原本在 icon frame 內偏左上（Small 偏 2.2／2.4 pt），且比例偏小；Light／Dark 共 16 個 star frame（Neutral Active／Disabled × Small／Medium／Large 等）改為向量佔 frame 80%、幾何置中（略下移 2% 作光學補正），instance 隨 master 更新。
- Dark `Text Field / Neutral` Disabled：`surface/control/disabled` 由 alias control（`#3A3A3C`）改為獨立值 `#343437`（比 sheet／card `#2C2C2E` 亮一點點，輸入欄都在 sheet 上；與 Default／Focused 的 `#4A4A4D` 仍可分辨）；邊框仍為 `line/input/disabled`。Dark 按鈕停用態同步：`action/disabled/surface`、`surface/disabled` 改 alias `surface/control/disabled`（`#343437`），Primary／Neutral／Danger 的 Disabled 與 Active 仍可分辨；Icon 按鈕本來就用此 token。
- Dark Neutral 按鈕調亮：`surface/control/active` `#4A4A4D` → `#505054`，`action/secondary/surface` 改 alias `surface/control/active`，Button / Text Neutral 與 Icon + Text Neutral、Icon 按鈕、Text Field 同一個亮度（原 Button / Text Neutral 為 `#3A3A3C`，較暗）；Input、Neutral Active 同值。
- Dark INFO 以使用者設定的 Main `#475569`（slate-600）為基準同步其餘：Background `#1F2A37`（slate 色調深底，取代偏藍的 `#182B40`）、Text `#94A3B8`、Border `#64748B`、Contrast text `#E5E5EA`；`surface/status/info`、`line/status/info` 與色票板、JSON 同步。Light INFO 為 `#475569`／`#EDF0F4`／`#334155`／`#CBD5E1`／白字，同一色相。
- Dark SUCCESS／WARNING 降飽和（原 `#30D158`／`#FF9F0A` 過亮），Contrast text 統一 `#E5E5EA`（Dark 的「白」，不用純白）：Success Main `#2E7048`（對比 4.74）、Background `#1B2E22`、Text／icon `#6FC48B`、Border `#3E8A5A`；Warning Main `#8A5C2A`（4.59）、Background `#352A1B`、Text／icon `#DDA862`、Border `#A8742F`。`surface／line／text／icon` 的 success／warning token 同步，Dark toast、snackbar、icon 會連動變柔和（Figma 實心外框規格不變，僅色值改）；色票板與 JSON 已更新。Dark ERROR 的 Text／Border 仍為 `#FF453A`，未調整。
- Dark Toast（danger／warn／success）小字調亮：說明文字（13 pt）與關閉 ✕ 由 `text/secondary`／`icon/secondary`（`#98989D`）改綁新 token `text/status/secondary`／`icon/status/secondary`（Dark `#C7C7CC`；Light 為 alias 原 secondary，維持不變），標題與按鈕文字仍為 `text/primary`。Snackbar 只有主文字，未受影響。
- Dark SUCCESS／WARNING 再調亮（2026-10-28 使用者）：Success Main `#2E7048`→`#3A8A58`、Border `#52A072`；Warning Main `#8A5C2A`→`#A87430`、Border `#C48A3F`；Background、Text 不變。Contrast text 維持 `#E5E5EA`，對比降為約 3.4／3.2（符合 3:1 大字／粗體 UI 文字，未達 4.5；若要 4.5 需改深色文字或調暗 Main）。
- **Figma 色票庫整理（2026-10-28）**：以 CS Light／Dark 為準整理 Local variables。兩個 collection（`GoFly iOS / Light Theme`、`/ Dark Theme`）名稱集合一致（各 111 個）：語意 token（`canvas`、`surface/*`、`text/*`、`icon/*`、`line/*`、`action/*`、`control/*`、`system/*`、`primary/*`）、`map/*`、`speed/*`。每個 token 補中文用途說明；依角色限定 scope（文字 token 只出現在文字填色、line 只出現在描邊、surface／canvas／action 只出現在 frame／shape 填色，icon 為 shape 填色＋描邊）。舊 `color/palette/*` 共 40 個：未被任何畫面使用的 16 個已刪除，仍被引用的 24 個（每主題 23 個，Dark／Light 同名）改名為 `color/legacy/*`、隱藏於發佈與選色器，待逐步改綁語意 token（例：Home indicator 的 `legacy/3c3c43-3c3c43` 隨 G02 移除）。語意 token 即使暫未被畫面引用也保留，作為 CS 定義。`LocalGo / Wireframe` 舊線框 collection（19 個，色彩 12 個仍被舊頁使用）未動。Light／Dark 仍為兩個 collection，尚未合併為單一 collection 的兩個 mode（需重綁全檔，另案評估）。已截圖核對 Light／Dark A 區無變化。
- **Light CS 第二輪優化（2026-10-28）**：① control `#E5E5EA`→`#E1E1E6`（對 canvas 1.17、對 card 1.30），Map overlay panel 同步 `#E1E1E6F2`；② active `#D1D1D6`→`#BCBCC2`，與 Neutral 按鈕 `#D1D1D6` 拉開（1.24）；③ 停用態獨立：`surface/control/disabled` `#ECECF0`（不再等於 control），`surface/disabled`、`action/disabled/surface` alias 之；④ `text/tertiary` `#8E8E93`→`#7B7B80`（對白底 4.2）；⑤ 狀態色外框改實心，與 Dark 一致（danger `#D92D20`、warning `#FF9500`、success `#2E9E4F`、info `#64748B`）；⑥ INFO Background `#EDF0F4`→`#E6EDF6`（偏冷藍，與中性灰區分）。未做：control 加外框（改以拉深底色解決）。已截圖核對 Light C、D、E、按鈕板、Color Scheme；D 區 G06 底層空白、D12／D14 純黑仍待處理。Light 元件板與 Color Scheme section 底色目前為 `#F2F2F7`（使用者已改回），其標題文字維持深色。
- **色票庫第二次整理（2026-10-28）**：新增 `GoFly iOS / Common Color` collection（`common/white`、`common/black`、`common/transparent`、`common/gray/50…950`，共 14 個，值對應 [IOS-COLOR-SCHEME.json](IOS-COLOR-SCHEME.json) `primitive`），04 `Common Color` 色票板 13 個實色已改綁此 collection。移除不在 Color Scheme 的色票：每主題 23 個 `color/legacy/*`、`canvas/button-board`、`surface/button-board`，以及舊 `LocalGo / Wireframe` collection（19 個；舊 00／01 頁與 04 少量舊節點的綁定轉為原值，渲染不變）。`map/*`、`speed/*` 不在 CS 色票板但仍被 04 畫面引用，予以保留。目前 collection：Light 86、Dark 86、Common 14。
- **Dark CS 優化（2026-10-28，使用者確認全做）**：① 色票板補同步：Active `#505054`、Secondary Main `#505054`、ACTION disabled `#343437`；② Success／Warning Main 調到與 `#E5E5EA` 文字 ≥ 4.5（`#2C7347` 4.58、`#8C5D26` 4.51），Border、Text 不變；③ 連結／accent／focus 邊框 `#0A84FF`→`#4DA3FF`（對卡片 5.31、canvas 6.48），Primary 組 Text 同步，只剩一個藍色文字；④ `text/tertiary` `#7C7C80`→`#8A8A8E`（對卡片 4.05）；⑤ Error Text／icon `#FF453A`→`#FF7A70`（對卡片 5.49、對錯誤底 5.05）、Border `#E0605A`，與 Success／Warning 調性一致。Error Main `#B3352F`、Info 組不變（Info Main 對卡片 1.84，屬自訂值，僅作填色；若用作按鈕需加外框）。
- **搖桿（Joystick）握柄色（使用者調整，2026-10-28 讀回）**：`Light／Dark · Joystick / 重新設計`（`268:21738`／`222:13253`）中央握柄 `Knob / 握柄` 與內圈 `grip` 改綁 Common Color collection 的灰階：Light 握柄 `common/gray/200`（`#EEEEF0`）、grip `common/gray/300`（`#D1D1D6`）；Dark 握柄 `common/gray/800`（`#48484A`）、grip `common/gray/700`（`#636366`）。外盤 `surface/card`、外框／內環 `line/border`、刻度 `icon/secondary`、方位字 `text/secondary` 仍為 Theme token。握柄不使用 CS 的 control／active 階，因為要與外盤 card 保持立體感；Common Color 為單一 mode，Light／Dark 各自綁不同灰階。這是 Figma 靜態設計，App `GoFlyJoystickPanel.swift` 尚未同步，亦未做裝置驗證。
- 04 頁 section 底色：Light A–F、`Light · 0 · 共用元件`（含按鈕）、`Light · Color Scheme` 為 `#202020`；Dark A–F、`Dark · 0 · 共用元件`（含按鈕）、`Dark · Color Scheme` 為 `#0E0E0E`；Light section 內標題與說明文字改淺色以維持可讀。Icon、Typography、Common Color、未定義 section 未動。
- 新增 A 區 R08「首次引導 / 需要重新設定（Setup 與 App 不相符）」Light `313:28214`／Dark `313:28242`：以 R07 版面為底，齒輪圖示（沿用 Icon 目錄 `icon/gear`，語意為「設定」）、標題「需要完成設定」、說明「此 GoFly App 與設定套件不相符。請將這支 iPhone 連接 GoFly Mac App，以修復設定。」、主要按鈕「重試」（位置同 R02／R03）。依 App 實機畫面；靜態 wireframe，未驗證行為。
- 新增 D23「檢視路線 sheet（全部地點）」Light／Dark，對應 App `GoFlyRouteListView`（可編輯節點卡＋新增停靠點／反轉順序）；取代文件中「可編輯路線清單沒有 wireframe」的缺口，D13 仍為 GPX 唯讀清單。D6.a 確認結束 dialog 已由使用者刪除。

## 05 · Mac Redesign 對照

Figma 與規格的畫面數一致：淺色、深色各 34 張；M1 環境設定 E01–E08 共 8 張、M2 首次安裝 I01–I09 共 9 張、M3 裝置管理 G01–G17 共 17 張。新版 Mac 視覺與流程規格已依此分節。舊 `02 · Mac App` 畫面不再作新版基準。

Mac M2 I09／D14 的「中斷後重新開始」行為已與安裝交易同步：建立新 `setupID` 並從頭 preflight/apply；renew 覆蓋同一 App、保留資料並重建 USB 配對。若舊交易可能已發布一次性 pairing envelope，僅移除身份與 digest 完全相符的未消耗 `incoming.plist`，保留活動 pairing store、receipt、App 及使用者資料。詳見 [`MAC-INSTALLER-SPEC.md`](MAC-INSTALLER-SPEC.md)、[`MAC-UI-DESIGN.md`](MAC-UI-DESIGN.md) 與 [`AI-INSTALL.md`](AI-INSTALL.md)。

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
   - `SearchField / focused`：藍色外框（Light: `#007AFF` 1.5pt、Dark: `#0A84FF` 1.5pt，caret 同步藍色），底色淺化（Light: `#F2F2F7` systemGray6、Dark 當時為 `#3A3A3C` systemGray4；2026-10-27 已改用 E Neutral/Icon + Text Focused variant）。
   - `SearchField / normal`：底色同步淺化（Light: `#F2F2F7`、Dark 當時為 `#3A3A3C`；2026-10-27 已改用 E Neutral/Icon + Text Default variant）。
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
     - Switch / on、Switch / off（舊有元件建立紀錄；後續已從目前 E2 控制稿移除並停止使用，不在 Dark 共用元件重建）
     - Slider / 原生黑白
     - Recenter、Follow、Progress
     - SimArrow / 模擬位置（實心）、RealArrow / 真實位置（實心藍）、SimArrow / 模擬位置（等待 50%）
     - CandidatePin / 候選 Pin（唯一共用 Pin 元件；DestPin 已刪除）
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
     - 選中模式（Active Tab）：圖示為純線框線條加深加粗（`strokeWeight: 2.29 pt`、Light: `#000000`、Dark: `#E5E5EA`，`strokeCap: ROUND`、`strokeJoin: ROUND`，`fills: []` 無填色），文字標籤加深（`PingFang TC Medium 10 pt`、Light: `#000000`、Dark: `#E5E5EA`），子圖層命名統一為 `Tab / <模式> / selected`。
     - 未選中模式（Inactive Tabs）：圖示為純線框細線（`strokeWeight: 1.88 pt`、Light: `#999999` `rgb(0.6,0.6,0.6)`、Dark: `#8E8E93` `rgb(0.56,0.56,0.58)`，`fills: []` 無填色），文字標籤次要色（`PingFang TC Medium 10 pt`、Light: `#999999`、Dark: `#8E8E93`），子圖層命名為 `Tab / <模式>`。
     - 全 TabBar 41 個實例已全面清除所有向量填色 overrides（清除 207 個遺留填色），確保全檔無任何藍色或灰色 filled color，完全對齊 `B1 · 地圖首頁 / sheet 收合`。
   - **元件板展示配置**：
     - Light 與 Dark 元件板寬度自動拓寬至 2269 pt（精確對齊下方 Section A 寬度 2269 pt），於右側 `x: 1800, y: 330` 配置完整的 TabBar ComponentSet 垂直展示，並附帶 `TAB BAR · 瞬移／路線／搖桿（等寬）` 專屬標題與說明文字。
     - 原元件座標 `x: 1186, y: 790` 保留單一實例預覽（`Mode=瞬移`），維持元件板版面無空白缺漏。
   - **UI 頁面實例模式全面連動（共 41 處）**：
     - Section B 地圖首頁／瞬移（8 處 Light + 8 處 Dark）：統一保持 `Mode=瞬移`（瞬移圖示與文字加深，其餘淡灰）。
     - Section D 路線規劃（8 處 Light + 8 處 Dark，含 D1、D15、D7、D4、D3、D8、D9、D2）：統一切換為 `Mode=路線`，路線圖示與文字加深，瞬移與搖桿維持灰色。
     - Section E 搖桿與漫步（4 處 Light + 4 處 Dark，含 E1、E3、E4、E5）：統一切換為 `Mode=搖桿`，搖桿圖示與文字加深，瞬移與路線維持灰色。
6. **Dark · E5 · 搖桿漫步中斷 / 恢復（Resume UI）panel UI 對齊 Light E5**：
   - 移除舊版 380 pt 巨大搖桿面板（`Panel / 漫步控制`）與冗餘 Switch 開關。
   - 新增深色主題版 `BottomSheet / 漫步控制（高度最窄）`（`393 × 106 pt`，置底 `y: 693`，在 TabBar 上方可視 76 pt）：
     - 底色：`#1C1C1E`，頂部圓角 20 pt，頂部陰影 `y: -4, radius: 12, opacity: 0.08`。
     - Grabber：`36 × 5 pt`，底色 `#48484A`，圓角 2.5 pt。
     - 標題與資訊：白字「漫步模式 · 暫停中」（PingFang TC Semibold 17 pt）與次要灰字「已移動 420m · 速度 9 km/h」（PingFang TC Regular 12 pt，`#98989E`）。
     - 主要按鈕：白色膠囊底色 `Button / primary / 恢復漫步`（`100 × 40 pt`，圓角 20 pt），黑字「恢復漫步」（PingFang TC Semibold 14 pt）。
   - 補齊深色底欄 `Dark · TabBar / 瞬移・路線・搖桿（等寬）`（實例 `Mode=搖桿`，`y: 769, h: 83`）。
   - 回定位按鈕 `MapControls` 配合收合面板位置下移至 `y: 633`（面板上方 16 pt 浮動）。
   - 頂部 `Dark · Toast / 系統訊息 / warn` 文案與高度對齊淺色版（標題「搖桿漫步已暫停」、副標「背景訊號中斷已安全暫停，可立即重試漫步。」，高度自動貼合為 85 pt）。
   - 同步更新旁註 `Dark · E5 說明`。
7. **全頁面 Text Field 全面轉換為 SearchField 共用元件（新增最愛路線與編輯最愛對齊）**：
   - 全頁面所有文字輸入欄位（Text Field）已全數替換為共用元件實例（`SearchField / normal` 與 `SearchField / focused`）：
     - `D20 · 新增最愛路線 sheet` 與 `Dark · D20 · 新增最愛路線 sheet`：將原獨立 frame `LabelField / focused` 替換為 `SearchField / normal`（Light）及 `Dark · SearchField / normal`（Dark）實例，寬度調整為 353 pt（適應 sheet 邊距），文案覆蓋為「通勤路線」。
     - `C2 · 編輯最愛 sheet` 與 `Dark · C2 · 編輯最愛 sheet`：將原獨立 frame `LabelField / focused` 替換為 `SearchField / normal`（Light）及 `Dark · SearchField / normal`（Dark）實例，寬度調整為 353 pt，文案覆蓋為「公司」。
   - 全頁面非共用元件之 Text Field frame 數量歸零（0 處遺留），全數使用共用元件。

### 2026-10-26 貼上圖示與搜尋列貼上控制（Figma 元件已建立）

- **Figma 04 頁 `0 · 共用元件（正式版 token）`（node `121:50484`）元件補齊**：
  - **獨立元件**：建立標準 `icon / paste`（18×18 pt，SF Symbol `doc.on.clipboard`，黑色 `#000000`）與 `icon / paste (20pt)`（20×20 pt，次要色 `#8A8A8E`）。
  - **Action Row 元件**：於 `ACTION ROW · 地點 sheet` 區域在 `Action / 複製` 右側新增 `Action / 貼上` 按鈕元件（40 pt capsule，含 `icon / paste` 與 15 pt Semibold「貼上」）；同步於 `Dark · 0 · 共用元件（正式版 token）` 補齊 `Dark · Action / 貼上`。
  - **設計確認卡片**：在 Section 0 底部新增 `ICONS · PASTE / 貼上（SF: doc.on.clipboard）` 標題及 `PasteIconOptions / 設計確認卡片`（包含方案 A 原生 SF Symbol 推薦標章預覽，以及方案 B UIPasteControl 動作整合說明）。
  - **搜尋控制實例更新（2026-10-26 截圖）**：`SearchBar / 浮動`（`222:13222`）整體 361 × 50 pt，由 301 × 50 pt 輸入卡與 50 × 50 pt 設定命中區組成，間距 10 pt；輸入卡右側有 44 × 44 pt 無底色貼上命中區。此時 Light 貼上 icon 為 `#6B6B6B`；Dark SearchBar 的白色 icon 樣式已由 2026-10-27 調整記錄取代。首頁採 20 pt SF Symbol `doc.on.clipboard`，保留明確對比，不使用較淡 disabled 感色階。
  - **全螢幕搜尋 B3 空輸入（2026-10-26）**：Light `B3 · 全螢幕搜尋 / 空輸入`（`121:51543`）與 Dark `Dark · B3 · 全螢幕搜尋 / 空輸入`（`121:54407`）均已補上右側 `doc.on.clipboard` 純 icon，20 pt 圖示置中於 44 × 44 pt 無底命中區；空輸入時隱藏清除 ✕。Placeholder 改用灰色：Light `#8A8A8E`、Dark `#98989F`。沒有修改共用 `SearchField / focused` master；B4、D5 等其他實例維持原狀。此為 wireframe 更新，沒有新增 prototype wiring。
- **規格與驗收對齊**：已同步 [`IOS-UI-DESIGN.md`](IOS-UI-DESIGN.md) 規範。首頁輸入卡 301 × 50 pt，貼上圖示在欄位內右側，設定卡獨立於欄位外；空 query 顯示 44 pt 命中範圍之 20 pt SF Symbol `doc.on.clipboard`，Light `#6B6B6B`／Dark `#E5E5EA`、無底色。輸入文字後貼上圖示隱藏並顯示清除 ✕。貼上來源為純文字時自動移除頭尾空白與換行。
- **貼上後確認與錯誤狀態（App 行為，Figma variant 缺口）**：首頁貼上會立即確認搜尋；有效位置顯示候選地點卡。無效經緯度、找不到位置或搜尋失敗時顯示約 2 秒的中英文 warning toast，沒有 action／關閉按鈕，也不建立 location card。現有 `Toast / 系統訊息 / warn` Figma 元件含 action 與關閉控制，未定義此無按鈕短暫 variant；此處依使用者確認實作，並記錄為待補設計 variant。全螢幕搜尋頁貼上仍只插入輸入欄，保持頁面開啟。

### 2026-10-27 Dark SearchBar／SearchField 貼上控制調整

- `Dark · SearchBar / 浮動`（`222:13238`）保留 361 × 50 pt 外框；`Input / 搜尋框` 直接使用 E `Text Field / Neutral / Icon + Text / Default` instance，尺寸 301 × 48 pt、y=1。SearchBar input 的新增項目只有右側 paste icon；輸入元件本身沿用 E variant，提供 14 pt 圓角、`color/surface/control/active` 底色、`color/line/input/default` 1 pt 邊框、18 pt 搜尋 icon 與 15 pt `Theme/subheadline`；搜尋文案維持「搜尋地點或輸入經緯度」，使用 `color/text/input/default`。
- SearchBar 的 44 × 44 pt `UIPasteControl / 貼上` 命中區使用 Icon 目錄 `0 · 共用元件（Icon）` 的 `icon/paste`（master `241:15464`）；Dark icon vectors 綁 `color/icon/input/default`（`#BEBEC2`），命中區無底色。這取代先前貼上 Vector 與同色輸入底造成圖示不可見的狀態。
- `Button / Icon` 的 Settings Enabled／Disabled variants（Dark `256:18403`／`256:18409`，Light `268:21919`／`268:21921`）為 48 × 48 pt、14 pt 圓角方形，22 pt gear 置中。Light／Dark SearchBar 保留 50 × 50 pt 外框，內嵌 48 × 48 pt Settings variant，垂直對齊 48 pt 高的 Default input；icon、fill 與 border 延用各自主題 tokens（2026-10-28 使用者更新）。
- `Dark · SearchField / focused`（`222:13239`）直接使用 E `Text Field / Neutral / Icon + Text / Focused` instance，提供 active surface、1.5 pt accent border、Theme/subheadline value／caret 與搜尋 icon，右側 Clear 使用共用 Button/Icon instance。`Dark · SearchField / normal`（`222:13240`）直接使用 E Default instance，搜尋 placeholder 使用 Theme/subheadline，右側為 44 × 44 pt 無底貼上命中區，內含同一 `icon/paste` instance，顏色同用 `color/icon/input/default`。
- 驗收：輸入欄尺寸、圓角、底色、邊框、字級與 E Default 一致；Dark SearchBar／SearchField 貼上 icon 均來自 Icon 共用元件且可見；Settings 為圓角方形；Dark 背景／文字／icon 不使用純白。已用 Figma 畫面截圖確認元件外觀與位置。這是 Figma 靜態 wireframe 更新，沒有新增 prototype wiring；App 程式與實機行為未在本次修改或驗證。

## 2026-10-24 Section E 重構逐票校準

- 票 01：淺色 E1.a 改為 E1 收合待機結構；E3 狀態pill統一「啟動」；E4 漫步選點卡片的 Pin 與卡片主按鈕統一純文字「確認」，不保留播放圖示。相應淺／深色畫面均以 Figma Console 渲染讀回。
- 票 03：E2 與 E2.a 淺／深色四個畫面沿用相同道路幾何：`M 0 141.5 L 0 13.5 L 75.5 5.5 L 122.5 0`；只保留各主題的路線描邊色。四張渲染已讀回比對。畫面核對不代表裝置道路服務或實機漫步已驗收。
- 票 05：E4 淺／深色 Pin 與地點卡主按鈕均為 DestPin／「確認」，E2 保留底部「更換地點」。最終截圖時發現 E4 Light 缺候選 Pin、Dark 誤用實心 CandidatePin；已在兩種外觀各新增／替換成空心 DestPin，與現有路線目的地分開呈現，修正後兩張截圖讀回一致。App 的確認與更換地點需成功重規劃才原子替換，手動接管放開後回到原目的地也需從最後 ACK 重規劃。2026-10-27 Icon 目錄統整後，DestPin master／卡片已刪除；E4 候選只用 CandidatePin，生效終點用 MapNode / 目的地。
- 票 05 補充：使用者確認漫步地圖 Pin 的地點卡出現時，panel 自動收至最小高度並保持；拖曳 grabber 拉高或點「搖桿」tab 可展開，關閉卡片不自動恢復高度。E4 Light/Dark 已讀回修正後畫面，兩者都呈現最小 panel；App 行為及兩種主題一致性由軟體驗收確認。
- 票 06：以 Figma Console 讀回 E1/E2/E2.a/E3/E5 淺深色共10畫面；速度 pill、設定 sheet（5/25/50/100、1–120 slider）及恢復列在兩種主題結構一致，沿用既有線框，沒有新增 Figma 狀態畫面。
- 票 07：以 Figma Console 讀回 E5 淺／深色恢復畫面；均為恢復列＋tabs，Dark 不再呈現大搖桿或 Switch。設計只表達靜態恢復態，不宣稱已驗證背景 runtime 或實機恢復。
- 票 01–03 對 App 的漫步道路規劃和 ACK 進度描述屬於行為／實作更新；設計圖不表示原型已接線。本次未新增 Figma prototype wiring。

## 2026-10-27 04 iOS theme 色彩與變數綁定

- 04 深色語意角色已對齊 05 的 Mac 深色值；變數仍由 iOS 自己管理，分別放在 `GoFly iOS / Light Theme` 與 `GoFly iOS / Dark Theme`，未共用 Mac 變數。地圖色票及 05 未定義的 danger 底色為 iOS 專屬。
- 逐 frame 綁定檢查發現先前單看變數綁定數量仍會漏掉畫面層級的語意誤染；對異常畫面另行截圖讀回。速度插圖重繪前曾盤點 04 Dark 區段 63 張完整 `393 × 852` frame、5,727 個圖層；當時 3,050 個實心填色、2,120 個描邊及 1,044 段文字填色均綁定 `GoFly iOS / Dark Theme`。本輪速度插圖重繪改變圖層數，舊數量不再視為目前統計；8 個 Dark 速度圖示已逐一讀回，均綁定 Dark `color/speed/*`。
- 已修正 B10／D8 錯誤 toast 與 D9／D22 成功 snackbar 把狀態色套到整張畫面的問題，現在狀態色只保留在 toast／snackbar 本身；D8 路線列與控制圖示恢復中性色。R04／R05／R06 步驟號、B3／B4 確認文字、狀態列、Tab Bar 與 F1／F1.a 未綁色文字亦已逐項對應 Dark token。Dark B1、B3／B4、D8／D9、R06、F1／F1.a 等修正畫面均已截圖讀回。
- Dark 地圖 palette 維持 iOS 專用值：canvas `#242426`、building `#313133`、park `#1E3322`、water `#1A2B3C`、road `#3A3A3E`、road-edge `#2C2C2E`、arterial-edge `#6E5C2C`、arterial `#5C4F2A`、label-area `#8E8E93`、label-water `#6FA3D6`。共用深色語意值仍與 05 對齊；Figma collection 保持 iOS 獨立。
- 此為靜態 Figma 設計更新，App 實作與裝置驗證狀態另行追蹤。B11（`239:15137`）目前只有 Light 畫面，Dark variant 尚缺，列為設計缺口。
- 後續驗收：Light／Dark 各自維持 iOS 變數來源；每張 Dark frame 的底色、邊線、文字及圖示需依語意 token 綁定，調整變數後引用畫面同步更新，並逐 frame 渲染讀回確認文字與元件對比。

### Dark · 0 · 共用元件（UI）

- Figma 04 `Dark · 0 · 共用元件`（section `256:16952`）收錄狀態 Banner／Snackbar／Pill、搜尋欄與控制項、Progress、搜尋結果／清單、搖桿及 Tab Bar；按鈕矩陣與色彩角色集中於相鄰的 `Dark · 0 · 共用元件（按鈕）`。狀態動作只在使用情境中呈現，不重複按鈕 variants。Icon 目錄仍由獨立工作整理；本輪僅將 Search、history、nav、pin、gear、x、more 既有圖形資產轉成可重用 component，供搜尋欄、搜尋結果列與 `Button / Icon` 使用。
- 兩區頂端與內容板起點對齊、分類與展示格線保留；Dark 規則一致：避免大面積純白、元件背景與底面不可為 `#FFFFFF`、文字與 icon 不得為 `#FFFFFF`。主要文字／icon 及按鈕前景為 `#E5E5EA`，Primary surface 為 `#0066CC`；控制、卡片與狀態表面使用各自 Dark tokens。
- Figma 主文字／主 icon、Primary／Danger 前景與色票變數已更新；兩區的實心填色與描邊讀回沒有純白值，截圖確認版面分組與層次。這是 Figma 靜態設計更新；App 實作和裝置驗證仍未完成。
- 2026-10-27 `LIST · SEARCH RESULTS` 更新 `Dark · List rows`（`222:13255`）：內容改為 04 Dark B3 最近搜尋 history 列、B4 座標 navigation 列與地點 location-pin 結果列（52／64／64 pt），移除舊收藏／勾選列；右側 More 改用 `Button / Icon` More variant，其內 icon 使用共用 `icon/more`。左側改用共用 `icon/history`、`icon/nav`、`icon/pin` instances，均綁 Dark icon tokens。四張 B3／B4 Light／Dark wireframe 的清單列也已綁定同一套 Figma `Theme/<token>` 文字樣式；全檔現在有 14 個 core `Theme` styles 對應 `GoFlyFont`，另有兩個 Theme/button 尺寸樣式，皆不依外觀模式分支。各文字圖層仍分別綁定 Light／Dark theme 文字色變數。Dark 按鈕、文字欄位、Tab Bar 及羅盤方向標籤也已綁 Theme styles。讀回 Dark 共用元件與 Light／Dark B3／B4 截圖確認 icon 與字級層次；這是 Figma 靜態設計更新，App 字型程式未修改、未做裝置驗證。
- 2026-10-27 狀態元件與輸入／進度元件同步使用 Dark tokens 及共用 Theme 文字樣式：Toast 標題／action 為 `Theme/subheadlineEmphasis`，說明／dismiss 為 `Theme/footnote`；Snackbar 訊息為 `Theme/subheadline`、action 為 `Theme/subheadlineEmphasis`；StatusPill 為 `Theme/footnoteEmphasis`，標籤與語意色已對齊。搜尋元件標題改為 `Dark · SearchBar`，SearchBar、focused／normal SearchField 文案為 `Theme/body`；設定／清除鈕引用 `Button / Icon` 元件，三個搜尋 glyph 的舊白底 wrapper 已清除。Progress track 使用 `color/surface/card`，value 依使用者更新綁定 `color/surface/control`。讀回各元件及整區截圖；兩個 Dark 共用 section 的可見 fills／strokes 均無純白 `#FFFFFF`。未改 App 實作或裝置狀態。
- Switch 已從 E2 漫步控制稿移除，現行 E2 說明與畫面配置為停止／更換地點兩個操作；Light／Dark 說明圖層名稱已清除過時的 Switch 文案。Dark 共用元件沒有 Switch variant，本輪未新增或恢復 Switch。

### Dark · 0 · 共用元件（按鈕）

- 2026-10-27 新增於 04 `Dark · 0 · 共用元件（按鈕）`（section `249:16291`），集中整理按鈕類型、色彩角色與靜態狀態。舊 `A · ACTION BUTTONS / Type × State`（`Button / Action`）已移除：其 6 個 variants 沒有任何 instance 引用；`Destructive · text` 色彩角色卡保留，但新的按鈕矩陣尚未定義 Destructive variant。Dark `Button / Icon` component set 現含 Standard／Route／Ghost Standard／Ghost Route／Clear／More 六種各有 Enabled／Disabled 的 Type，加上 MapControls 只有 Enabled，合計 13 個 variants；Settings 是 set 外獨立 48 × 48 pt 元件，使用 gear，Clear 使用 x、More 使用 more 共用 icon instances。Filled Standard／Route 使用共用 Active `#4C4C4F`、Disabled `#242426` surface；Ghost Standard／Route／Clear／More 維持無填色／描邊，Enabled／Disabled icon 依 Dark icon tokens 呈現。`Button / Check` 含 Selected／Unselected；`Button / Status action` 含 Error／Retry、Warning／Continue、Success／Undo。
- 新增 `Button / Icon + Text` 與 `Button / Text` component sets，Type 為 Primary／Neutral／Danger／Ghost Primary／Ghost Secondary、State 為 Active／Disabled，Size 為 Large／Medium／Small／Extra Small；每組 40 個組合。尺寸為 `280 × 56`、`224 × 48`、`176 × 40`、`144 × 32 pt`。C · `Button / Icon + Text` 的 Neutral Active／Disabled surface 綁定共享 control tokens `#4C4C4F`／`#242426`，Disabled label／icon 使用 `#636366`。Danger Active 使用 Dark 專屬 `color/action/danger/surface` `#E14C46` 搭配 `#E5E5EA` 文字／圖示；Danger 文字、圖示、邊線與 Toast 狀態色仍使用各自語意 token。C/D Ghost action buttons 仍無填色、無描邊；Active Ghost Primary 使用 accent 藍；Active Ghost Secondary 使用 `color/text/primary`／`color/icon/primary`（`#E5E5EA`）；其 Disabled 前景仍使用 `color/text/button/disabled`／`color/icon/button/disabled`（`#636366`）。C 所有類型的 Disabled 文字／圖示值已一致。
- `Text Field / Neutral` 包含 Text／Icon + Text 及 Default／Focused／Disabled（6 個組合）。Default／Focused surface 與 C Neutral、B Filled Enabled 同用 `color/surface/control/active` `#4C4C4F`；Disabled surface 與 B Filled／C Neutral Disabled 同用 `color/surface/control/disabled` `#242426`。Default placeholder／icon `#BEBEC2`，Disabled text／icon `#636366`；Focused 保留 accent 藍描邊與 caret。Default／Disabled border 為 `#636366`／`#38383A`。展示區背景為 `#101012`，元件面板為 `#1C1C1E`。
- 板內另列 Primary、Secondary、Disabled、Danger、Destructive、Icon enabled／disabled 色彩角色，及 Danger、Warning、Success、Info 狀態色參考。Primary 的專用 token 為 `color/action/primary/filled-surface`／`filled-text`：Light 使用藍底白字 `#007AFF`／`#FFFFFF`，Dark 使用藍底與非純白前景 `#0066CC`／`#E5E5EA`；Dark `primary/surface`／`primary/text` 語意 token 亦同步為 `#0066CC`／`#E5E5EA`，以對齊共用 UI 與按鈕前景。Danger 填色由 `color/action/danger/surface` 控制，值為 `#E14C46` 並搭配 `#E5E5EA` 前景；Danger 文字／圖示、Toast 狀態色維持各自語意 token。B/C 共用元件控制狀態表面為 `#4C4C4F`／`#242426`；一般、control、button 三組 disabled 文字／圖示 tokens 現在皆為 `#636366`；Destructive 紅字僅列為色彩角色，未定義按鈕 variant；勾選態使用深色表面與藍色勾記，未勾選態使用深色表面與次要描邊；兩態均無純白底。Error／Warning／Success 動作依所屬狀態語意上色，Info 目前只有色彩參考。
- 此區移除舊 A 按鈕元件組、新增 icon Ghost 並同步 B/C/E 狀態與展示背景後的 418 個實心填色／描邊皆綁定 `GoFly iOS / Dark Theme`，無裸色值或跨 collection 綁定，不引用 Mac 05 變數。2026-10-27 後續更新已將 B Disabled icon 與 C/E Disabled text／icon 統一為 `#636366`；截圖確認 Filled/Ghost 狀態與背景層次，Ghost 維持無底無框，Danger 仍由 Dark action token 控色，沒有超出 section 邊界；未新增 prototype wiring。此為 Figma 靜態設計更新，App 尚未據此實作，未做裝置驗證。
- 驗收：Primary／Danger 使用各自 Light／Dark tokens；B Filled、C Neutral、E Default／Focused 共用 `color/surface/control/active` `#4C4C4F`，Disabled 共用 `color/surface/control/disabled` `#242426`；B Ghost 無填色／描邊，Enabled icon `#E5E5EA`、Disabled icon `color/icon/control/disabled` `#636366`；C 各 Disabled 類型及 E Disabled text／icon 均為 `#636366`，邊框與 caret 綁定 Dark tokens；展示區背景／面板分別為 `#101012`／`#1C1C1E`。`Destructive · text` 目前僅是色彩角色，未列入按鈕 variant；只將已列組合視為已設計。



### 2026-10-27 04 iOS Icon 目錄

- 速度圖示色塊規格（2026-10-28 重繪，取代先前 walk 姿勢與 bicycle 線架規格）：`speed/walk`、`speed/bicycle`、`speed/scooter`、`speed/car` 四個 36 pt master 全部由封閉填色 shape（色塊）組成，可見圖層無 stroke、元件底色透明。walk 為前傾行走人物：navy 圓角膠囊四肢（後腿彎膝）、coral 實心上衣、skin 頭與手、navy 髮型、gold 圓角鞋；bicycle 以 coral 實心圓角管件組成車架、navy 座墊／把手／前叉、gold 齒盤；scooter 為 coral 實心車身與前擋泥板、navy 座墊與把手、gold 頭燈；car 為 coral 實心車身與車艙、sky 車窗、gold 頭燈、coral-shadow 尾燈。三款車輪統一為 navy 實心輪胎、highlight 輪框與 gold 輪轂。填色綁定 `color/speed/*`。D7／E3 淺深色 16 個「Speed icon」直接使用這四個 master 的 instance（22 × 22 pt，原位置），Dark 實例覆寫為 Dark `color/speed/*`；`00` 頁的 `WF/Icon/speed-*` 24 pt source 已不再被 D7／E3 引用。驗收：Icon 目錄 36 pt 與 D7／E3 Light／Dark 截圖中四款圖示造型一致、無描線、在 22 pt 仍可辨識；Figma 截圖已讀回，此靜態設計未更新或驗證 App `SpeedPreset*` 資產與實機顯示。

- 將 `0 · 共用元件（Icon）` 從 00 移至 `04 · iOS Redesign`（section `256:17781`，board `256:17784`）。[開啟 04 Icon 目錄](https://www.figma.com/design/RtPV8PXCQJ2WXK3jk3kPrq/GoFly-%C2%B7-UI-%E7%B7%9A%E6%A1%86%E8%A8%8E%E8%AB%96?node-id=256-17781)。00 不再保留此區段。
- 目錄只收錄 04 頁中出現的 SVG／向量圖示（含 `icon/check`）；依使用者定義，Figma 向量圖歸入 SVG 類。SimArrow 實心與等待 50% 各列 Light／Dark，其他 Light／Dark 重複圖示只保留一筆。05 Mac 專用圖示與 glyph 不納入；卡片數量與位置以 Figma 當前內容為準。已移除重複的 System Font Close、Grip 卡及未使用的 `icon/repeat.muted`。
- 目錄整理：非速度預覽統一使用 24 × 24 pt 置中區；功能圖示以 `icon/copy` 為基準，24 pt 線寬 1.9 pt、圓端／圓角，播放／暫停／停止為一致的實心控制圖示。`icon/speed` 儀表維持原樣；`speed/walk`、`speed/bicycle`、`speed/scooter`、`speed/car` 為 36 pt 彩色色塊插圖，四款均以實心填色 shape 構成、不使用描線（含單車車架與車輪）。D7／E3 淺深色實例直接引用這四個 master。地圖箭頭、候選 Pin 與路線節點以原始比例及狀態色置於 24 pt 預覽區，保留各自用途；既有畫面圖示保留各自尺寸與位置；速度預設引用更新後的共用插圖及對應主題色。6 個基礎 `WF/Icon` 各有可搜尋的 24 pt 共用元件，內嵌局部外觀覆寫，原始 master 保留。整理期間 `slider.horizontal.3` 卡片在 Figma 目錄中被移除，其基礎 master `9:207` 仍存在。
- 命名統一採簡短英文：`icon/expand`（原 `icon/arrow.up.left.and.arrow.down.right`）、`icon/reset`（原 `icon/arrow.counterclockwise`）、`icon/direction-forward`／`icon/direction-reverse`，以及 `speed/walk` 等；地圖等待狀態使用 `map/sim-light-wait`／`map/sim-dark-wait`。原元件 ID 保留，舊名稱記在描述中供搜尋。
- 四個速度插圖共用 navy、coral、coral-shadow、gold、skin、highlight、sky 七種 `color/speed/*` 色彩，Light／Dark 各自綁定對應主題 collection；16 個 D7／E3 淺深色預設圖示為 `speed/*` master 的 instance，保留 22 pt 與原位置。此為 Figma 設計更新，App `SpeedPreset*` 資產及裝置狀態未在本次更新或驗證。
- 單色功能 icon 使用黑色 `#000000`，保留圖形內部留白／負空間；alert、success、速度插圖及定位 symbol 保留語意色。`icon/success` 勾色與 success 圓環一致（Light `#34C759`、Dark `#30D158`；黑底勾選框內的勾為白色）。Check／選取改為共用向量 `icon/check`，勾形與 `icon/success` 內勾一致，`icon/select` 勾線也同形並使用圓端／圓角。Close 僅留 `icon/close`，Grip 僅留圓端線條的 `icon/grip`。`icon/paste` 為透明底圓角描邊 clipboard：主體輪廓置中，夾扣封閉且圓角；24 pt 線寬 1.9 pt、主體圓角 2 pt，比照 `icon/copy`。24／20 pt 母元件、內層框架及所有 18／20 pt 使用實例採雙向 SCALE constraints，外層容器放大時圖示等比例縮放且無重複圖層；`icon/location` 已刪除並改用無填色、1.9 pt 黑色描邊的空心 `icon/nav`，`mappin.and.ellipse` 已刪除並以 `icon/pin` 為通用 Pin。`icon/direction-forward` 左箭頭透明度 40%，`icon/direction-reverse` 右箭頭透明度 40%；`icon/swap-horizontal` 補上雙向 `arrow.left.arrow.right`。SimArrow 為 22×22 pt，其外形／向量與 24 pt `icon/nav` 按比例一致；Light 黑填白描邊、Dark `#E5E5EA` 填黑描邊，不用綠色或紅色；等待態同色並以 50% opacity 表示。RealArrow 同步使用相同 22×22 frame 與 SimArrow 箭頭輪廓／向量尺寸，保留 `#007AFF` 實心藍、`#E5E5EA` 描邊及微陰影。`icon/reset` 的箭頭頭部為水平／垂直圓端線，旋轉 0° 並與圓弧相接，左側保留可見間距。F1.a Light／Dark「重置」按鈕均引用此 component，Dark 實例描邊綁定 Dark `color/icon/primary`。
- `0 · 共用元件（Icon）` 的 SVG／向量卡均以 component master 或 component instance 提供可重用圖示；`icon/paste` 預覽保留巢狀 component instance，主體輪廓與封閉夾扣完整並可隨容器等比例縮放。`icon/check` 置於 `SVG · VECTOR ICONS`，可直接搜尋；功能圖示沿用 Light／Dark 主題 tokens。
- MapNode 起點／停靠點／目的地均為 24 pt frame、18 pt 白底空心環；描邊分別為 3／2.5／4 pt，停靠點保留 11 pt 編號，目的地無黑色中心點。Pin 唯一保留 CandidatePin，Pin 頭空心、黑描邊並保留短桿；DestPin master／卡片已刪除。Figma 形狀規則已回寫 `IOS-UI-DESIGN.md`。
- 驗收：04 只有一個 `0 · 共用元件（Icon）`，00 沒有該目錄；目錄僅含 04 圖示，當前 SVG/vector 卡片含 `icon/check`；每個圖示皆可透過 component master 或 instance 重用，`icon/check` 勾形比照 `icon/success`；單色功能 icon 為黑色，語意／速度插圖保留指定色彩；非速度預覽均為 24 × 24 pt 置中區，功能 icon 使用 1.9 pt 圓角描邊，速度儀表保留原樣，四款速度插圖為無描線的實心色塊插圖，D7／E3 淺深色實例為其 instance 且造型一致；paste 主體與封閉夾扣清楚相接、內部留白可辨，線條與圓角比照 copy；母元件、內層框架及所有使用實例皆為雙向 SCALE constraints；容器 44→88 pt 時，20 pt 圖示 20→40 pt 並保持置中；`icon/location`、`mappin.and.ellipse`、DestPin 已刪除，定位與 Pin 分別用空心描線的 `icon/nav`、`icon/pin`，Pin 元件僅留 CandidatePin。MapNode 三種尺寸均 24 pt，目的地使用 4 pt 空心環且無黑點；SimArrow 為 22 pt，外形與 24 pt `icon/nav` 等比例一致、Light／Dark 黑白描邊配色且不使用綠／紅、等待態 50%；RealArrow 為 22 pt，箭頭外形同 SimArrow 並與 `icon/nav` 等比例一致，保留藍色填色、淺灰描邊與微陰影；`icon/reset` 保留間距；F1.a 淺／深色 Reset 仍引用共用 component 並使用相符 icon token；`icon/pin` 可搜尋且 B4 Search Sheet options 保留 pin；卡片版面讀回正確。此為靜態 Figma 設計更新，未變更 App 實作或完成裝置驗證。
- 2026-10-27 RealArrow 同步：原先因 Figma Console `Transport closed` 未完成；本輪連線恢復後，Light／Dark master 與 B8 畫面實例均已改為 22 × 22 pt、與 SimArrow 同形的箭頭，使用 `#007AFF` 填色、`#E5E5EA` 描邊及微陰影。B8 的箭頭中心位置保留，兩種外觀均已截圖讀回；這不代表 App 實作或裝置驗證完成。

- 另記既有 Figma 色彩差異：Light `SearchField / normal` 與 B3 的 20 pt paste instance 白色描邊在白底不可見；Dark B3 的 20 pt paste 描邊 `#2C2C2E` 在輸入欄上對比偏低。貼上控制的色彩覆寫尚未調整；系統 `UIPasteControl` 的 App 外觀與實機狀態未由此推定。D7／E3 既有的 25 km/h 選中預設在 Light 文字／背景不可見、Dark 數字對比偏低，與此次速度插圖重繪分開記錄。


- 2026-10-27 初版視覺一致性（已由後續實心色調整取代）：`speed/walk`、`speed/scooter`、`speed/car` 主體曾改為無填色 coral 描線；人物肢體線寬亦曾對齊 `speed/bicycle`。16 個 D7／E3 Light／Dark 速度實例仍為 22 × 22 pt，8 個 Dark 實例新描線綁定 Dark `color/speed/*`。`icon/nav` 移除填色並保留 1.9 pt 黑色描線。`icon/paste` 的 24／20 pt masters、內層框架與 48 個使用實例均設雙向 SCALE constraints；截圖讀回 D7 Light／Dark 與 Icon 目錄，並以 44 × 44 pt 容器放大至 88 × 88 pt 驗證 20 pt paste 同步放大至 40 × 40 pt、維持置中。此為 Figma 靜態更新，未修改 App SVG 資產或進行裝置驗證。


- 2026-10-27 實心色第一版（已由無外描邊版本取代）：`speed/walk`、`speed/scooter`、`speed/car` 主體曾以實心 `color/speed/coral` 填色，外緣採 `color/speed/coral-shadow` 細描邊；人物肢體線條、單車線架及車輪配色維持原樣。


- 2026-10-27 實心無描邊更新：`speed/walk`、`speed/scooter`、`speed/car` 的 36 pt master、24 pt source 與 D7／E3 淺深色 12 個畫面實例，主體使用實心 coral fill，移除主體 stroke；人物肢體、單車線架、車輪及其他細節維持原樣。Light／Dark fill 綁定各自 `color/speed/coral`。Icon 目錄及 D7 Light／Dark 截圖讀回正常；App SVG 資產與實機狀態未在本次更新或驗證。

- 2026-10-28 `speed/walk` shape 重繪（已由同日四款色塊重繪取代）：以 `Illustration / scooter` 的圓潤厚實幾何作參考，36 pt master、24 pt source 的手臂與腿改為 navy 圓角膠囊 shape，鞋為 gold 圓角實心 shape，頭部以 navy／skin 填色形狀構成；移除這些可見圖層的 stroke。Light／Dark D7／E3 四個 22 pt 實例讀回同步。36／24 pt 與四個畫面實例均已截圖驗證。此為 Figma 靜態設計更新，App 資產與裝置狀態未更新或驗證。

### 2026-10-28 04 Light／Dark 色彩分類與 Surface Overlay

- 04 色彩區分為 `Common Color`（section `283:23726`）、`Light · Color Scheme`（section `276:22514`）與 `Dark · Color Scheme`（section `278:22578`）。Common Color 展示 primitive；Light／Dark 分別展示主題色。每組使用一條橫向連續色帶，角色名稱與 HEX 標在對應色塊下方，組間留白；Surface 按明度由淺至深，同色角色合併標示。
- 新增 Primary 100／300／500／700／900 色階參考；500 沿用現有 Primary：Light `#007AFF`、Dark `#0066CC`。新增色階樣本不綁既有 UI 元件，現有元件色值與 token 綁定維持不變。Button／Status 角色卡按 Light／Dark 重排，Status 顏色及既有描邊保留。
- 新增 `color/surface/overlay/*` 共 10 個 Light／Dark 參考變數，alpha 讀回約 0.949（95%）；既有 `color/surface/card` 等 token 仍為不透明。Color Scheme 的 Surface／Map Overlay 色帶以標註 HEX 的靜態色票展示這些 token 值，不重新綁定既有元件。
- Light `Button / Icon + Text`、`Button / Text`（component sets `268:22020`、`268:22197`）及 Dark 對應組（`249:16511`、`249:16544`）的 Neutral Disabled variants，各有 Large／Medium／Small／Extra Small 四種尺寸，16 個 variants 的 stroke 均讀回為空。其餘 Active 邊框與色彩不變。
- Light／Dark 色票區與兩個按鈕區均已截圖核對，角色標籤對應色票、色階與 Surface 排列清楚。這是 04 靜態 wireframe／token 分類更新；沒有更新 App、prototype wiring 或裝置驗證。

### 2026-10-27 04 iOS Typography Theme text style 目錄

- 新增 `0 · 共用元件（Typography）`（section `260:20013`），位於 04，與 `0 · 共用元件（Icon）` 同列，採兩欄展示文字樣例與樣式 metadata。16 個樣式包含 14 個 core `Theme/<token>` 與 2 個 `Theme/button/*`；每個樣例圖層均套用對應本機 Figma text style。原 `0 · 共用元件（正式版 token）` 的 6 個 TYPE 概覽示例同步綁定 `Theme/display`、`Theme/title`、`Theme/headline`、`Theme/body`、`Theme/footnote`、`Theme/caption`，並以實際樣式名取代舊字級標籤。
- Figma Theme styles 共用於 Light／Dark，只定義 PingFang TC 字型、字級與字重；文字顏色另依畫面綁定 `GoFly iOS / Light Theme` 或 `GoFly iOS / Dark Theme` 文字變數。此目錄只整理靜態樣式，未變更 App `GoFlyFont` 或裝置狀態，未加入 prototype wiring。
- 驗收：目錄唯一存在於 04；14 個 core styles 與 2 個 button styles 各列一次，讀回的 text style ID、字級與字重正確；兩欄無重疊，文字顏色規則清楚，Figma 截圖呈現完整字級層次。App 實作與裝置驗證分開追蹤。

### 2026-10-27 Dark／Light wireframe 對齊與 icon/pin 排序

- 04 Dark 配對 UI 依 Light 的結構與元件位置同步，仍使用獨立 `GoFly iOS / Dark Theme` variables，不引用 Mac 05 collection。完成：R02／R06、B1／B10、D6／D8／D10／D10.a／D15、E4；D10 系列保留 Dark 中性色面板及藍色「繼續」主動作。B11 Dark variant 仍是設計缺口，未由 Light 推定補畫。
- Dark SearchBar 現為 301 × 48 pt、y=1，直接使用 E `Text Field / Neutral / Icon + Text / Default` instance，surface 為 `color/surface/control/active` `#4C4C4F`；B10 Toast 高度 85 pt 並依 Light 內容換行。D8／D15 sheet、D6／D10／D10.a controls 與 B1 collapsed sheet 結構已依 Light 更新，文字、背景及狀態色重綁 Dark theme tokens。Figma Console 截圖讀回 B1／B10、D6／D8／D10／D10.a／D15、E4、R02／R06。
- 將既有 `icon/pin` 卡保留於 `04 · iOS Redesign` 的 `0 · 共用元件（Icon）`；保留 icon master 與 Dark B4 Search Sheet options 的 pin instances，未刪除任何畫面中的 pin。卡片相對位置依目前 Figma 畫布呈現。
- 驗收：Light／Dark 成對 frame 結構、尺寸與位置一致，Dark theme token 維持可讀；SearchBar 依 E Neutral Default 使用 Dark active control surface；Icon 目錄保留 pin 卡，B4 Search Sheet pin 選項仍存在且可讀。此為 Figma 靜態設計更新，未表示 App 已實作或完成裝置驗證。

### 2026-10-27 04 Light 共用元件與舊正式版 token 區移除

- 新增 `Light · 0 · 共用元件`（`268:21633`）及 `Light · 0 · 共用元件（按鈕）`（`268:21877`），分別對應 Dark UI／按鈕板；保留元件家族與版面，所有 Light 色彩綁定 `GoFly iOS / Light Theme`。Light Primary Active 的 Icon + Text 與 Text 四種尺寸全部為 `#007AFF`／`#FFFFFF`；Neutral Active `#D1D1D6`／`#C6C6C8`；Disabled `#F9F9F9`／`#9999A0`；五態 StatusPill 均為白底；Danger 使用 Light status/action tokens。輸入欄 Default／Focused 為白底，Disabled 為 `#EEEEF0`。
- 刪除舊 `0 · 共用元件（正式版 token）`（`121:50484`）。為保留既有畫面連結，28 個仍被 04／05 畫面使用的原母元件移至 04 Light 主板下方的 `iOS Light · 畫面引用中的原始元件`（`268:22388`）；249 個既有 instance 讀回仍指向原 master，未失聯。未被引用的 Switch on/off、Slider 與 List rows 一併移除。
- Figma Console 已截圖讀回兩個 Light 元件板與原始引用元件收納框，並核對 Light／Dark 色彩變數及 instance master；本次更新是 04 靜態元件板整理，沒有修改 App 或新增 prototype wiring。
- 驗收：04 有成對 Light／Dark UI 與按鈕板；舊 token 區不存在；Light／Dark 不跨 collection；既有畫面 instance 維持原 master ID。App 實作與裝置驗證未由 Figma 設計推定。

### 2026-10-27–28 Light／Dark 按鈕、Snackbar 與 SearchBar 樣式調整

- Light `Button / Icon + Text` 與 `Button / Text` 的 Primary Active 四種尺寸全部使用共用 `color/action/primary/filled-surface`（`#007AFF`）；前景維持白色。Neutral Active／Disabled 分別使用 action secondary／disabled surface `#D1D1D6`／`#F9F9F9`，保留 `#C6C6C8` 邊與 `#9999A0` disabled 前景。五個 Light StatusPill 均改用白底。
- Light `D · STATUS ACTIONS / Error × Warning × Success` 三個按鈕均改白底並保留各自 status 邊線。Light 可復原 Snackbar 與自動消失款使用相同 `#C7C7CC` 灰邊及兩層陰影；Dark 可復原 Snackbar 與自動消失款使用相同 `#48484A` 1 pt 灰邊及相同兩層陰影（9% y5 blur24、6% y1 blur3）。
- Light／Dark SearchBar 的 Settings button 均與同列 Input 搜尋框對齊填色、邊線顏色及 1 pt 邊線：Light 白底／`#C7C7CC`，Dark `#4C4C4F` 底／`#636366`；Enabled／Disabled variants 均為 48 × 48 pt、22 pt gear 置中、14 pt 圓角，垂直對齊 48 pt 高的 Default input。Figma 截圖已讀回兩個元件板及 Light／Dark SearchBar component。
- 驗收：Light Primary Active 的 Icon + Text／Text 兩組 component set 中，Large／Medium／Small／Extra Small 全部為藍底白字；Neutral Active／Disabled 分別為 `#D1D1D6`／`#F9F9F9`；五態 Light StatusPill 為白底；Status Action 三鈕白底；Light／Dark 可復原 Snackbar 分別與各自主題自動消失款的底色、灰邊及陰影一致；Light／Dark SearchBar Settings Enabled／Disabled variants 均為 48 × 48 pt、gear 置中並與各自 Default input 垂直對齊，顏色與 1 pt 邊線符合主題。Figma 截圖及元件讀回已核對。此為 Figma 靜態 wireframe 更新，未修改 App 或新增 prototype wiring，亦未完成裝置驗證。

### 2026-10-28 Color Scheme 對應附件 JSON 結構

- 使用附件原有 `colors.primitive`、`colors.themes.light`、`colors.themes.dark` 欄位整理目前的 04 Figma 色票，輸出至 [`IOS-COLOR-SCHEME.json`](IOS-COLOR-SCHEME.json)。Primary／Secondary／Error／Warning／Success／Info、surface、文字、邊線與 disabled 值都回讀自 Light／Dark 共用元件及按鈕元件；primitive gray 從元件已用的中性色取樣。沒有 hover variant 的欄位以目前對應角色值補齊；primitive gray 與補值不會重綁元件。
- `primary.scale` 保留 100／300／500／700／900；`surface.mapOverlay` 保留現有 95% opacity 的五種 map surface。JSON 的 `overlay.backdrop`／`scrim` 保留附件原值，因 04 現有元件沒有對應 token。
- Figma `Common Color`（section `283:23726`、board `283:24605`）、`Light · Color Scheme`（section `276:22514`、board `276:22515`）及 `Dark · Color Scheme`（section `278:22578`、board `278:22579`）現以色票呈現：Common Color 為 primitive 與 gray 50–950；Light／Dark 各有 Primary 色階、按鈕角色、Success／Warning／Error／Info、Background、Text、Surface、Map Overlay、Border、Action、Overlay。依參考排版，各組為獨立橫向色帶，角色名與 HEX 列在色塊下方；Figma 不顯示 JSON 文字。
- Figma 讀回確認三區所有 JSON 色值都有對應色票標籤與 HEX，無遺漏值；JSON 可解析且沒有空欄位。Neutral Disabled 無邊框的 16 個按鈕 variants 仍保持原狀。沒有改動共用元件、按鈕 variants 或既有 Figma variables；未更新 App，未做裝置驗證。

### 2026-10-28 Color Scheme 色值來源校正

- 色值來源確認為 04 頁 Light／Dark `0 · 共用元件` 與 `0 · 共用元件（按鈕）`，目的地是對應 Light／Dark Color Scheme 色票及附件 JSON；Color Scheme 不回寫或重設來源元件。
- 從現行 theme token 讀值後，修正 Primary button text、Success text／border、Light Warning／Error text 與 Light／Dark Info surface。代表值：Primary button text Light `#FFFFFF`、Dark `#E5E5EA`；Success border Light `#34C759`、Dark `#30D158`；Info surface Light `#E5F2FF`、Dark `#182B40`。Color Scheme 色塊與 HEX 標籤一致，95% Map Overlay alpha 保留。
- Figma 節點回讀及 Light／Dark Color Scheme 截圖已核對；共用元件、按鈕 variants 與 theme variables 沒有變動。這是靜態色票／規格更新，沒有修改 App 或完成裝置驗證。

### 2026-10-28 Light Standard Icon Buttons

- 04 `Light · 0 · 共用元件（按鈕）`（section `268:21877`）B 區已改為 `Type × State × Size`；Light `Button / Icon` component set `268:21882` 目前有 20 個 variants。Standard 有 Large 44 × 44 pt、Medium 40 × 40 pt、Small 36 × 36 pt、Extra Small 32 × 32 pt，各含 Enabled／Disabled；Route、Ghost Standard、Ghost Route、Clear、More 各有 Large Enabled／Disabled；Copy 與 MapControls 各有 Large Enabled。SearchBar Settings 維持 set 外獨立 48 × 48 pt。
- Standard Enabled 使用 `color/surface/card` 白底與 0.5 pt `color/line/separator` 邊；Disabled 使用 `color/surface/disabled`／`color/icon/disabled` 且無邊。四種 glyph 尺寸為 22／20／18／16 pt，圖示由 Icon 目錄 `icon/star`（component `256:19000`）提供並可改用其他共用 icon component。Light Standard 畫面 instance 保持 master 連結；Dark、Route、Ghost、Clear、More 與獨立 Favorite 56 × 56 控制不在本次視覺更新範圍。
- 截圖讀回 Button Theme board、Light 按鈕區及 D15（`123:57737`）；核對尺寸層級、白底／邊線、停用狀態、文字間距及版面無重疊。此為靜態 Figma 設計更新，App 程式未修改、未新增 prototype，尚未裝置驗證。App 實作小於 44 pt 的視覺按鈕時，需保留至少 44 × 44 pt 觸控命中範圍。

### 2026-10-28 移除重複的 Location Card Actions / Map Pin 展示（後續已重新建立為共用元件）

- Light 按鈕板刪除 F 區標題、9 個 Location／Map Pin 按鈕展示主件及標籤。共用 icon-only 按鈕看 B `ICON BUTTONS / Type × State × Size`；icon + text 按鈕看 C `BUTTON / ICON + TEXT · Type × State × Size`，不再在按鈕板重複列示 Location／Map Pin 專用展示。
- B、C 及其他按鈕板區域保留。B5、D4 等既有地點卡與地圖 Pin 畫面實例仍在原處，渲染外觀保持；本次只清除元件板展示，沒有把畫面實例替換為 B／C variants，也不聲稱其尺寸一對一符合 B／C 尺寸表。
- 驗收：Light 按鈕板 F 區完全移除，B／C 與其他區域不變；既有地點卡／Pin 畫面示例仍可見、尺寸及外觀不變。此為 Figma 靜態整理；未修改 App、未新增 prototype，未完成裝置驗證。

### 2026-10-28 C／D 按鈕內容置中

- Light／Dark `Button / Icon + Text`（C）與 `Button / Text`（D）各自的主矩陣 40 個 variants 改為水平 Auto Layout，主軸與交叉軸皆 Center，按鈕寬高固定以保留原尺寸。Light C 另含 Primary Inline Active／Disabled（各 77 × 40 pt），Light D 另含 Neutral Inline Active／Disabled（各 86 × 40 pt）；Dark C 新增 Primary Inline Active／Disabled（各 77 × 40 pt），Dark D 沒有 Inline variants；四組主矩陣共 160 個 variants，加上 Light C／D 與 Dark C 六個 Inline variants，共 166 個 variants。C 的 icon 在前、文字在後、間距 8 pt；D 僅有文字、間距為 0。所有文字層水平對齊 Center。
- 驗收：四組 Light／Dark、C／D component sets 共 166 個 variants 使用 Center 對齊的固定尺寸 Auto Layout；代表性的 Large／Extra Small、Filled／Ghost variants，以及 Light C／D 與 Dark C 六個 Inline variants 改寬與縮窄後，圖文組或文字置中偏移皆為 0 並已恢復原尺寸。截圖與節點讀回確認，按鈕顏色、描邊、狀態和規格尺寸保留。此為 Figma 靜態 wireframe 更新，App 未修改、未新增 prototype，未完成裝置驗證。

### 2026-10-28 Light LocationCard 與 Top / 執行指示共用元件（目前狀態）

- 04 `Light · 0 · 共用元件` 的 `Light · LocationCard` component set（`309:26980`）僅保留 `Layout=Route`（361 × 180 pt、圓角 16 pt）；`Layout=Floating` 已刪除，B5／B7／D4／E4 全改用 Route。卡片無描邊，綁 Light `color/surface/overlay/card`（`#F9F9F9F2`、95% alpha）並使用 12 pt Background Blur。
- 每張卡片左側 Go 是 C `Type=Primary, State=Active, Size=Inline`（77 × 40 pt）；右側 Star 是 B `Type=Standard, State=Enabled, Size=Large`，Copy 是 B `Type=Copy, State=Enabled, Size=Large`（各 44 × 44 pt、純 icon）；右上 Close 是 B Clear Enabled Large。Button board 不含 Location／Map Pin 專用 F 組。
- `Light · Top / 執行指示` component set（`309:26996`）有 Active／Paused 兩個 Light variants，使用 Light 95% overlay surface、primary／secondary text tokens 及 primary nav／pause icon。D6／D7 使用 Active，D10／D10.a 使用 Paused；Dark 對應 variants 已於後續 Dark 共用元件更新中建立（見下節）。D7 的 Top 位於現有 Dim overlay 下方，sheet 呈現時會被遮擋。
- Light B5／B7／D4／E4 LocationCard 與 D6／D7／D10／D10.a Top 已引用 component instances。D4／E4 PinConfirm 仍為「確認」，Figma 卡片 CTA 為 Go；PinConfirm 不屬於卡片操作列。Figma component board 與 B5、B7、D4、E4、D6、D10、D10.a 截圖及節點已核對。
- 驗收：LocationCard 只有 Route variant，B5／B7／D4／E4 均為共用 component instances；卡片無邊框，Surface 為 F9F9F2 95% alpha 並含 12 pt blur；Go／Star／Copy／Close 分別來自指定 C／B variants；Top Active／Paused 使用 Light token。這是靜態 Figma 設計更新；App 行為／SwiftUI 未同步，未新增 prototype wiring，未做裝置驗證。

### 2026-10-28 Dark LocationCard 與 Top / 執行指示共用元件

- 04 `Dark · 0 · 共用元件` 新增 `Dark · LocationCard`，只保留 `Layout=Route`（361 × 180 pt、圓角 16 pt），並新增 `Dark · Top / 執行指示` Active／Paused variants。兩者使用既有 Dark `color/surface/overlay/card`（`#2C2C2EF2`，95% alpha）、12 pt Background Blur 與陰影，不設邊框。
- LocationCard 左側 Go 使用 Dark C Primary Inline Active／Disabled（77 × 40 pt）；右側 Star 使用 Dark B Standard Enabled、Copy 使用 Dark B 新增 Copy Enabled（各 44 × 44 pt、純 icon）；右上 Close 使用 Dark B Clear Enabled。Dark B5／B7／D4／E4 改用 LocationCard，B7 Go 為 Disabled；Dark D6／D7 使用 Top Active，D10／D10.a 使用 Paused。
- 驗收：Dark 共用元件板顯示 `MAP · LOCATION CARD / Dark` 與 `TOP · EXECUTION GUIDANCE / Dark`；LocationCard 僅 Route，按鈕由 Dark 共用 B／C variants 組裝；Dark 各畫面引用對應共用 instances。元件板、代表畫面截圖、variant、surface token 與無邊框狀態已核對。這是 Figma 靜態 wireframe 更新，App SwiftUI 未同步、未新增 prototype wiring，未做裝置驗證。

### 2026-10-28 MapControls 44 pt 納入 Light Icon Button

- 將「未定義」區 `未定義 · MapControls · 44 pt 控制組` 移入 Light `0 · 共用元件（按鈕）` 的 B `ICON BUTTONS / Type × State × Size`，新增 `Type=MapControls, State=Enabled, Size=Large` 44 × 44 pt variant，並移除未定義區原展示及標籤。
- 新 variant 為 `color/surface/card` 白色圓底 `#FFFFFF`、無描邊，使用 Icon 目錄的 `icon/locate` 22 × 22 pt instance 置中；背景與 icon 均設水平／垂直 Scale constraints，保留來源控制組陰影。Light `Button / Icon` 目前共 20 個 variants，另有一個 Large Enabled `Copy` variant。
- 驗收：節點讀回為 44 × 44 pt，無描邊，底與 icon 同心；在 32 × 32 及 64 × 64 pt 尺寸讀回，背景與 icon 按比例縮放且置中，並恢復原尺寸。Light 按鈕板與「未定義」區截圖已核對；這是 Figma 靜態 wireframe 更新，未修改 App、未新增 prototype wiring，未完成裝置驗證。

### 2026-10-28 Dark MapControls 44 pt 納入共用 Icon Button

- 在 04 `Dark · 0 · 共用元件（按鈕）` 的 B `ICON BUTTONS / Type × State` 新增 `Type=MapControls, State=Enabled` 44 × 44 pt variant；component set 現有 13 個 variants，MapControls 目前只有 Enabled。
- Variant 沿用 Dark `Recenter` 視覺：`color/surface/control` `#3A3A3C` 圓底、0.5 pt `color/line/separator` `#38383A` 描邊、原有兩層陰影及 22 × 22 pt `color/icon/primary` locate 圖示。圖示容器及內部向量均設水平／垂直 Scale constraints。
- 驗收：截圖及 Figma 節點讀回確認 B 區新增 MapControls · 44 pt、Dark token、描邊和陰影正確；縮放至 32 × 32 與 64 × 64 pt 時圖示分別為 16 × 16 與 32 × 32 pt 且置中，恢復後尺寸為 44 × 44 pt。這是 Figma 靜態 wireframe 更新，未修改 App、未新增 prototype wiring，未完成裝置驗證。

### 2026-10-28 路線清單 grip UI 外框角色

- Light `color/border` 色票（section `276:22514`）改為 `subtle=#E5E5EA`、`default=#C7C7CC`、`strong=#8E8E93`、`focus=#007AFF`；default 保留原值，subtle／strong 原本同為 `#C6C6C8`，現在分別拉開明度。Dark 色票同步為 `subtle=#38383A`、`default=#48484A`、`strong=#8E8E93`、`focus=#0A84FF`；default 保留原值，strong 與 default 明顯區分。
- Light／Dark D1、D2、D8、D9 路線清單外卡沿用 subtle；一般列框使用 default，被 grip 抓取的列使用 focus。D8 原紅色選中框改用 focus。
- 新增 Light `D2 · 路線規劃 / 拖曳排序示意`（frame `309:27349`）與 Dark 對應 frame（`309:27509`）。兩者示範 `台北 101` 抓取列、一般列及空出的新順序位置框；位置框使用 2 pt strong 描邊，Light `#8E8E93` 與 default `#C7C7CC` 有明顯差異，Dark `#8E8E93` 與 `#48484A` 有明顯差異。D2 拖曳排序示意是靜態討論 wireframe，沒有 prototype wiring，且只涵蓋面板 route list grip UI；全螢幕可編輯清單仍沒有對應 wireframe。
- Light／Dark Color Scheme 與 Light／Dark D1、D2、D2 拖曳排序、D8、D9 渲染截圖已核對，並讀回兩主題 D1／D2／D8／D9 的 row border roles。此為靜態 Figma／規格更新；未修改 App SwiftUI、未做裝置驗證。
