# Phase F：DMG 發行架構

狀態：**已定案，尚未實作**（2026-10-19 記錄）。**排在 iOS 手機功能驗收之後**才開始；驗收期間的 bug 修正和 UI 調整優先。本文件不改程式碼。

## 目標

別人下載 DMG，執行一行安裝指令後就能打開 Mac GoFly，再用**自己的** Xcode 帳號和 Team，把 GoFly 裝到**自己的** iPhone。原作者的帳號不參與別人的簽名。

## 已定案的設計

| 項目 | 決定 |
| --- | --- |
| iOS App 來源 | DMG **不附已簽名的 iOS App**。Mac App 內附 iOS 專案原始碼，由使用者在自己的 Mac 上用 `xcodebuild` 建置，並用自己的 Team 自動簽名後裝到手機。 |
| 原生函式庫 | `libidevice_ffi.a` 由發行者預先編譯並放進 Mac App。使用者的 Mac 不需要 Rust；建置時直接連結，跟著 App 一起由使用者的 Team 簽名。 |
| Bundle ID | 一律是 `com.neven.gofly.<teamid 小寫>`，原作者也一樣，不准有特例。免費個人帳號在 Xcode 也有自己的 Personal Team ID，同樣適用。不使用帳號名稱：會撞名、可能含非英數字、會公開個人資訊，改名後還會變成另一個 App。 |
| Python | 可攜式 CPython runtime 和固定版本的 pymobiledevice3 打包在 App 內。使用者的環境引導中沒有 Python 步驟。 |
| Mac 架構 | 只支援 Apple Silicon（arm64）。Intel 之後有需要再評估。 |
| Mac App 簽名 | 不使用付費的 Developer ID 和 notarization。整個 App（含內建 Python 和所有 `.so`／dylib）做 ad-hoc 深度簽名。 |
| 開啟方式 | DMG 內附 `install.sh`。使用者在「終端機」輸入 `bash /Volumes/GoFly/install.sh`，腳本會把 App 複製到 `/Applications`、執行 `xattr -dr com.apple.quarantine`，再開啟 App。用 `bash` 執行可以避免腳本本身被 Gatekeeper 擋下；雙擊 `.command` 會被擋。 |
| 開發版與發行版 | `build-app.sh` 的產物就是 DMG 的內容，不再有只能在開發目錄執行的版本。 |

## 使用者需求（寫進三語 README）

- 完整的 Xcode，包括 iOS 平台元件。只裝命令列工具不夠：建置需要 iOS SDK，免費自動簽名需要在 Xcode 登入 Apple 帳號。
- 在 Xcode → Settings → Apple Accounts 登入 Apple 帳號；免費帳號可以用。GoFly 不會、也不應該經手 Apple ID 密碼。
- iPhone：iOS 26 以上、開啟開發者模式、信任這台 Mac，並從 App Store 安裝 LocalDevVPN。
- 免費帳號的限制：簽名 7 天要續一次；每台裝置最多 3 個用免費帳號簽名的 App；7 天內能新註冊的 App ID 有數量上限。
- `install.sh` 會讓 GoFly 跳過 Gatekeeper 檢查。README 要附上 DMG 的 SHA-256，請使用者執行前先核對。

## 實作階段

### 第一階段：Mac App 自給自足

已完成的前置工作（commit `a6d7ecc`）：刪除介面預覽模式、bundle 檔案雜湊清單（`MacBundleResources`），以及「選擇已簽署的 GoFly.app」安裝來源。

待做：
1. **iOS 專案自給自足**（純搬移，不改邏輯）：把 `app/LocalGo/StikDebug` 底下 GoFly 編譯用到的 3 個檔案（`PairingFileStore.swift`、`LocalGoSetupProtocol.swift`、`LocalGoSetupHandoff.swift`）搬進 `app/GoFly`；`GoFly.xcconfig` 的 `LIBRARY_SEARCH_PATHS` 改用可覆寫的 `GOFLY_NATIVE_DIR`（目前寫死成 `work/gofly-ios/native`）。完成後，`app/GoFly` 的建置輸入不再引用 `app/GoFly` 以外的路徑。
2. **App bundle 佈局**：`Contents/Resources` 包含：
   - `Bridge/`
   - `Python/`：python-build-standalone 的 arm64 install_only 版本，固定版本並驗證 SHA-256；加上依 `requirements.txt` 安裝的固定版本套件。
   - `iOSProject/`：不含 Tests、UITests、scripts 和 Rust 建置腳本。
   - `native/libidevice_ffi.a`
3. **路徑從 `Bundle.main` 推導**：刪除 `LocalConfiguration.json`、`SetupConfiguration.json`，以及依賴工作目錄的驗證（`workspaceRoot`、`work/mac-setup-env`、`app/GoFly`）。
   - 狀態：`~/Library/Application Support/GoFly/state`（舊的 `GoFlySetup` 目錄不讀、不刪、不搬）。
   - 建置：每次建置前，把 `iOSProject` 複製到 `~/Library/Application Support/GoFly/build/project`；DerivedData 放在同目錄的 `derived`。
   - `DEVELOPER_DIR`：取自 `xcode-select -p`。
4. **依 Team 產生 Bundle ID**：建置時傳入 `PRODUCT_BUNDLE_IDENTIFIER`。iOS 端和 Mac 端不准再寫死 `com.neven.gofly`。2026-10-19 盤點的位置：
   - iOS：`GoFly.xcconfig`、`GoFly-Info.plist`（背景任務 ID）、`GoFlyContinuedProcessingDriver.swift`（背景任務 ID 要改成 `<Bundle ID>.movement`）、`SetupTypes.swift`（`formalBundleID`）、`project.pbxproj`（UI test target）。另外，`NativeDeviceService.swift` 和 `NetworkTunnelProbe.swift` 只是 DispatchQueue 的標籤，不影響功能，可以不改。
   - Mac：`bridge.py`（`DEFAULT_BUNDLE_ID`）、`setup_protocol.py`（`TARGET_BUNDLE_ID`）、`setup_producer.py`（產物驗證）、`BridgeWire.swift`、`ProcessBridge.swift`、`build-app.sh`。
   - 測試與 fixture 跟著改。
   - 實作前要用 `git grep -n "com\.neven\.gofly"` 重新盤點一次。
5. **驗收**：把 App 複製到工作目錄以外（例如 `/tmp`）開啟，首頁要顯示「Mac 環境已就緒」；內建 Python 必須是 arm64。

### 第二階段：新架構的手機驗收

用第一階段的 App，在原作者的 iPhone 上以新的 Bundle ID 做**首次安裝**，再跑一次功能清單、延長簽名期限、更新（資料保留）。

舊的 `com.neven.gofly` 會變成另一個 App，資料不會自動帶過去，確認後可以手動刪除。

### 第三階段：DMG 與文件

1. `make-dmg.sh`：執行 `build-app.sh`，ad-hoc 深度簽名（`codesign --force --deep -s -`），用 `codesign --verify --deep --strict` 檢查，產生 `work/dist/GoFly-<版本>-arm64.dmg` 並輸出 SHA-256。DMG 和建置產物不進版本控制。
2. `install.sh`：照上表的開啟方式實作。只能動 `/Applications/GoFly.app`；目標已存在時，先詢問再覆蓋。不使用 sudo，也不修改系統的 Gatekeeper 設定。
3. 隔離屬性實測：給 App 加上 `com.apple.quarantine`，模擬從網路下載，再實際執行 `install.sh`，確認 App、內建 Python 和原生擴充模組都能執行。最後要在另一個 macOS 使用者帳號或另一台 Mac 上實際下載測試；這部分由使用者執行。
4. 文件：三語 README 改寫成以 DMG 為主的安裝說明；`docs/LICENSING.md` 逐項列出 DMG 內附元件的授權（idevice、LocalGo 衍生程式碼、Python、pymobiledevice3 及其依賴）和原始碼取得方式；同步更新 `docs/AI-INSTALL.md`。

## 尚未驗證

- Commit `b23d557`～`70cfbb6`（Mac UI 精簡、環境引導、首次安裝流程、裝置管理）都還沒經過實際安裝驗收。
- 免費 Personal Team 是否支援 GoFly 用到的所有 capability（背景任務等），要在第二階段實測確認。
- `install.sh` 移除隔離屬性後，ad-hoc 簽名的內建 Python 和 `.so` 能不能在乾淨的 Mac 上執行，要在第三階段實測確認。
