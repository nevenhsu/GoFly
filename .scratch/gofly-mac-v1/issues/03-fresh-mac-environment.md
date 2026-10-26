# 03 · 全新 Mac 環境檢查（bridge `environment`）

**Status:** todo
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

**Stop if:** 判斷 iOS 平台是否已安裝的方法需要執行會修改系統的命令。
