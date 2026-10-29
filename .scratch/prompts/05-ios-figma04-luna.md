# 任務：iOS App 依 Figma 04 按順序更新 UI／UX（給 Luna）

你在 repo `/Users/neven/Documents/projects/ianygo` 工作，對象是 iOS App `app/GoFly`（SwiftUI、iOS 26、Swift 6）。請依票單 `.scratch/gofly-ios-figma04/issues/` **按編號順序**實作，一票一票做完再做下一票。總覽與依賴見 `.scratch/gofly-ios-figma04/TRACKER.md`。

> 停下規則沿用 `.scratch/prompts/00-master-order.md`「何時才停下」。其餘問題照票內建議自行決定，寫進該票『執行紀錄』後繼續。

## 一、先讀（必做）

1. `AGENTS.md`：視覺唯一準據是 Figma 檔『GoFly · UI 線框討論』（fileKey `RtPV8PXCQJ2WXK3jk3kPrq`）頁面 `04 · iOS Redesign（Google Maps 參考）`（node `121:50359`）的**渲染畫面**；舊頁 `01 · iOS App` 已廢棄，不可參考。規格文字與渲染衝突時以渲染為準，並在同一票修正文件。
2. `app/GoFly/ARCHITECTURE.md`（命令與送點不變量，**不可破壞**）。
3. `docs/IOS-UI-DESIGN.md`、`docs/IOS-TYPOGRAPHY.md`、`docs/IOS-COLOR-SCHEME.json`、`docs/IOS-STATUS-ERRORS.md`、`docs/ROUTE-MODE-TASKS.md`、`docs/FIGMA-UI-RECONCILIATION.md`。
4. 你要做的那一票全文與它 Blocked by 的票的『執行紀錄』。

## 二、怎麼看 Figma

- Light section：`A`（`121:51099`）、`B`（`121:51311`）、`C`（`121:52108`）、`D`（`121:52563`）、`E`（`121:53055`）、`F`（`121:53501`）。Dark section 為同名加 `Dark · `（`121:53972`、`121:54177`、`121:54958`、`121:55411`、`121:55887`、`121:56323`），兩邊 frame 一一對應。
- 共用元件板：`Light／Dark · 0 · 共用元件（按鈕）`、`Light／Dark · 0 · 共用元件`；色票：`Light／Dark · Color Scheme`、`Common Color`；字級：`0 · 共用元件（Typography）`；icon：`0 · 共用元件（Icon）`。
- 用 Figma Console（`figma_capture_screenshot`、`figma_execute` 讀取）或 Figma 畫面截圖取得渲染與數值。只讀，**不得修改 Figma**；發現 Figma 缺漏或矛盾，記在票尾『執行紀錄』與回報，不要自行補畫或推定。
- 每張 frame 下方的說明文字是行為規格；與本票單衝突時以票單與第四節決定為準。

## 三、共同規則

- 只改 UI／UX 與票內指定行為，不改命令、送點、ACK、背景執行語意。
- 顏色與字級一律走 01、02 建立的 token；不得在 View 內寫顏色或字級字面值（地圖原生元件與系統控制例外並列清單）。
- **圖示一律匯出成資產，不使用 SF Symbol**：Figma『0 · 共用元件（Icon）』的 52 個 `icon/*` 全部匯出為單色 template 資產，由單一 `GoFlyIcon` 入口提供；票 03 建立 `icon/*` ↔ 資產對照表並替換全部既有 SF Symbol（系統原生控制例外）；目錄沒有的圖示列出回報，不要自行新增或挑相近圖示。
- 每個畫面使用共用元件，不留手刻副本；互動元件命中範圍 ≥ 44 × 44 pt、圖示按鈕有 accessibility label、最大 Dynamic Type 不裁切。
- 驗證：`app/GoFly/scripts/check.sh`（核心測試＋unsigned simulator build）每票結束必過。**每票完成都要截圖驗證**：模擬器沒有網路、VPN、真機，所以票 01a 先建立 Debug＋模擬器專用的 fixture 層（沿用 `GoFlyUITestOverrides` 模式，Release／真機 build 無作用），可直接開到任一 Figma frame 的狀態；之後每票對自己涵蓋的每張 frame、Light 與 Dark 各截一張到 `work/gofly-ios-figma04/screenshots/`，與 `work/gofly-ios-figma04/figma/` 的 Figma 截圖並排比對，結論與路徑寫進票尾『執行紀錄』。沒有截圖的票不算完成；到不了的 frame 如實回報，不得略過。
- 不要執行 Prettier；不要安裝到手機；不要 commit／push（使用者另行要求才做）；不修改 Mac App 與 `tools/`。實機驗證不在本任務範圍，回報時明講『未做實機驗證』。
- 本地化：新增或改動文案要同步 `zh-Hant`、`zh-Hans`、`en` 三份，`EnglishButtonLabelTests` 與 `IssueCatalogTests` 要過。
- 完成一票後：勾選票內 checkbox、填『執行紀錄』（日期、完成項、截圖位置、差異與 Figma 缺口）、把 Status 改為 `done: software-verified`；有文件需更新就同票更新（區分 Figma 設計、App 實作、實機驗證）。

## 四、本輪已決定（不要再問）

- **地圖一律滿版**：任何有地圖的畫面，地圖都填滿整個螢幕（忽略四邊 safe area，延伸到狀態列、Dynamic Island、Tab Bar、home indicator 後方），其餘 UI 疊在地圖上；不得有地圖縮小、留邊或色帶。Figma 的 `Map / Base` 為 393 × 852 滿版畫面，以此為準。

- 新增停靠點：新空欄位加在清單最後並成為終點，原終點降為停靠點（票 10）。
- 無法規劃路線：按鈕『修正』，自動重排**全部**地點（含起點）後重新規劃；成功就採用新順序，失敗保留原順序與 toast（票 11）。
- 服務卡：永遠只有一顆主按鈕。正常已停止＝『啟動模擬』、運行中＝『停止服務』、停止失敗／服務卡住＝『重置連線』；重置成功後按鈕變『啟動模擬』並在導覽列下方以懸浮方式顯示 success toast（疊在內容上方、不推動版面）（標題『已重置連線』、說明『可以重新啟動模擬』）；重置失敗不顯示錯誤、只保留『GPS 未確認』（票 17）。
- Dark 階梯：畫面底 `#0B0B0D`、Tab／Sheet／info card `#1A1A1C`、Sheet 上按鈕與 list `#2C2C2F`、active／focused `#48484D`；遮罩為黑色 40%；Primary 按鈕文字與圖示純白；Enabled 圓形 Icon Button 外框 `line/separator` 0.5 pt。
- 路線停靠點選中列：primary 邊線、中性底（Light＝card、Dark＝active），不用 primary 底。
- 遮罩、Sheet、清單層級：Sheet 上的 list／按鈕底色比 Sheet 亮兩階；active／focused 再亮三階。
- Figma 缺口（不要自行補）：B11 無 Dark 設計；票 00 完成前 D8 仍顯示『重試』、F1.b 不存在——票 00 由 Claude 先完成，票 10、11、17 在 00 完成後才開始。

## 五、執行順序

`00（Claude）→ 01a → 01 → 02 → 03／04 → 05 → 06 → 07 → 08 → 09 → 10 → 11 → 12 → 13 → 14 → 15 → 16 → 17 → 18 → 19`。每票開工前確認它的 Blocked by 都已 `done`。完成全部後依票 19 回報：①完成票號 ②未完成與原因 ③需要使用者決策（每題一句）④每個 section 的差異與 Figma 缺口 ⑤聲明『未做實機驗證、未 commit』。
