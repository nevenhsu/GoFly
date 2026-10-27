# 02 · 依 Team 產生 Bundle ID

**Status:** implemented; software-verified
**Blocked by:** 01
**Spec:** F-dmg-architecture「Bundle ID」與第一階段第 4 點。

**Scope**
- Bundle ID 一律 `com.neven.gofly.<teamid 小寫>`，原作者也一樣。建置時傳入 `PRODUCT_BUNDLE_IDENTIFIER`；iOS 與 Mac 端不准再寫死 `com.neven.gofly`。
- 實作前以 `git grep -n "com\.neven\.gofly"` 重新盤點。已知位置：iOS `GoFly.xcconfig`、`GoFly-Info.plist`（背景任務 ID）、`GoFlyContinuedProcessingDriver.swift`（背景任務改成 `<Bundle ID>.movement`）、`SetupTypes.swift`（`formalBundleID`）、`project.pbxproj`（UI test target）；Mac `bridge.py`、`setup_protocol.py`、`setup_producer.py`、`BridgeWire.swift`、`ProcessBridge.swift`、`build-app.sh`；`scripts/install-ios-test.py`。DispatchQueue 標籤與 `os.Logger` subsystem 可不改。
- 測試與 fixture 跟著改。

**Delete:** 功能用途的寫死 `com.neven.gofly`。直接 `git rm`／刪除，不留相容入口或舊副本；見 TRACKER「舊代碼與舊 UI：該刪就刪」。

**Acceptance**
- 不同 Team 產生不同 Bundle ID；背景任務 ID 與 Info.plist 一致；交接與 readback 使用實際 Bundle ID。
- 離線測試通過。文件註明：舊 `com.neven.gofly` 會變成另一個 App，資料不會自動帶過去。

**Stop if:** 免費 Personal Team 無法簽署 GoFly 用到的 capability（記錄錯誤，交使用者決定）。

**Evidence**
- Team ID 嚴格產生 `com.neven.gofly.<teamid 小寫>`；Mac UI、Bridge、Xcode build、iOS manifest／handoff／readback 與 maintainer installer 共用相同的 Team scoped ID。不同 Team 的 ID 不同；舊 `com.neven.gofly` 不接受為正式 Bundle ID。
- 背景任務 identifier 從實際 `Bundle.main.bundleIdentifier` 加上 `.movement` 產生；Info.plist 以 `$(PRODUCT_BUNDLE_IDENTIFIER).movement` 展開。`bash app/GoFly/scripts/check.sh` 通過：Swift 套件 343 tests、13 native boundary cases、iOS simulator build，以及 Info.plist identifier 比對。
- Mac Swift 47 tests、Bridge Python 13 tests、Setup Python 52 tests 通過。Shell syntax、Python AST parse 與 `git diff --check` 通過。
- 更新 `docs/MAC-INSTALLER-SPEC.md` 與 `docs/AI-INSTALL.md`：舊 `com.neven.gofly` 會成為另一個 App，資料不會自動移轉。刪除功能用途的舊 Bundle ID fallback；`DispatchQueue` label 與 `os.Logger` subsystem 保留為非 Bundle ID 用途。

**Not verified**
- 尚未以 Xcode Personal Team 執行簽署，故免費 Personal Team 的 capability 簽署結果、實機安裝與交接未驗證。依本任務限制未連接 iPhone。
- Ticket 01 所述官方 Python archive 不在本機快取；未執行完整封裝 app build／launch。
