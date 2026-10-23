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
| `0 · 共用元件` | token、按鈕、狀態、輸入與地圖元件板 | IOS 視覺 token 與規格相符；地圖位置箭頭新增 `RealArrow / 真實位置（實心藍）`（iOS systemBlue `#007AFF` 實心向量箭頭搭配白色外框與微陰影，不使用空心），與 `SimArrow / 模擬位置（實心）`、等待（50%）並列；個別畫面若使用不同尺寸，以該畫面為準。 |
| `A · 啟動與首次引導` | R01、R02、R03、R04、R05（5 張） | 文件涵蓋 Logo 啟動、定位權限三態、VPN 失敗與共用連線說明；與畫面相符。 |
| `B · 地圖、搜尋、地點、瞬移` | B1–B8、B8.a（9 張） | 文件涵蓋全螢幕搜尋、地圖不自動置中、地點動作、Toast／snackbar 及 B8 恢復狀態；B7 瞬移失敗 Toast 動作按鈕為「重連」，底層地點 sheet 改為高度最窄模式（76 pt 可視），Go 停用。B8（斷連後有真實 GPS）底層面板顯示「目前位置」，地圖箭頭採用 `RealArrow / 真實位置（實心藍）`；B8.a（斷連後無真實 GPS）底層面板顯示「最後模擬位置」，地圖模擬箭頭轉為灰色。深色版 B7、B8、B8.a 已完整對齊淺色版（含補齊之 Dark B8、Dark B8.a 瞬移中斷恢復 Resume UI，Dark B8 亦同步套用實心藍色 RealArrow）。 |
| `C · 最愛地點` | C1–C4（4 張） | Figma C4 標示刪除後約 5 秒可復原；舊規格曾寫 2 秒，現已更正為約 5 秒。 |
| `D · 路線` | D1–D17、D1b、D2a（19 張） | 文件涵蓋地圖直接新增目的地、地圖選點、收合面板、最愛與 GPX 狀態。D13 畫面顯示快選 5／20／60／120；同頁註解另寫 5／15／40／60，規格依渲染畫面記錄 5／20／60／120。新版淺色 D4 是 Resume UI；同區舊 D4a 註解視為過期。深色版缺 D2a、D17、D1b。 |
| `E · 搖桿與漫步` | E1、E2、E3、E4、E5（5 張） | 文件涵蓋搖桿、漫步、速度設定、E5 地點卡及 E3 恢復狀態。E5 的 LocationCard 畫面尺寸為 361 × 188 pt。新版淺色 E3 是 Resume UI；深色 E3 仍是舊版背景中止畫面，兩者不一致。 |
| `F · 設定與共用規則` | F1–F9（9 張） | 文件涵蓋設定首頁與定位、VPN、背景、語言、外觀、裝置簽名子頁；與畫面內容相符。 |

淺色畫面共 51 張（A 5、B 9、C 4、D 19、E 5、F 9）；深色畫面共 48 張（A 5、B 9、C 4、D 16、E 5、F 9）。深色 B 區已補齊 Dark B8、Dark B8.a 並與淺色完全對齊；B5（地點選取／放 Pin）淺色與深色為 LocationCard 獨立地點卡覆蓋於底層，B7（瞬移失敗）Toast 按鈕為「重連」且底層為高度最窄 panel；深色頁仍缺 D2a、D17、D1b；深色 D4、E3 仍為舊版提示，並非淺色新版的深色對應。缺畫面或狀態的視覺驗收須記為未定義，不能以文件文字宣稱 Figma 已提供設計。

Figma 中名為 D4a／E3a 的舊註解，與目前淺色 D4／E3 畫面不同；以新版畫面為準。D13／E4 快選註解也與實際畫面不同；以渲染畫面為準。這些差異是 Figma 內部註解與畫面不同步，尚未修改 Figma。

## 05 · Mac Redesign 對照

Figma 與規格的畫面數一致：淺色、深色各 34 張；M1 環境設定 E01–E08 共 8 張、M2 首次安裝 I01–I09 共 9 張、M3 裝置管理 G01–G17 共 17 張。新版 Mac 視覺與流程規格已依此分節。舊 `02 · Mac App` 畫面不再作新版基準。

唯一已確認的跨規格差異是 M2 I09 的「USB 中斷後從頭安裝、重建配對」敘述，和目前安裝交易規則不一致。實際寫入中斷須保留原 `setupID`，先查 status，只在明確可續時 resume；因此 I09 的畫面文案不可改變實際交易流程。詳見 [`MAC-UI-DESIGN.md`](MAC-UI-DESIGN.md) 與 [`AI-INSTALL.md`](AI-INSTALL.md)。

## 未來更新方式

每次 UI 工作先查閱對應平台的 04 或 05 頁及當前畫面；修改規格時列出畫面代號、差異、採納的 Figma 畫面規則，以及未實作／未驗收項目。若畫面與 Figma 註解彼此衝突，記錄該差異並以畫面為視覺依據；不要把不存在的深色或其他狀態寫成已設計。
