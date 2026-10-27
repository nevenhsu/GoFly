# 03 · 全新 Mac 環境檢查（bridge `environment`）

**Status:** implemented; software-verified
**Blocked by:** 01
**Spec:** MAC-INSTALLER-SPEC §4；Figma E01–E09。

**Scope**
- `environment` 依序回報：macOS 版本是否符合偵測到（或預定）Xcode 的最低需求、可用空間（需求約 40 GB，數字集中成常數）、Xcode 是否安裝、首次啟動與授權條款是否完成、iOS 平台是否已下載、Xcode 是否有 Apple 帳號、Teams 清單。每項有穩定 `id`，供 UI 決定跳到哪一步。
- 移除使用者可見的「命令列工具」「Python 環境」「App 資源」步驟。App 內建資源驗證失敗回傳單一 `bundle-damaged`，UI 只顯示「GoFly 無法啟動，請重新安裝」。
- 新增「是否第一次開啟 GoFly」的本機旗標（供 04 決定是否顯示 E01）。
- 只讀：不使用 sudo、不跑 `-runFirstLaunch`、不接受授權、不開下載。
- **E06 驗證任務**：在乾淨 Mac 不下載 iOS 平台，能否用 `xcodebuild` 建置並簽名實機版 GoFly。這需要使用者操作另一台 Mac：把驗證步驟寫在 `work/gofly-mac/v1/E06-VERIFY.md`，結果回來前 iOS 平台檢查照規格保留。

**Delete:** `python-runtime`、`project`、`developer-tools` 等使用者可見檢查與對應測試。直接 `git rm`／刪除，不留相容入口或舊副本；見 TRACKER「舊代碼與舊 UI：該刪就刪」。

**Acceptance**
- 每個檢查項目有離線測試（以假 Xcode 路徑、假 plist、假 `df` 結果模擬全新 Mac、只差 Apple 帳號、全部通過等情境）。
- 偵測不到時回「未知」而不是假通過。

**Evidence**
- `Bridge/bridge.py` 依序回報 macOS 版本、`/Applications` 磁碟可用空間（40 GiB）、Xcode 安裝、首次啟動／授權、iOS 平台、Apple 帳號；unknown 不會通過 readiness。平台檢查只讀 Xcode 目錄，沒有執行安裝命令。內建資源錯誤使用 `bundle-damaged`，Swift UI 只顯示指定通用文案。
- 首次開啟旗標存在 `UserDefaults`，只記錄於本機。
- 離線驗證：Bridge 18 項、Mac Swift 48 項全過；測試涵蓋完整通過、磁碟或 macOS 版本不足、觀察未知、Xcode 最低版本 plist、`df` 解析、授權只讀與 bundle 資源缺漏。
- E06 乾淨 Mac 驗證步驟：[`../../../work/gofly-mac/v1/E06-VERIFY.md`](../../../work/gofly-mac/v1/E06-VERIFY.md)。本票沒有新增環境頁 UI，因此沒有 App 截圖。

**Not verified**
- 尚未在乾淨 Mac 確認不下載 iOS 平台時是否能建置、簽名實機版；因此保留 E06 檢查。
- App Store 實際 Xcode 版本與下載容量尚未在乾淨 Mac 確認。未連接 iPhone；Personal Team 簽署／實機交接未驗證。

**Stop if:** 判斷 iOS 平台是否已安裝的方法需要執行會修改系統的命令。
