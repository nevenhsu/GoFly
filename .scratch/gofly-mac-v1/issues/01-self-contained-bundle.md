# 01 · App 自給自足（內建 Python、iOS 專案、原生函式庫）

**Status:** implemented; software-verified
**Blocked by:** —
**Spec:** `docs/MAC-INSTALLER-SPEC.md` §2–3；`.scratch/gofly-ios/decisions/F-dmg-architecture.md`「第一階段」。

**Evidence**
- 搬入 `PairingFileStore.swift`、`LocalGoSetupProtocol.swift`、`LocalGoSetupHandoff.swift` 至 `app/GoFly/Setup/`；`GOFLY_NATIVE_DIR` 可覆寫。授權文本與來源記錄移至 `app/GoFly/Legal/`；舊 `app/LocalGo/` 原始碼、重複 LICENSE／README 及舊設定測試已移除，修正所有存留授權連結。
- `build-app.sh` 固定 CPython 3.14.6 arm64 install_only archive 與 SHA-256，打包 Bridge、iOS 專案、Python 依賴及 arm64 FFI；bundle 不讀寫 JSON runtime 設定。`rsync` 靜態副本檢查 5,053 個檔案，確認排除 Tests、UITests、scripts 與 NativeBridge 建置 inputs；`lipo -archs work/gofly-ios/native/libidevice_ffi.a` 回報 `arm64`。
- runtime 路徑從 bundle Resources 推導；新狀態目錄是 `~/Library/Application Support/GoFly/state`，建置副本與 DerivedData 在同層 `GoFly/build/`。維護腳本的 source-tree 模式明確獨立，沒有 App bundle workspace fallback。舊 `GoFlySetup` 使用者狀態未讀寫。
- `NativeSources.json` 5 筆 SHA-256 全部匹配；`verify-native.py` 通過（native patch markers 與 30-declaration Swift shim 未變）。`bash app/GoFly/scripts/check.sh`：343 GoFly tests、13 native boundary scenarios、iOS Simulator build passed；未指定裝置。Python requirements 94 個 pins 與維護 runtime metadata 相符，`pip check` 無 broken requirements。
- CPython 官方 release asset 與 checksum 已核對：[20260610 expanded assets](https://github.com/astral-sh/python-build-standalone/releases/expanded_assets/20260610)。
- 本機完整產生 `work/dist/GoFly-1.0.0-arm64.dmg`（489 MB）；SHA-256 sidecar 與實際檔案吻合，`hdiutil verify` 通過。隔離 quarantine 安裝模擬把 App 安裝到暫存 Applications，從工作目錄外啟動 App，內建 CPython 3.14.6 回報 arm64，`cffi` 與 cryptography 原生模組可載入，`libidevice_ffi.a` 含 arm64，codesign 驗證通過；安裝器未觸碰 `/Applications` 或使用者資料。
- 最新離線驗證：GoFlyMac Swift 65 tests passed；Bridge 94 tests passed（2 skipped）。

**Not verified**
- 乾淨 Mac／另一個使用者帳號的正式下載流程待使用者驗收；本機 quarantine 模擬不等於下載來源信任驗收。
- 本票未連接或操作 iPhone；真機環境檢查及安裝／交接仍待裝置驗收。

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
