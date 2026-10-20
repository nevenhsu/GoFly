# 任務：GoFly for Mac UI／UX 改版

你在 repo `/Users/neven/Documents/projects/ianygo` 工作，對象是 macOS App `app/GoFlyMac`（SwiftUI，macOS 15+，Swift 6；後端是 Python bridge `app/GoFlyMac/Bridge/`）。請依新版設計重構 Mac App 的介面與流程。

範圍分兩類，**界線要清楚**：
- 只動 UI 的部分：直接照設計做。
- 需要新後端能力的部分：依開發計畫 `work/gofly-planning/MAC-RESET-BACKUP-PLAN.md` 實作。

> **停下規則**：依 `.scratch/prompts/00-master-order.md`「何時才停下」。其他問題照本文件建議做法自行決定，寫進 `work/gofly-dev/DECISIONS.md` 後繼續。

---

## 一、設計與規格檔案（先全部讀完）

| 優先序 | 檔案 | 用途 |
| --- | --- | --- |
| 1 | `AGENTS.md` | 專案規則 |
| 2 | `docs/MAC-UI-DESIGN.md` 的「新版 UI／UX 改版（2026-10-20，設計更新）」一節 | **改版規格與驗收條件**；與同文件上方舊規則衝突時以此為準 |
| 3 | `app/GoFlyMac/DEVELOPMENT.md` | 不可破壞的交易、journal、renew、到期日、完成判定規則，與開發驗收表 |
| 4 | `app/GoFlyMac/Bridge/PROTOCOL.md`、`app/GoFlyMac/README.md` | bridge 契約、現有能力與開啟方式 |
| 5 | Figma 檔「GoFly · UI 線框討論」→ 頁面「05 · Mac Redesign（新版）」 | 淺色、深色各 34 張靜態線框：M1 環境設定 E01–E08、M2 首次安裝 I01–I09、M3 裝置管理與備份 G01–G17；每張下方有說明。無法存取 Figma 時以第 2 項為準 |
| 6 | Figma 頁面「02 · Mac App」 | 舊版流程，只作對照，不再照做 |
| 7 | `work/gofly-planning/MAC-RESET-BACKUP-PLAN.md` | **需求已確認**的開發計畫：Phase 0 取消接續（中斷即重新安裝）、Phase 1 備份與備份管理頁、Phase 1.5 更新簽名、Phase 2 重置、Phase 3 還原（含 iOS 改動） |

---

## 二、現況與差異（動工前請自行核對並回報）

**現有程式**
- `Sources/GoFlyMac/`：`MacRootView`、`MacEnvironmentGate`、`MacPages`、`MacSetupPage`、`DesignSystem`。
- `Sources/GoFlyMacCore/`：`MacAppModel`、`MacSetupModel`、`BridgeWire`、`ProcessBridge`。

**bridge 現有能力**
- 唯讀：`environment`、`devices`、`inspect`。
- 寫入：`preflight`／`apply`／`status`／`resume`。
- 交易 `mode` 只有 `install` 和 `renew`。

**設計與現況的差異**

| 設計 | 現況 | 處理方式 |
| --- | --- | --- |
| 環境檢查多一步「命令列工具」（E03） | 沒有獨立檢查 | 可新增唯讀檢查（例如 `xcode-select -p` 是否指向 Xcode），不得代跑 `xcode-select --install`、sudo 或 `-runFirstLaunch` |
| 首次安裝 6 步：連接 → 信任 → 開發者模式 → 確認 → 安裝 → 完成 | 4 步 | 「信任」「開發者模式」用既有 inspect 錯誤碼（`trust-required`、`developer-mode-required`）判斷；已通過就自動略過 |
| 安裝中鑰匙圈引導（I05） | 無 | UI 層：簽署階段等待超過約 5 秒時顯示引導。不需要新 bridge 能力；若需要階段細分回報，自行在 bridge 加最小的回報欄位並記錄 |
| 完成頁「信任開發者」與「未受信任的開發者」插圖（I07） | 只寫開啟 LocalDevVPN、GoFly | 只改文案與插圖 |
| 裝置管理三個動作卡（G01）、更新簽名確認（G07、G17）、未安裝 GoFly（G15、G16） | 單一按鈕：「延長簽名期限」或「更新 GoFly」，都走 `renew` | 依第四節第 1 項 |
| 「更新 GoFly」確認頁列出保留清單 | 無 | 列出類別（最愛地點、最愛路線、已匯入路線、偏好設定）；筆數取自最新一份備份的 manifest（計畫 Phase 1），沒有就只列類別，不猜測 |
| 重置、備份、還原、備份管理頁（G05–G06、G09–G13） | bridge 沒有這些能力；`Bridge/Reinstall`、`Bridge/Backup` 只剩殘留測試資料夾 | 依開發計畫的 Phase 順序實作（見第三節） |
| 中斷處理 | 現有「繼續上次安裝」（resume） | 改為「中斷即從頭重新開始」，依計畫 Phase 0 |
| 連線限制、重新搜尋裝置（G14、側欄） | 未區分 | Wi‑Fi 只能更新簽名；側欄裝置清單加「↻ 重新搜尋」（唯讀） |

---

## 三、實作步驟（每步可獨立建置、測試、commit）

| 步驟 | 內容 | 主要檔案 |
| --- | --- | --- |
| 0 | 盤點：列出新設計每張 frame 對應的現有 view／狀態，標出可直接做、需新 bridge 能力、需決定的項目。寫到 `work/gofly-mac/redesign/INVENTORY.md` 後直接動工 | 全部 |
| 1 | 共用版面與元件：1120 × 760 預設視窗；240 pt 側欄（四個導覽＋流程步驟清單＋裝置清單）；內容區麵包屑／標題／說明；底部固定分隔線與右對齊按鈕；StatusBanner（danger／warning／success／資訊）；**系統視窗引導元件**（左側編號步驟＋右側示意插圖＋橘色「點這裡」標示） | `DesignSystem`、`MacRootView`，新元件檔 |
| 2 | M1 環境設定 E01–E08：一次只顯示第一個未通過的步驟、每步「重新檢查」、App 回前景自動重新檢查；命令列工具、Xcode 元件、Apple 帳號的系統視窗引導；Team 選擇；App 資源與 Python 環境的可區分錯誤 | `MacEnvironmentGate`、`MacPages`、`MacAppModel` |
| 3 | M2 首次安裝 I01–I09：6 步側欄；信任與開發者模式引導（自動輪詢、通過即前進）；確認頁；鑰匙圈引導；進度；完成頁；已安裝分流（I08）；中斷後只能「重新安裝」（I09） | `MacSetupPage`、`MacSetupModel` |
| 4 | M3 裝置管理 G01–G04、G07–G08、G14：裝置總覽、更新 GoFly、更新簽名、Wi‑Fi 限制、重新搜尋裝置 | `MacPages`、`MacAppModel` |
| 5 | 開發計畫 Phase 0：取消接續、中斷即重新開始（bridge＋UI） | `Bridge/Setup/*`、`MacSetupModel` |
| 5b | Phase 1：iOS 偏好設定鏡像檔、bridge `backup`、備份管理頁 G09–G10、更新前備份 | bridge、`MacPages`、iOS `GoFlyPreferences` |
| 5b2 | Phase 1.5：更新簽名的版本比對與確認步驟 G07、G17 | UI（沿用 renew） |
| 5c | Phase 2：重置 G05–G06 | bridge＋UI |
| 5d | Phase 3：還原 G11–G13（含 iOS `RestoreIngress`） | bridge＋UI＋iOS |
| 6 | 全面驗收：逐條對照 `docs/MAC-UI-DESIGN.md` 新版驗收條件與 `DEVELOPMENT.md` 開發驗收表 | `Tests/` |

---

## 四、已有建議做法的事項（照建議做，記錄在決策紀錄，不必停下）

1. **「更新簽名」與「更新 GoFly」的分工**（已決定）：
   - 「更新簽名」只為延長使用期限，可用 Wi‑Fi，沿用 `renew`。版本一致時版本不變；版本不一致（或讀不到手機版本）時先顯示確認步驟 G17（例如 build 21 → build 24），確認後直接覆蓋成 Mac 上的版本，資料保留。依開發計畫第 5a 節。
   - 「更新 GoFly」＝換成 Mac 上的新版本並更新簽名，只限 USB。
   - 裝置未安裝 GoFly 時，兩者與重置、備份、還原都停用，提示先完成首次安裝（G15、G16）。
2. **重置、備份、還原、取消接續**：需求已由使用者確認，依 `work/gofly-planning/MAC-RESET-BACKUP-PLAN.md` 實作。實作細節（檔名、上限數字、錯誤碼命名、UI 文案微調）自行決定並記錄；只有要改變**備份／還原的資料範圍、會刪除使用者資料的條件、或計畫第 10 節的安全規則**時才停下。這些是破壞性或跨端操作，每個 Phase 都要有對應測試，並在回報中寫明風險處理（計畫第 10 節）。
3. 備份滿 5 份時「自動刪除最舊一份」，確認頁事先告知。照做。

---

## 五、注意事項

**不可破壞**（`DEVELOPMENT.md`）
- 選取裝置只做 inspect，不自動寫入或開始 renew。
- 交易、journal、`operation.lock` 規則除「中斷即重新開始」（Phase 0）外不變：
  - 每次可能修改前，先持久化意圖。
  - 同一次執行內，結果不明保持未知，不自動重送、不接管、不自動移除；只有使用者按「重新開始」才從頭執行。
  - 取消要等實際程序返回。
- 完成判定不變：首次安裝需要 App 部署、配對匯入、同機支援與 activation receipt 都確認。到期日取自 `embedded.mobileprovision` 的 `ExpirationDate`，讀不到顯示「未取得」，不估算、不假設 7 天。
- `transaction-unknown`（沒有 journal）視為沒有進行中的交易；`complete`＋`confirmed` 不鎖任何頁面。
- 中斷規則以開發計畫 Phase 0 為準：USB 斷線即停止，只能從頭重新開始；重新開始前一律重新觀察手機狀態，且一定是使用者明確觸發，不自動重試。
- 純導覽入口（首頁、Mac 環境、返回裝置清單）在環境未就緒或操作鎖期間仍可使用。

**系統視窗引導**
- GoFly 不代替使用者點擊、安裝、接受條款或輸入密碼，也不顯示 Apple 帳號或密碼輸入框。
- 文案要明確區分「Mac 登入密碼」「iPhone 密碼」「Apple 帳號密碼」。
- 插圖是示意。系統視窗文字依 macOS／Xcode 版本可能不同，引導文字以按鈕名稱為主，避免依賴整句系統文案。

**專案規則**
- 不跑 Prettier。不提交憑證、簽署資料、配對檔或 `work/` 產出。
- 保留工作樹中其他未提交的修改。
- 規格有偏離或補充時，同一步驟內更新 `docs/MAC-UI-DESIGN.md` 新版章節與 `app/GoFlyMac/DEVELOPMENT.md`，直接改掉被取代的舊規則。
- 文件中區分「已實作」「離線測試已驗證」「待實機驗收」。
- 深色模式：使用 AppKit／SwiftUI 語意色自動適配，不寫死色碼；對照 Figma 05 頁右側「Dark · 」深色稿。

**範圍外**
- iOS App 的改動（另有 iOS 任務）、DMG 打包與 notarization、Figma 修改。
- 不連接或操作 iPhone；實機驗收由使用者最後集中執行。

---

## 六、每步驟的驗證

- 建置：`bash app/GoFlyMac/build-app.sh`；Swift 測試：`swift test --package-path app/GoFlyMac`；bridge 測試：依 `app/GoFlyMac/README.md` 用 `work/mac-setup-env/bin/python` 執行 `Bridge/Tests`、`Bridge/Setup/Tests`、`Bridge/Device/Tests`。全部要通過，失敗附輸出。
- 新增或更新 model 測試，涵蓋：
  - 步驟略過：已信任、已開啟開發者模式。
  - 鑰匙圈引導的出現時機。
  - 三個動作卡的啟用規則。
  - Wi‑Fi 連接時只有更新簽名可用。
  - 中斷後只提供「重新開始」。
  - 備份滿 5 份時的刪除提示。
  - 導覽在操作鎖期間可用。
- 在 1120 × 760 與 1000 × 700 下截圖（淺色＋深色），存到 `work/gofly-mac/redesign/step-N/`，對照 Figma 同名 frame。

## 七、回報格式（每步驟）

1. 改了哪些檔案；新增或刪除了哪些狀態、文案。
2. 建置與各測試結果。
3. 截圖路徑，以及與 Figma 的差異。
4. 已勾選與未完成的驗收條件；第四節事項的進度或提案。
5. 不宣稱實機行為已驗證。
