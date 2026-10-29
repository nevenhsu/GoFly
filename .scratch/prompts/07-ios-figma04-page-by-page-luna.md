# 任務：Figma 04 UI 大更新，iOS App 要逐頁更新（給 Luna）

你在 repo `/Users/neven/Documents/projects/ianygo` 工作，對象是 iOS App `app/GoFly`（SwiftUI、iOS 26、Swift 6）。

## 一、發生了什麼事

Figma 檔『GoFly · UI 線框討論』（fileKey `RtPV8PXCQJ2WXK3jk3kPrq`）的頁面 `04 · iOS Redesign（Google Maps 參考）`（node `121:50359`）**經過大幅更新**，App 目前的畫面與它有大量差異。它是 iOS UI 的**唯一視覺準據**（以渲染畫面為準，舊頁 `01 · iOS App` 已廢棄、不可參考；規格文字與渲染衝突時以渲染為準）。你的工作是**一頁一頁**把 App 更新成與 Figma 一致，不是只修幾個點。

Figma 這一輪的主要變更（與 App 目前的差異來源）：

1. **Light 全部完成，Dark 已重建成與 Light 一一對應**：A–F 每個 section 的 frame、元件、說明文字結構在 Light／Dark 兩邊相同；Dark 的所有元件 instance 都改指向 `Dark ·` 共用元件。
2. **Dark 色彩重新分階**（畫面底近純黑）：canvas `#0B0B0D` → Tab／Sheet／info card `#1A1A1C` → Sheet 上的按鈕與 list、輸入欄 `#2C2C2F` → active／focused `#48484D`；LocationCard 比 Sheet 亮一階 `#232326`（95%）；地圖底 `#131315`。Light 為 canvas `#EEEEF3` → card `#FBFBFD` → control `#DEDEE4` → active `#B9B9BF`。色票以 Figma 變數（`GoFly iOS / Light Theme`、`Dark Theme`、`Common Color`）為準，`docs/IOS-COLOR-SCHEME.json` 是快照。
3. **共用元件整組重做**（`Light／Dark · 0 · 共用元件（按鈕）`、`0 · 共用元件`）：Icon Button 四種尺寸（Large 44／Medium 40／Small 36／Extra Small 32，Enabled 圓形外框 `line/separator` 0.5 pt）、按鈕內容置中、Primary 按鈕文字與圖示純白、Status action 透明底、Text Field、Toast／Snackbar／StatusPill、LocationCard、Top 執行指示（底色與下方執行面板相同的實色）、MapControls 44 pt、Map Pin（primary 線條、白字白箭頭）、Slider、Chip、清單列、Sheet、Tab Bar、Overlay／Dim（**黑色** 40%）、原生鍵盤與系統分享 sheet 的 Dark 配色。
4. **圖示**：一律使用 `0 · 共用元件（Icon）` 的 52 個 `icon/*`，App 要匯出成資產、不用 SF Symbol（見票 03）。
5. **地圖一律滿版**（延伸到狀態列、Tab Bar、home indicator 後方）。
6. **Toast 一律懸浮**（疊在導覽列／搜尋列下方、不推動版面、帶浮層陰影）。
7. **層級規則**：Sheet 上的 list 與按鈕比 Sheet 亮兩階；active／focused 再亮三階；路線停靠點選中列＝primary 邊線＋中性底（不是 primary 底）；步驟圓點數字為白字；Hero icon 底色為中性 control 色（App icon 本身維持白底）。
8. **新 UX**：路線『＋ 新增停靠點』加在最後當終點；無法規劃路線 toast 按鈕『修正』（系統自動重排全部地點含起點再規劃）；設定服務卡永遠只有一顆按鈕（正常『啟動模擬』／運行中『停止服務』／停止失敗『重置連線』，重置成功後變『啟動模擬』並懸浮顯示 success toast）；D5 選點頁輸入為空時才顯示『使用目前位置』與『最近搜尋』；R05 連線說明精簡版（三列步驟＋一則提示）。

## 二、先讀（必做）

1. `AGENTS.md`、`app/GoFly/ARCHITECTURE.md`（命令與送點不變量，不可破壞）。
2. `.scratch/gofly-ios-figma04/TRACKER.md` 與 `issues/`：**這就是逐頁更新的待辦清單與驗收條件**（票 00–19，含 01a 截圖驗證工具）。本 prompt 只說明背景與做法；每票細節以票為準。
3. `.scratch/prompts/05-ios-figma04-luna.md`（共同規則與已決定事項）、`.scratch/prompts/06-ios-device-feedback-luna.md`（實機截圖回饋：B1 Dark Tab Bar／地圖深色、R04 Light 層級、R05 精簡、Toast 懸浮）。
4. `docs/IOS-UI-DESIGN.md`（2026-10-29 各節是最新設計決定）、`docs/IOS-TYPOGRAPHY.md`、`docs/IOS-COLOR-SCHEME.json`、`docs/IOS-STATUS-ERRORS.md`、`docs/FIGMA-UI-RECONCILIATION.md`。

## 三、逐頁做法（每一頁都照這個流程）

Figma section（Light／Dark 同名，Dark 加前綴 `Dark · `）：

| 順序 | Section | Light node | Dark node |
| --- | --- | --- | --- |
| 1 | A 啟動與首次引導（R01–R08） | `121:51099` | `121:53972` |
| 2 | B 地圖首頁、搜尋、地點 sheet、瞬移（B1–B11） | `121:51311` | `121:54177` |
| 3 | C 最愛地點（C1–C4） | `121:52108` | `121:54958` |
| 4 | D 路線（D1–D23） | `121:52563` | `121:55411` |
| 5 | E 搖桿與漫步（E1–E7） | `121:53055` | `121:55887` |
| 6 | F 設定與共用規則（F1–F9、F1.a、F1.b、F6.a） | `121:53501` | `121:56323` |

先完成基礎票（01a 截圖工具 → 01 色彩 → 02 字級 → 03／04／05 共用元件），再按 A→F 一頁一頁做。**每一個 frame**：

1. 用 Figma Console 讀取該 frame 的渲染截圖（`figma_capture_screenshot`／`figma_take_screenshot`）與節點資料（只讀，**不得修改 Figma**），確認用到哪些共用元件與 token。
2. 對照 App 現況，列出差異（版面、色彩層級、元件、字級、圖示、文案）。
3. 實作該頁，使用共用元件與 token，不留手刻副本、不寫顏色或字級字面值。
4. 用票 01a 的 fixture（模擬器沒有網路、VPN、真機，所以要靠 fixture）開到該 frame 的狀態，**Light 與 Dark 各截一張**，存到 `work/gofly-ios-figma04/screenshots/`，與 `work/gofly-ios-figma04/figma/` 的同名 Figma 截圖並排比對（`work/` 已 git ignore，會有 `index.html` 總覽頁）。
5. 有差異就修到一致；Figma 缺漏或互相矛盾的地方**不要自行補畫或推定**，記在票尾『執行紀錄』並在回報中列出。
6. 一個 section 全部 frame 過關後，才進下一個 section；該 section 對應的票填『執行紀錄』、勾驗收項、Status 改為 `done: software-verified`。

## 四、共同規則

- 只改 UI／UX 與票內指定行為，**不改命令、送點、ACK、背景執行語意**。
- 字型一律 `Font.system`（不得 `Font.custom`／字型檔），字級字重依 `Theme/*`；圖示一律使用 Figma『0 · 共用元件（Icon）』（匯出資產經 `GoFlyIcon`），不用 SF Symbol 或自繪替代。
- 互動元件命中範圍 ≥ 44 × 44 pt；圖示按鈕有 accessibility label；最大 Dynamic Type 不裁切。
- 本地化三語（zh-Hant、zh-Hans、en）同步；`EnglishButtonLabelTests`、`IssueCatalogTests`、`TypographyStandardTests` 要過。
- 每票結束 `app/GoFly/scripts/check.sh` 必過；相關單元測試與 UI tests 更新。
- 不跑 Prettier；不安裝到手機；不 commit／push（使用者另行要求才做）；不修改 Mac App 與 `tools/`；實機驗證不在範圍，回報明講『未做實機驗證』。
- 停下規則沿用 `.scratch/prompts/00-master-order.md`「何時才停下」；其餘問題依票內建議自行決定，寫進『執行紀錄』。

## 五、最後回報

①完成的票與 frame 清單 ②未完成與原因 ③每個 section 與 Figma 仍有的差異、Figma 缺口（例如 B11 無 Dark 設計）④需要使用者決策的問題（每題一句）⑤截圖位置（`work/gofly-ios-figma04/screenshots/index.html`）⑥聲明『未做實機驗證、未 commit』。
