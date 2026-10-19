# GoFly 精簡計劃（交付實作用）

日期：2026-10-19（Phase D 範圍同日由使用者定案）。依據：`main` @ `13dd897` 的實際原始碼盤點。本文件只是計劃，**撰寫者未改任何程式**。

## 0. 給實作者的規則（先讀）

1. **產品尚未發行**（沒有 DMG、沒有其他使用者）。不需要相容舊 protocol 版本、舊 journal、舊檔案格式。開發機上的舊 state 直接清掉重來即可。
2. **保留的使用者功能**（行為不能壞）：首次引導＋VPN 檢查、搜尋／座標／地圖選點瞬移、Start／Stop／Restore／Reset、地點最愛＋標籤、兩點／多點路線、來回、GPX 匯入／匯出、最愛路線、搖桿、自動漫步、設定（語言／外觀）、三語、Mac 首次 USB 安裝。
3. **不要動**：`app/GoFly/NativeBridge/*.patch`、`include/`、`build.sh` 的建置邏輯、`ServiceController` 的單一 FIFO＋`PointDispatchGate` 送點門檻（這是唯一真正防止重複送點的核心）、MapKit adapter。
4. 一個 Phase 一個 commit（或一個 PR），每個 Phase 結束都要跑第 7 節的驗收指令並全綠。
5. 刪除前先 `grep -rn <符號>` 確認沒有其他引用；刪檔同時移除 `GoFly.xcodeproj/project.pbxproj` 內對應的 file reference／build file。
6. 不要新增任何新的抽象層、protocol、journal、文件或「證據紀錄」。精簡的方向只有刪除與合併。
7. 不跑 Prettier。不新增 Figma 工作。

## 1. 現況規模（tracked files）

| 區域 | 正式碼 | 測試 |
| --- | ---: | ---: |
| iOS `GoFlyCore` | 15,300 | 16,239（Core 單元） |
| iOS `App` | 9,589 | 3,846（UI tests，完整跑約 35 分鐘） |
| Mac Python Bridge（Setup／Reinstall／Management／Backup／Device／root） | ~21,900 | ~5,840 |
| Mac Swift（Core＋App） | 6,880 | 1,943 |
| LocalGo 殘留（3 個 Swift 來源＋授權） | ~1,550 | 0 |
| 文件（.scratch、ARCHITECTURE、DEVELOPMENT、README×3…） | ~3,500 | — |

主要過度開發的來源：
- Mac 端有 **5 套獨立 bridge protocol**（1 唯讀、2 安裝、3 重裝、4 備份、5 管理），每套各自有 Python codec＋journal＋producer＋adapter，Swift 端又各自有 Protocol＋ProcessBridge＋Journal 讀取器＋Model。
- iOS 端有 **3 套 Mac→iOS 信箱**（Setup handoff、Transfer、Management），各自有 Types／Codec／Storage。
- iOS 有 **4 層恢復／背景機制**（SessionRecovery 冷啟動 hold、MovementRecovery、MovementContinuation、ContinuedProcessing BGTask）。
- 每個本機 JSON 存檔（最愛、匯入路線、最愛路線、session）各自實作 no-follow FD、quota、staging、undo、orphan cleanup。
- 測試行數 > 正式碼行數，大量是 race／timing／fault 排列組合。
- 開發流程（Advisor 多輪核准、雙軸審查、逐票記錄測試數／build 號／秒數）。

---

## Phase A：零風險刪除（不改行為）

| # | 動作 | 位置 | 說明 |
| --- | --- | --- | --- |
| A1 | 刪除未使用字體 | `app/GoFlyMac/Sources/GoFlyMac/Resources/NotoSansTC.ttf`、`NotoSansTC-OFL.txt` | Swift 沒有任何引用（README 自己寫「未使用字體資源」），卻因 `.process("Resources")` 被打包。同步刪 `docs/LICENSING.md` 三語的 Noto 列、`app/GoFlyMac/README.md:74` 的字體句子。 |
| A2 | 刪除開發日誌 | `app/GoFlyMac/Bridge/Setup/B1-HANDOFF.md` | 是 TDD RED/GREEN 過程紀錄，不是規格。 |
| A3 | 移除 protocol 1 的假 `install` action | `app/GoFlyMac/Bridge/bridge.py`（docstring 第 7 行起與 action 分派）、`Bridge/PROTOCOL.md`、`Sources/GoFlyMacCore/BridgeProtocol.swift`、`Bridge/Tests/test_bridge.py` | 永遠回 `read-only-mode`，純「前向相容」佔位。連同 `read-only-mode` 錯誤碼一起刪。 |
| A4 | 移除 Debug icon 預覽畫面 | `app/GoFly/App/GoFlyIconPreview.swift`、`UITests/GoFlyIconUITests.swift`、`-gofly-ui-icon-preview` 旗標 | 純元件檢視頁。 |
| A5 | 清掉 `__pycache__` | `app/GoFlyMac/Bridge/**/__pycache__` | 未 tracked，但確認 `.gitignore` 有 `__pycache__/`。 |
| A6 | 歸檔票單 | `.scratch/gofly-ios/issues/01–18-ticket.md`、`decisions/02–16*.md`、`decisions/09-gpx-research.md` | 全部已 Implementation complete。移到未 tracked 的 `work/gofly-ios/archive/`（或直接刪，git 歷史有）。依 Phase D 定案，`issues/M2-reinstall.md`、`issues/17-ticket.md`、`decisions/M2-reinstall.md`、`decisions/M2-wifi-lean-mvp.md` 也一併歸檔；`M3-*` 改寫成一段 setup `renew` 需求。只留 `M1-*`、`DEVICE-ACCEPTANCE.md`、`MAC-DEVICE-ACCEPTANCE.md`。 |
| A7 | 重寫 `TRACKER.md` | `.scratch/gofly-ios/TRACKER.md` | 刪除每票「Swift N、UI N／N（秒數）、build N、key 數、兩軸零 finding」段落。只留一張表：票號／狀態／手機驗收是否待做。≤30 行。 |
| A8 | 重寫 `ARCHITECTURE.md` | `app/GoFly/ARCHITECTURE.md`（252 行） | 改成「目前不變量」文件 ≤80 行：模組地圖、單一 FIFO＋dispatch gate、ACK 才更新位置、Stop→clear 順序、儲存位置。刪除所有「票 N 離線證據」「Advisor 核准」「不稱 N／N」「Figma 讀回」敘述。 |
| A9 | 重寫 `DEVELOPMENT.md` | `app/GoFlyMac/DEVELOPMENT.md`（119 行） | 只留需求與驗收表（自動續簽表格可保留）；刪除日期敘事、「本輪只更新 wireframe」等。 |
| A10 | README ×3 精簡 | `README.md`、`README.zh-Hant.md`、`README.zh-Hans.md` | 刪除開發狀態長段落與 LocalGo 歷史；保留需求表、建置指令、授權。三份同步。 |

---

## Phase B：測試與驗證流程精簡

### B1. UI tests：19 檔 → 5 檔煙霧測試

保留（每個主要 mode 一條 happy path）：
- `GoFlyOnboardingUITests`（首次流程）
- `GoFlySearchUITests`（搜尋＋瞬移 Go）
- `GoFlyRouteUITests`（兩點路線；把 Waypoint、RoundTrip 各併入 1 個 case）
- `GoFlyJoystickUITests`（把 Wander 併入 1 個 case）
- `GoFlySettingsUITests`（語言／外觀切換各 1 case）

刪除：`GoFlyFavoriteRoutesUITests`、`GoFlySettingsRetentionUITests`、`GoFlyRecoveryUITests`、`GoFlyWaypointUITests`、`GoFlyRoundTripUITests`、`GoFlyWanderUITests`、`GoFlyContinuationUITests`、`GoFlyIconUITests`、`GoFlyOperationUITests`、`GoFlySetupUITests`、`GoFlyImportedRoutesUITests`、`GoFlyFavoriteUITests`、`GoFlyServiceUITests`。（Favorite／GPX 各留 1 個 case 併到 Search／Route 檔即可。）

接著移除只服務已刪 UI test 的 Debug 旗標與其 App 內程式碼（每個先 grep 確認）：
`-gofly-ui-map-metrics`（31 處，地圖幾何量測）、`-gofly-ui-operation-metrics`、`-gofly-ui-preparation-delay`、`-gofly-ui-route-planning-delay`、`-gofly-ui-setup-delay`、`-gofly-ui-setup-fixture`、`-gofly-ui-unconfirmed-point`、`-gofly-ui-session-fixture`、`-gofly-ui-route-draft-count`、`-gofly-ui-preferences-store`。
保留：`-gofly-ui-session-store`／`favorites-store` 這類「隔離檔案 namespace」旗標若煙霧測試仍需要。目標是 App 內 `#if DEBUG` 區塊從 ~40 處降到 ≤8 處，`GoFlyUITestFixtures.swift` 只留 namespace 隔離。

### B2. Core 單元測試：16k 行 → 目標 ≤6k 行

原則：每個模組一個測試檔；只測公開行為的 happy path＋1–2 個關鍵失敗（例如「未 ACK 不更新位置」「Stop 後遲到 ACK 不復活」「損壞檔不覆寫」）。刪除 race 排列、逐一 fault injection 矩陣、檔案權限／symlink 矩陣、精確 timing。

| 動作 | 檔案 |
| --- | --- |
| 隨 Phase D 整檔刪（D-A／D-C／D-E 已定案） | `MovementContinuationControllerTests`(1175)、`MovementContinuationServiceTests`、`MovementContinuationExpiryTests`、`MovementContinuationSubmissionTests`、`MovementContinuationTestSupport`、`ContinuedProcessingTests`(612)、`TransferHoldCoverageTests`(591)、`TransferStoreHoldTests`、`TransferHoldTests`、`TransferMissingNamespaceTests`、`TransferCoreTests`、`TransferStorageTests`、`ManagementStorageTests`、`ManagementCodecTests`（D-E 另留 1 個 ≤100 行背景測試檔） |
| 合併 | `ServiceControllerTests`＋`PointServiceControllerTests`＋`ServiceRouteCommandsTests`＋`ServiceJoystickCommandsTests`＋`ServiceJoystickRecipeTests`＋`RouteServiceControlTests` → `ServiceControllerTests`（≤600 行） |
| 合併 | `RouteExecutionControllerTests`＋`RouteWaypointsTests`＋`RouteRoundTripTests`＋`ImportedRouteExecutionTests`＋`FavoriteRouteExecutionTests`＋`RouteRecoveryPreviewTests` → `RouteExecutionTests`（≤500 行） |
| 合併 | `JoystickMovementControllerTests`＋`JoystickWanderControllerTests`＋`JoystickControllerIntegrationTests`＋`WanderControllerIntegrationTests`＋`JoystickModelTests`＋`JoystickStepRecipeTests`＋`JoystickTargetGeometryTests`＋`WanderTargetSelectorTests` → `JoystickTests`（≤400 行） |
| 合併 | 三個 `*FilePersistenceTests`＋三個 `*StoreTests` → `PersistenceTests`（配合 Phase C3 的共用 store，≤300 行） |
| 大幅縮減 | `SetupCoreTests`(924 → ≤250)、`SessionRecoveryPersistenceTests`(618 → ≤150)、`MovementRecoveryControllerTests`(548 → ≤150)、`PreparedOperationTests`(348 → 隨 C5 刪或 ≤80)、`TunnelResetRecoveryTests`(390 → ≤120) |
| 刪除 | `ManualServiceWatchdog.swift`、`RouteTestClock.swift` 若合併後只剩一處使用就內聯 |

### B3. Python bridge 測試

隨 Phase C1 合併重寫：一個 `Bridge/Tests/test_bridge.py`（wire codec 共用測試）＋每個 action 一個檔（setup／renew…），每個 action 只測 preflight、apply 成功、中斷後 status、一個典型失敗。總量目標 ≤1,500 行（現 ~5,840）。刪除 `test_setup_usb_serial.py`、`test_setup_process_control.py` 這類單點 regression 檔，必要斷言併回 action 測試。

### B4. 驗證腳本

| 動作 | 位置 |
| --- | --- |
| `check.sh` 預設只做：`swift test`＋simulator build；`iphoneos` build 與 native rebuild 改成 `check.sh --device` 才跑 | `app/GoFly/scripts/check.sh` |
| `verify-native.py`＋`NativeBridge/verify-shim.py` 合併成一個 ≤60 行檢查（patch 已套用、shim 宣告數符合），刪除 hash 證據比對 | `app/GoFly/scripts/`、`NativeBridge/` |
| 刪除 `NativeBridge/tests/`（`check-error-mapping.sh`、`NativeErrorMappingCheck.swift`、`NativeSessionLifetimeCheck.swift`、`timeout-stub.c`）；error mapping 斷言若需要改放 Core 單元測試 1 個 case | `app/GoFly/NativeBridge/tests/` |
| 隨 Phase D 刪除 `test-transfer-validator.py` 與 `Sources/GoFlyTransferValidator` | |

---

## Phase C：結構合併（行為不變，大幅減碼）

### C1. Mac：5 套 bridge → 1 個入口、1 套 wire、1 套 journal

現況每套都有 `*_protocol.py`（strict JSON、大小上限、錯誤碼）、`*_journal.py`（0600 atomic replace＋fsync＋`operation.lock`）、`*_bridge.py`（一次性 stdin/stdout）、`*_config.py`。

目標結構：
```
Bridge/
  bridge.py          # 唯一入口：讀 {action, requestID, ...}，分派
  wire.py            # 共用：嚴格 JSON 解碼、32KiB/256KiB 上限、錯誤 envelope、錯誤碼表
  state.py           # 共用：state root、operation.lock、atomic JSON write（一個實作）
  device.py          # 由 Device/gofly_device.py 移入
  setup.py           # 首次安裝（原 Setup/*：producer+adapters+support 合併、刪 seam 層）
  renew.py           # 續簽（D-C：setup 的 renew 模式，可直接放在 setup.py）
  Tests/
```
- 不再有 `protocol` 號碼 1／2／3／4／5；只有 `action`。
- journal 統一一種格式：`{operation, id, deviceID, stages: {name: state}}`，每個 operation 一份檔。刪除 `setup_delivery.py`（一次性 pairing 遞送 ledger）併入 setup stage。
- 刪除 `Backup/catalog.py` 用 `object.__new__` 借用 M2 adapter 的 hack（隨 Phase D）。
- 刪除 `Management/management_lineage.py`（Mac 端重新驗證 iOS 的 M2/M3 檔案 lineage，682 行）——Mac 不需要再當 iOS 資料的第二個驗證者。
- `setup_adapters.py`（2,253 行）中「Protocol seam＋production adapter＋value types」三層：刪 seam protocol，測試直接 monkeypatch production adapter 的少數函式。

Swift 端對應：
- `BridgeProtocol.swift`／`SetupProtocol.swift`／`ReinstallProtocol.swift`／`MacBackupProtocol.swift`／`MacManagementProtocol.swift`(883) → 一個 `BridgeWire.swift`（通用 `Codable` request/response envelope＋各 action 的小型 payload struct）。
- `ProcessBridge`／`SetupProcessBridge`／`ReinstallProcessBridge`／`BackupProcessBridge`／`ManagementProcessBridge` → 一個 `ProcessBridge`。
- **刪除 Swift 直接讀 Python journal 的程式**：`ManagementJournal.swift`(462)、`ReinstallJournal.swift`、`SetupJournal.swift`、`SetupWireJSON.swift`。改成呼叫 bridge `status` action 取得續行狀態。
- `MacManagementContinuation` 的 `selectionID`／`connectionRevision`／`initialTransport`／`currentTransport` 刪除（lean Wi-Fi 方案已決定不做這些域）。
- Mac Swift 測試相應合併：`Mac*ProtocolTests`→`BridgeWireTests`；`Mac*JournalTests` 刪除；Model tests 每個 ≤100 行。

預期：Python ~21.9k → ~7k；Mac Swift ~6.9k → ~3.5k。

### C2. iOS：3 套 Mac→iOS 信箱 → 1 套

現況：`SetupTypes/SetupCodec/SetupStorage/SetupBootstrap`、`TransferTypes/TransferCodec/TransferStorage(1,801)/TransferArchiveCodec/TransferFileIO/TransferPackageValidator/TransferHold`、`ManagementTypes/ManagementCodec/ManagementStorage(1,455)`；App 端 `GoFlySetupBootstrap`(759)、`GoFlyTransferCoordinator`(553)、`GoFlyManagementCoordinator`(315)、`GoFlySetupPaths`。

目標：
- 一個 `MacInbox`（GoFlyCore）：固定目錄、讀一個 `request.json`（`{kind, id, payload}`）、寫一個 `response.json`；共用 no-follow 讀取與權限收緊。
- App 端一個 `GoFlyMacInboxCoordinator`，依 `kind` 分派到 setup／renew（renew 只需重送配對檔，不需另一套信箱）。
- `GoFlySetupBootstrap` 啟動時對 executable 做最大 256MiB 的 SHA256 雜湊、profile 雜湊——刪除；Bundle 身分只比對 bundleID＋build 字串。
- 刪除「正式 pointer 不存在時退回舊 `Documents/DDI`」的雙路徑（`Device/ProvisionedSupport.swift`、`NativeDeviceService.swift`）：只留正式 pointer 一條路。

### C3. iOS：本機 JSON 存檔共用一個實作

現況：`FileFavoritePlacesPersistence`、`FileImportedRoutesPersistence`、`FileFavoriteRoutesPersistence`、`SessionRecoveryPersistence`、`SecureArchiveDirectory`、`TransferFileIO` 各自做 no-follow FD、0700/0600、staging＋fsync＋rename、quota、orphan cleanup、delete-undo。

目標：
- 一個 `AtomicJSONFile<T: Codable>`（≤120 行）：`Data.write(options: .atomic)`＋`completeUntilFirstUserAuthentication` 保護；讀取有大小上限；解碼失敗 → 回報 corrupted、不覆寫。
- 匯入路線／最愛路線：manifest＋immutable payload 結構改成「一個 JSON 檔含全部紀錄」或「一筆一檔＋一個索引」，二選一，取最簡單的。刪除 64MiB quota 會計、orphan cleanup、delete-undo token（UI 上的 undo 若要保留，就用記憶體中的上一份陣列）。
- 筆數上限、字串長度上限保留在 domain 驗證（一處）。

### C4. iOS：恢復／背景層合併

- `MovementTaskAuthority`（lease／snapshot 版本比較）併入 `ServiceController` 的 FIFO 內部狀態；對外只保留 `PointDispatchGate`。
- `SessionRecovery*`（Models＋Codec 435＋Store＋Persistence＋App `GoFlySessionRecovery`）只保留「保存草稿與設定，下次開啟還原草稿」。刪除冷啟動 hold（「必須實際 clear ACK 後才可建立新任務」）——改成：冷啟動若上次有 active 任務，Start 前自動排一次 clear，失敗就顯示錯誤，不做持久化的不確定狀態機。
- `MovementRecoveryController`（584）與 `TunnelResetState` 合併為一個前景連線檢查＋Reset 的小 controller。
- 背景（`ContinuedProcessing*`、`MovementContinuation*`、`GoFlyContinuedProcessingDriver` 422、`GoFlyContinuationView`）：照 D-E 縮成最小 driver。

### C5. iOS：小型過度設計

| 項目 | 建議 |
| --- | --- |
| `PreparedOperation`（一個 watchdog round 內自動重試三次，票 04） | 改為一次嘗試＋使用者手動重試；刪 `PreparedOperationSnapshot` 的 attempts 記帳 |
| `ContinuedProcessingRegistrationBook`（固定 256 次註冊嘗試） | 隨 D-E 刪除，改為啟動時註冊一次 |
| 漫步「最近 100 個成功目的地 1m 內排除」「32 方向樣本」 | 改為隨機方向＋固定距離，刪排除記憶 |
| 路線 50m 端點吸附＋10,000 點驗證、admission revision | 保留上限檢查，刪除 admission revision（新規劃直接取消舊 Task 即可） |
| `RouteExecutionController` 轉發 picker candidates 的 objectWillChange 訂閱 | 改由 View 直接觀察 picker 的 `CandidateController` |
| `GoFlyMapView`（988）＋`GoFlyMapCanvas`：實測面板高度防震盪、短 viewport 精簡模式 | 刪除「依保留實測高度判斷精簡」邏輯，固定 padding；隨 B1 刪除 map-metrics 量測 |

---

## Phase D：範圍決策（**已定案，2026-10-19**）

使用者已核准，照下表「建議」欄執行。實作者不要再重新討論這幾項的範圍：

- **D-A 刪除**：M2 重裝＋iOS 匯出／還原整塊移除，包含 `GoFlyTransferValidator`。
- **D-B 刪除**：M3 本機備份管理整塊移除。
- **D-C 改寫**：刪除 protocol 5 管理（Mac `Management/`、Swift Management 系列、iOS `Management*` 信箱），續簽改成 setup 的 `renew` 模式。
- **D-D 不做**：Wi-Fi 續傳（包括 lean MVP）不實作，刪除相關決策文件與規格段落。
- **D-E 保留最小版**：背景持續執行改成 ≤150 行的 driver（細節見下表）。
- **D-F 保留三語**：en／zh-Hant／zh-Hans 全部保留。
- **D-G 保留但精簡**：照下表。

各項範圍與理由：

| 代號 | 功能 | 涉及程式（約略行數） | 決定 | 理由 |
| --- | --- | --- | --- | --- |
| D-A | M2 USB 同機重裝＋iOS 匯出／還原 | iOS `Transfer*`(~2.9k)＋`GoFlyTransferCoordinator`＋`GoFlyTransferLockView`；Mac `Reinstall/`(~6.6k)＋`ReinstallProtocol/ProcessBridge/Journal/Model`＋`MacReinstallPage`；`GoFlyTransferValidator`；相關測試 ~4k | **刪除（已定案）** | 同 Bundle ID＋同 Team 重新簽名／覆蓋安裝本來就保留 App 資料；只有換 Team 才需要匯出還原，單人研究專案用不到。 |
| D-B | M3 本機備份管理（7 天保留、刪除意圖續做） | Mac `Backup/`(~2k)＋`MacBackupProtocol/Model/ProcessBridge`＋`MacBackupsPage` | **刪除（已定案）** | 只服務 D-A 的備份。 |
| D-C | M3 續簽＋配對修復（protocol 5） | Mac `Management/`(~9.4k)＋Swift Management 系列(~1.8k)；iOS `Management*`(~2.1k)＋`GoFlyManagementCoordinator` | **改寫成 setup 的 `renew` 模式（已定案）** | 續簽 = 用同 Bundle 重新簽名後覆蓋安裝＋重送配對檔，等同 setup 的 artifact→install→pairing 子集。刪掉 lineage、evidence inventory、submission ledger、iOS 管理信箱。目標 ≤600 行 Python。 |
| D-D | Wi-Fi 續傳（含 lean MVP） | 尚未實作 | **不做（已定案）** | D-A 刪除後沒有可續傳的對象；續簽走 Wi-Fi 只需 `device.py` 支援 Network transport（已有）。刪除 `decisions/M2-wifi-lean-mvp.md` 與 `DEVELOPMENT.md` 的 Wi-Fi 重裝段。 |
| D-E | 背景持續執行（BGContinuedProcessingTask） | Core `ContinuedProcessing*`、`MovementContinuation*`(~1.1k)；App driver 422＋view；測試 ~2.7k | **保留最小版（已定案）** | 保留一個 ≤150 行 driver：進背景時若有運行中的路線／漫步任務就 submit 一個 task、expiry 時暫停任務；啟動時註冊一次。刪除 grant／scene 原子 authority、`ContinuedProcessingRegistrationBook`（256 次註冊）、`MovementContinuation*` 協調層、`GoFlyContinuationView`。測試只留 1 檔 ≤100 行（submit／expiry 暫停／前景不自動恢復）。 |
| D-F | 簡體中文 | `zh-Hans.lproj`、`README.zh-Hans.md` | **保留（已定案）** | 三語全部保留；新增字串仍需三份同步。 |
| D-G | Mac 首次安裝的「Mac 端準備 DDI／Cryptex 支援檔」 | `Setup/setup_support.py`(977) | **保留但精簡（已定案）** | 刪除私有 closed inventory 複製與 generation 管理；改為直接用 pymobiledevice3 的 mounter 自動處理。 |

依上述決定執行，預估再減 ~25k 行（含測試）。

---

## Phase E：開發流程精簡（文件／規則）

目前的流程本身造成大量文件與測試膨脹：

| 現行流程 | 改為 |
| --- | --- |
| 每票 Advisor 多輪 PLAN_APPROVED、Root v5、API freeze 文件 | 刪除。小功能直接做；大改動寫 ≤1 頁 decision。 |
| Standards／Spec「雙軸審查零 finding」 | 刪除，改為一般 code review。 |
| 逐票記錄 Swift 測試數、UI N／N、秒數、build 號、key 數、hash 封存 | 刪除。CI／`check.sh` 綠燈即是紀錄。 |
| 「不得稱 30／30」「test-only 修正後單項重驗」等措辭規則 | 刪除。測試失敗就修好重跑。 |
| 每個 Core 型別都有 test-double seam 與「不製造 ACK」的長註解 | 註解只留不明顯的不變量，一行為原則。 |
| `DEVICE-ACCEPTANCE.md`(225 行) | 保留，但壓成一張勾選表（≤60 行），刪除已不存在功能（D-A／D-B／D-D）。 |

`AGENTS.md` 的「設計變更要同步更新規格」規則屬使用者規則，保留；但規格文件經 Phase A 縮減後同步成本會小很多。

---

## 6. 建議執行順序

1. Phase A（半天）→ commit
2. Phase B1、B4（UI tests、腳本）→ commit
3. Phase D（已定案）：先刪 D-A、D-B 與 D-D 文件 → commit；再把 D-C 改成 setup `renew` → commit（這樣 C1／C2 會變簡單很多）
4. Phase C1（Mac bridge 合併）→ commit
5. Phase C2、C3（iOS 信箱、存檔）→ commit
6. Phase C4、C5 → commit
7. Phase B2、B3（依新結構重寫／合併測試）→ commit
8. Phase E 文件收尾 → commit

## 7. 每個 Phase 的驗收

```bash
bash app/GoFly/scripts/check.sh
```
```bash
swift test --package-path app/GoFlyMac
```
```bash
python3 -m unittest discover -s app/GoFlyMac/Bridge -p 'test_*.py'
```
UI 煙霧測試（Phase B1 後）：`xcodebuild test -scheme GoFly -destination 'platform=iOS Simulator,name=iPhone 17'`，目標 < 5 分鐘。

完成定義：
- 上述全綠；第 0 節列出的保留功能在模擬器手動點過一次。
- 不新增任何檔案到 `.scratch`（除了更新本計劃的勾選狀態）。
- 實機驗收仍由使用者最後集中進行，不在本計劃範圍。

## 8. 目標規模

| 區域 | 現況 | 目標（D 已定案） |
| --- | ---: | ---: |
| iOS Core＋App | ~24.9k | ~13k |
| iOS 測試（Core＋UI） | ~20k | ~6k |
| Mac Python | ~21.9k＋5.8k 測試 | ~4k＋1.5k 測試 |
| Mac Swift | ~6.9k＋1.9k 測試 | ~3k＋0.6k 測試 |
| 文件 | ~3.5k | ~0.8k |
| **合計** | **~85k** | **~29k** |
