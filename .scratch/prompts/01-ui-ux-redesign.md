# 任務：GoFly iOS UI／UX flow 重構（參考 Google Maps）

你在 repo `/Users/neven/Documents/projects/ianygo` 工作，對象是 iOS App `app/GoFly`（SwiftUI，iOS 26，Swift 6）。請依已核可的改版計畫重構 UI 與操作 flow。**只改 UI／UX，不改命令、送點、背景執行的語意。**

> **停下規則**：依 `.scratch/prompts/00-master-order.md`「何時才停下」。其他問題照本文件建議做法自行決定，寫進 `work/gofly-dev/DECISIONS.md` 後繼續。

---

## 一、計畫與規格檔案（先全部讀完再動手）

| 優先序 | 檔案 | 用途 |
| --- | --- | --- |
| 1 | `AGENTS.md` | 專案規則 |
| 2 | `work/gofly-planning/IOS-GOOGLE-MAPS-REDESIGN-PLAN.md` | **改版計畫本體**：第 3 節骨架、第 4 節各環節新 flow、第 5 節 19 則 comments 對照、第 6 節決策、第 8 節背景權限決定。`work/` 不進版控，但在本機可讀 |
| 3 | `docs/IOS-UI-DESIGN.md` 的「Google Maps 參考改版」一節 | 取代規則表、新 token、**改版驗收條件**（逐條驗收用） |
| 4 | `work/gofly-planning/GLOSSARY.md` | 用語定義（Go、執行模式、StatusBanner、snackbar、最愛刪除…） |
| 5 | `DESIGN.md`、`app/GoFly/ARCHITECTURE.md` | 視覺 token、不可破壞的不變量 |
| 6 | Figma 檔「GoFly · UI 線框討論」→ 頁面「04 · iOS Redesign（Google Maps 參考）」 | 淺色、深色各 40 張靜態畫面，每張下方有說明。無法存取 Figma 時，以 2、3 為準 |
| 7 | `.scratch/bug-report/IMG_*.PNG` | 實機截圖，對應計畫第 5 節 comments |

文件之間有衝突時，以 `docs/IOS-UI-DESIGN.md` 的改版驗收條件為準，並在回報中指出衝突。

---

## 二、已決定的方案（摘要；細節以計畫檔為準）

**主畫面骨架**（由上到下）
- 浮動搜尋列（右側齒輪進設定）＋狀態 pill → 地圖 → 右側地圖控制 → bottom sheet（收合／半開／全開）→ bottom bar。
- 右側地圖控制只有「指北」（地圖旋轉後才出現）和「置中到模擬位置」，執行模式多一顆「跟隨方向」。**不做圖層／Layers**。
- Bottom bar 只有**瞬移／路線／搖桿**三個等寬 tab。最愛不設 tab。

**搜尋與瞬移**
- 搜尋是全螢幕頁：鍵盤出現時隱藏地圖、pill、tabs。結果是無框列表，可直接輸入經緯度。
- 搜尋（地圖全螢幕搜尋與路線欄位搜尋）同時比對最愛地點的自訂標籤（label），例如輸入「公司」可找到標為「公司」的最愛地點；結果列以標籤為標題、地址為副標。
- **Go 放兩處、同一動作**：
  - 候選 Pin 上方的小型 Go（約 28 pt 高，點擊範圍 ≥ 44 pt）。
  - 地點 sheet 動作列第一個（依序 Go、★ 收藏、設為起點／終點、複製）。
- sheet 不放「Go 會把模擬位置移到此地點」這類自明說明。
- 點地圖放 Pin 時鏡頭不動，只有 Pin 被 sheet 遮住時才最小幅度平移。

**路線**
- 起點、途經點、終點疊成一張清單，可交換、可新增停靠點；**點選搜尋結果即回填並返回**，不需要確認。
- 匯入 GPX：
  - 入口：路線 sheet 右上「路線資料夾」按鈕。icon 用資料夾類（例如 SF Symbol `folder`），不要用 `doc` 類，避免和「複製」混淆。
  - 匯入：系統檔案選擇器（GPX／XML、上限 2 MiB）。成功時新路線列在最上方，並顯示 snackbar「已匯入「檔名」」（動作「載入」）；失敗時清單頂端顯示 danger StatusBanner，原清單不變。
  - 清單操作：點一下路線開底部動作選單：載入路線、查看全部點位、匯出路線、刪除路線（紅字）、取消；不使用左滑。「匯出路線」開系統分享 sheet；「刪除路線」後 snackbar 可復原（Figma D11–D12）。
  - **匯入路線不可編輯**：不顯示把手、刪除、新增停靠點、反轉。
  - 10 點以下以唯讀清單完整列出。
  - **超過 10 點**：地圖畫完整路線。sheet 依序列出起點、第 2 點、「中間 N 點」、終點，最後一列「查看全部 N 點」開唯讀可捲動清單；點列只在地圖定位該點。
- 執行模式（路線與漫步）：
  - 隱藏 bottom bar 和搜尋列。
  - 頂部是深色指示卡。
  - 底部固定進度、暫停／繼續、✕ 結束（需確認）。

**最愛**
- **點星號**：變空心，約 0.5 秒後刪除；期間再點一次恢復實心＝取消。刪除後 snackbar「已刪除 1 項・復原」。
- 「⋯」開編輯 sheet（改標籤、刪除）。
- 「選取」可多選批次刪除，同樣可復原。
- 底部固定「搜尋最愛地點」，只搜尋已收藏的地點。

**搖桿／漫步**
- 搖桿重新設計：刻度、陰影、拖曳高亮、觸覺回饋、回彈動畫。
- 搖桿在搖桿 tab 與漫步執行模式**同為 150 pt**。
- 「隨機目的地」改成帶 ⟳ 的次要按鈕。

**錯誤與狀態**
- 一律用 **StatusBanner**（danger／warning／success，圖示＋文字），固定在 sheet 或執行面板頂端，最多一個主要動作。
- **修復指引寫在 banner 說明內**，例如「持續失敗請到「設定 › VPN 通道」修復」。
- 一次性結果用 2 秒 snackbar。pill 的顏色和 banner 同步。

**首次引導與設定**
- 首次引導定位頁顯示目前權限狀態：尚未設定（「允許定位」跳系統視窗，可略過）／已允許（綠色「已允許」，主要按鈕改「下一步」，不跳視窗、不顯示略過）／已拒絕（warning，主要按鈕改「前往設定」，仍可略過）。避免已允許時按鈕沒反應被誤以為壞掉（Figma R02／R03）。
- Launch Screen 用 Logo。設定檢查在背景進行，超過約 0.5 秒才顯示細進度條。
- 定位權限只請求「使用 App 期間」，**不要求「永遠」、沒有升級 sheet**。背景持續靠 `BGContinuedProcessingTask`。
- VPN「連線說明」頁：首次引導 VPN 失敗頁與設定 › VPN 通道共用同一頁，內容沿用 `onboarding.vpn.help.*` 文案。
- 「開啟 LocalDevVPN」在所有入口行為一致：先開 `localdevvpn://`；系統回報無法開啟（未安裝）時，改開 App Store 頁 `https://apps.apple.com/app/localdevvpn/id6755608044`；連 App Store 也打不開時，才顯示「請手動到 App Store 搜尋 LocalDevVPN」。目前只有首次引導（`GoFlyOnboardingView.openLocalDevVPN`）會改開 App Store，設定頁（`GoFlySystemStatus.openLocalDevVPN`）只顯示失敗，請抽成共用函式統一。
- 頂部不再放啟動／暫停：暫停／繼續在執行模式控制列，停止服務在設定。
- 設定子頁：
  - 定位權限：「使用期間」為正常，只有「拒絕」標 warning。
  - VPN 通道。
  - 背景執行。
  - 語言與外觀：原生 Picker。
  - 裝置與簽名。

**版面一致性**
- 底部主要按鈕下緣對齊 safe area 底部（距螢幕底 34 pt）；有 bottom bar 時放在 bottom bar 上方。
- 右側地圖控制貼在 sheet／面板上方 16 pt，按鈕間距 8 pt。
- 深色模式用語意色自動切換，不寫死色碼。

---

## 三、實作步驟（依序；每步可獨立建置、測試、commit）

| 步驟 | 內容 | 主要檔案（`app/GoFly/App/`） |
| --- | --- | --- |
| 0 | 盤點：列出現有畫面對應到新 flow 的哪一張，標出要刪、要改、要新增的 view。把清單寫到 `work/gofly-ios/redesign/INVENTORY.md` 後直接動工 | 全部 |
| 1 | 共用元件：danger／warning／success token；`StatusBanner`、`Snackbar`、狀態 pill、三段式 bottom sheet 骨架、執行模式面板骨架；`GoFlySymbols` 補符號 | `GoFlyStyle`、`GoFlySymbols`，新元件檔 |
| 2 | 主畫面骨架：浮動搜尋列＋齒輪、pill、右側地圖控制、bottom bar；拆掉舊的頂部狀態卡與面板內膠囊模式列 | `GoFlyMapView`、`GoFlyOperationPanel`、`GoFlyMapCanvas` |
| 3 | 搜尋與瞬移：全螢幕搜尋、地點 sheet、兩處 Go、點地圖不置中、瞬移成功／失敗呈現 | `GoFlySearchPanel`、`GoFlyPlaceDetailsView`、`GoFlyPlaceOptionCard` |
| 4 | 路線：規劃清單、點選即回填、路線資料夾入口、匯入／匯出 flow、唯讀載入（≤10／>10）、全部點位清單、執行模式 | `GoFlyRoutePanel`、`GoFlyRouteNodeList`、`GoFlyRoutePickerView`、`GoFlyImportedRoutesView`、`GoFlyGPXPreview`、`GoFlyGPXFileAccess` |
| 5 | 搖桿／漫步：新搖桿外觀與互動、漫步進入執行模式 | `GoFlyJoystickPanel` |
| 6 | 最愛：星號延遲刪除與取消、編輯 sheet、多選、復原 snackbar、底部搜尋 | `GoFlyFavoritesView`、`GoFlyFavoriteRoutesView`、`GoFlyFavoriteRouteSaveView` |
| 7 | 錯誤統一：把散落的錯誤區塊（`.background(GoFlyStyle.errorSurface…)`）全部換成 StatusBanner／snackbar，修復指引寫進 banner | 全部 |
| 8 | 首次引導與設定：Launch Screen、連線說明頁、設定入口與子頁 | `GoFlyOnboardingView`、`ServiceSettingsView`、`GoFlySettingsPages`、`GoFlySettingsValueRow` |
| 9 | 全面驗收：逐條對照 `docs/IOS-UI-DESIGN.md` 改版驗收條件，補 UI 測試與截圖 | `UITests/` |

---

## 四、注意事項

**不可破壞**
- 不改 `GoFlyCore` 的命令語意：`ServiceController` FIFO、`PointDispatchGate`、ACK 規則、`unconfirmed` 鎖定、Stop／clear 流程、`MovementContinuationController`、`ContinuedProcessingController`。UI 只讀狀態並呼叫既有入口。確實需要新的 Core API 時，保持最小，並在回報中說明理由。
- 「位置待確認」（規則 #7）時，**兩處 Go 都停用**。
- 星號延遲刪除的 0.5 秒期間只是 UI 狀態，逾時才呼叫既有刪除；取消時不得產生任何寫入。復原沿用 store 既有的「最近一次刪除」機制。
- 匯入路線唯讀是 UI 層限制，不要改動 GPX 資料格式或 store schema。

**範圍外**
- 功能 bug（#15 箭頭方向、#18 漫步斷線、模擬位置突然停止）另有修正軌，遇到只記錄、不修。#14「點選即回填」屬本次 UX 範圍，可以做。
- comment #17（Random 應該是文字還是按鈕）尚未釐清：依計畫 4.9 建議實作，回報中標「待 Nathan 確認」。
- 不改 Figma、不加 prototype。

**專案規則**
- 不跑 Prettier。不提交憑證或 `work/` 產出。
- 保留工作樹中其他未提交的修改（目前有 onboarding 和 transport 的變更），不要覆蓋或還原。
- 三語字串（`Resources/{en,zh-Hans,zh-Hant}.lproj/Localizable.strings`）同步新增，刪除不再使用的 key。
- 規格有偏離或補充時，同一步驟內更新 `docs/IOS-UI-DESIGN.md` 和 `work/gofly-planning/GLOSSARY.md`，直接改掉被取代的舊規則，不要只在後面追加。
- 文件中明確區分「已實作」「模擬器已驗證」「待真機驗證」。

---

## 五、每步驟的驗證

- `bash app/GoFly/scripts/check.sh` 必須通過（SwiftPM 測試＋模擬器建置）；失敗時附輸出。
- 更新或新增對應 UI 測試與 accessibility identifier。
- 模擬器截圖：淺色、深色、Accessibility 大字級，存到 `work/gofly-ios/redesign/step-N/`。
- 對照 Figma 同名畫面與改版驗收條件逐條勾選。

## 六、回報格式（每步驟）

1. 改了哪些檔案、刪了哪些 view／字串 key。
2. `check.sh` 結果與 UI 測試結果。
3. 截圖路徑，以及與 Figma 的差異。
4. 已勾選與未完成的驗收條件，待確認事項。
5. 不宣稱真機行為已驗證。
