# 01 · App 自給自足（內建 Python、iOS 專案、原生函式庫）

**Status:** todo
**Blocked by:** —
**Spec:** `docs/MAC-INSTALLER-SPEC.md` §2–3；`.scratch/gofly-ios/decisions/F-dmg-architecture.md`「第一階段」。

**Scope**
- iOS 專案自給自足（純搬移，不改邏輯）：把 `app/LocalGo/StikDebug` 中 GoFly 編譯用到的 `PairingFileStore.swift`、`LocalGoSetupProtocol.swift`、`LocalGoSetupHandoff.swift` 搬進 `app/GoFly`；`GoFly.xcconfig` 的 `LIBRARY_SEARCH_PATHS` 改用可覆寫的 `GOFLY_NATIVE_DIR`。完成後 `app/GoFly` 的建置輸入不引用 `app/GoFly` 以外的路徑。
- `build-app.sh` 產出的 `GoFly.app/Contents/Resources` 包含 `Bridge/`、`Python/`（python-build-standalone arm64 install_only，固定版本並驗證 SHA-256，加上依 `requirements.txt` 安裝的固定版本套件）、`iOSProject/`（不含 Tests、UITests、scripts、Rust 建置腳本）、`native/libidevice_ffi.a`。
- 所有路徑從 `Bundle.main` 推導；刪除 `LocalConfiguration.json`、`SetupConfiguration.json` 與依賴工作目錄的檢查（`workspaceRoot`、`work/mac-setup-env`、`app/GoFly`）。
- 狀態放 `~/Library/Application Support/GoFly/state`（舊的 `GoFlySetup` 不讀、不刪、不搬）。每次建置前把 `iOSProject` 複製到 `~/Library/Application Support/GoFly/build/project`，DerivedData 放同目錄 `derived`。
- `DEVELOPER_DIR` 直接用偵測到的 Xcode.app（`/Applications/Xcode.app/Contents/Developer` 或使用者實際位置），不依賴 `xcode-select`。
- `scripts/install-ios-test.sh` 改用同一套 bundle 內設定，或明確記錄開發模式的差異。

**Delete:** 設定檔產生與工作目錄路徑檢查、`app/LocalGo/StikDebug` 搬走的檔案（`app/LocalGo/` 無其他用途時整個刪除，授權聲明移到 `app/GoFly/Legal/`）。直接 `git rm`／刪除，不留相容入口或舊副本；見 TRACKER「舊代碼與舊 UI：該刪就刪」。

**Acceptance**
- 把 App 複製到工作目錄以外（例如 `/tmp`）開啟，環境檢查可以完成；內建 Python 是 arm64；`git grep` 找不到 bundle 內對工作目錄絕對路徑的依賴。
- Swift 與 Python 離線測試通過；`app/GoFly/scripts/check.sh` 通過。

**Stop if:** 需要改原生 patch、FFI header 或重建 NativeBridge；python-build-standalone 下載來源或雜湊無法核對。
