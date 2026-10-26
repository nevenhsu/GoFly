# 任務：GoFly for Mac V1 重構（照票實作，UI 照 Figma）

你在 repo `/Users/neven/Documents/projects/ianygo` 工作，對象是 macOS App `app/GoFlyMac`（SwiftUI，macOS 15+，Swift 6；後端是 Python bridge `app/GoFlyMac/Bridge/`），以及它建置並安裝到 iPhone 的 `app/GoFly`。

目標：網友下載 DMG、照 App 畫面在全新的 Mac 上裝好 Xcode 並登入自己的 Apple 帳號，用 USB 把 GoFly 裝到自己的 iPhone；之後 Mac App 開著時，簽名剩不到 4 天會自動用 USB 或 Wi‑Fi 延長。

## 先讀（全部讀完再動工）

1. `AGENTS.md`（專案規則；「iOS 實機測試安裝」已改成中斷不接續）。
2. `docs/MAC-INSTALLER-SPEC.md`：**唯一的流程與驗收規格**。與其他文件衝突時以它為準。
3. `.scratch/gofly-mac-v1/TRACKER.md` 與 `issues/01`–`12`：票、依賴與每票驗收條件。
4. `.scratch/gofly-mac-v1/FIGMA-NODES.md`：Figma 節點 ID 與共用版面數值。
5. `.scratch/gofly-ios/decisions/F-dmg-architecture.md`：DMG／bundle 架構定案。
6. `app/GoFlyMac/DEVELOPMENT.md`、`Bridge/PROTOCOL.md`、`app/GoFly/ARCHITECTURE.md`：現有交易、完成判定、到期日與 iOS 不變量（接續相關規則已被 spec 取代，見票 08）。

**不要參考**：`.scratch/prompts/03-mac-redesign.md`、`work/gofly-planning/MAC-RESET-BACKUP-PLAN.md`、Figma 頁面 `02 · Mac App`，以及 `05` 頁右側 `Archive ·` 開頭的 section。第一版不做備份、還原、重置。

## UI 一律照 Figma

- 檔案 `RtPV8PXCQJ2WXK3jk3kPrq`，頁面 `05 · Mac Redesign（新版）`（`123:61504`），只看 `V1 · E Mac 環境（全新 Mac）`、`V1 · D 裝置` 與對應的 `Dark ·` section。
- 實作每個畫面前，用 Figma Console MCP（需要 Figma Desktop 開著 Desktop Bridge plugin）截圖該節點的淺色與深色版本，並讀畫面下方的灰字說明；版面、文案、間距、按鈕位置、狀態顏色照圖做。畫面下方說明是行為規則。
- 無法連到 Figma 時停下，請使用者開啟 Figma Desktop 與 Desktop Bridge plugin；不要憑記憶或舊頁面猜。
- 完成每個畫面後，把 App 截圖存到 `work/gofly-mac/v1/screens/<畫面編號>-light.png`／`-dark.png`，與 Figma 並排檢查差異，修正到一致。Figma 有而規格沒寫的細節照 Figma；規格與 Figma 衝突時停下回報。
- 品牌圖示用 `00 · 品牌與基礎元件` › `Logo masters`（`13:1693`），E00 版面對齊 iOS `R01 · 啟動畫面 / Logo`（`121:51102`）。系統視窗示意圖用 SwiftUI 繪製。
- 使用 macOS 系統字體與 AppKit 語意色、SF Symbols；支援深淺色、鍵盤焦點、1000 × 700 可捲動。三語字串（en／zh-Hant／zh-Hans）。

## 做法

- 依 TRACKER 順序逐票做：01 → 02 → 03 → 04 → 05 → 06 → 07 → 08 → 09 → 10 → 11 → 12。只有依賴完成的票才開始；05 和 06 可交錯。
- 每票完成：跑相關離線測試（Mac：`swift test`；bridge：`python -m unittest`；iOS：`bash app/GoFly/scripts/check.sh`），更新該票的 **Status／Evidence／Not verified**，更新 TRACKER 表格。狀態用 `implemented; software-verified`、`implemented; static-design-verified` 等，沒有證據就不寫已驗。
- 規格沒寫到的小決定（命名、檔案拆分、輪詢間隔細節、文案微調）自行決定，寫進 `work/gofly-mac/v1/DECISIONS.md` 後繼續，不要停。
- **舊代碼與舊 UI 該刪就刪**：照 TRACKER「舊代碼與舊 UI：該刪就刪」的表格與各票 **Delete** 欄，直接 `git rm`，不保留相容入口、隱藏開關、註解掉的程式或舊副本；刪除後無引用的型別、字串、資源、測試一起刪，並記在票單 Evidence。使用者資料（手機上的 App／配對／偏好、Mac 上舊的 `GoFlySetup` 狀態目錄）不讀、不刪、不搬。

## 何時停下（只有這些情況）

1. 需要使用者在手機或 Mac 上操作：安裝 Xcode／App、拔插 USB、輸入任何密碼、在系統視窗點按、用乾淨 Mac 測試（例如票 03 的 E06 驗證、票 11 的下載測試）。把步驟寫清楚，**這一項暫停，改做下一個不依賴它的票**。
2. 會違反 `app/GoFly/ARCHITECTURE.md`「命令與送點」或完成判定（部署、本次配對匯入、同機支援、activation receipt 全部確認才算完成）。
3. 需要改原生 patch、FFI header 或重建 NativeBridge。
4. 會刪除手機上已啟用的配對、App 或使用者資料。
5. 需要憑證、簽署身分、Apple 帳號、付費服務，或要 commit、push。
6. 規格與 Figma 互相衝突。

## 安全規則

- 不在聊天、日誌或版本控制中留下配對檔、憑證、簽署資料或 Apple 帳號資訊；`work/` 已被 gitignore。
- 不使用 sudo、不改系統 Gatekeeper、不代替使用者執行 `xcodebuild -runFirstLaunch` 或接受授權。
- 不連接或寫入實體 iPhone，除非使用者在對話中明確授權該次操作；實機驗收項目寫進 `.scratch/gofly-ios/MAC-DEVICE-ACCEPTANCE.md`。
- 不執行 Prettier。不 commit、不 push。

## 回報

全部做完（或只剩需要使用者操作的項目）時，回報：每票狀態與證據、截圖位置、`DECISIONS.md` 摘要、待使用者操作的步驟、未驗證事項。
