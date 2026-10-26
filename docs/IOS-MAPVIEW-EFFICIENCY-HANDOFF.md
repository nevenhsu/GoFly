# iOS 地圖畫面效能與解耦 Handoff（2026-10-26）

給接手的 agent。分支 `route-mode-redesign`。本文件列出尚未完成的效能／省電與解耦項目，每一項都要**保持行為不變**，
除非該項明確寫出可接受的差異。以下是讀程式碼得出的判斷，尚未用 Instruments 實測。

## 已完成（不要重做）

- `612ab77`：漫遊規劃搬到 `Sources/GoFlyCore/WanderPlanningCoordinator.swift`。
- `fc885d5`：搖桿起點流程搬到 `JoystickOriginController`；背景 checkpoint 存檔搬到 `SessionCheckpointSaver`。
- `5eab942`：通知 dismissed 旗標集中到 `NoticeState`。
- GPS 省電：`GoFlyRealLocation` 改百公尺精度、單次 `requestLocation()`，由 `RealLocationRefresher` 在前景每 8 秒補取，
  裝置被模擬時暫停（見 `app/GoFly/ARCHITECTURE.md` 第 7 點下的說明）。

## 第二輪結果（2026-10-26，同日完成）

| 項目 | 狀態 |
|---|---|
| 1. 可用性改變才送 `availabilityChanged` | 已完成，新增 `RealLocationAvailabilityEventsTests` |
| 2. 不觀察 `recoveryStore`、`location` | 已完成；`GoFlyRealLocation` 改由 `GoFlyMovementModel` 持有 |
| 3. 箭頭補間上限 30fps | 已完成 |
| 4. 移除 `noticeKey` | 已完成；`acceptedFix()` 一併移除 |
| 5. 拆成子 View | 部分完成：浮動通知抽成 `App/GoFlyMapToastStack.swift`（只收被觀察物件、binding 與值，SwiftUI 可略過重算）。見下方說明 |
| 6. `PositionKeepAlive` 按需計時 | 不做，原因見下方 |

**第 5 項為何停在通知**：`topBar`、`mapControls`、各面板都要靠 closure 回呼父 View（搜尋、Recenter、展開面板等），
closure 會讓 SwiftUI 無法判斷輸入沒變，拆出去只改善可讀性、不省重算。而且父 View 仍觀察所有 controller，
每次變更仍會重算父 body。要真正減少重算，下一步應是 `@Observable` 遷移（見文末），之後再拆其餘部分才有效益。

**第 6 項為何不做**：`keepAliveTarget` 取決於 native busy、模擬是否已清除、顯示位置、movement authority、
搖桿 owner 五個未發布的狀態。要按需啟動，就得在其中任何一個改變時發事件檢查，成本比它省下的
「前景每 15 秒一次、無事可做就結束」的喚醒更高，也會改變 ADR 0001 定義的心跳時點。

## 工作方式（必讀）

- 先讀 repo 根目錄 `AGENTS.md`。不要執行 Prettier。
- 可測的邏輯放 `Sources/GoFlyCore`，測試放 `Tests/GoFlyCoreTests`（Swift Testing，`@Suite @MainActor`）。
  `ServiceController(service: JoystickControlledDevice())`、`RouteTestClock` 是現成的測試替身。
- 驗證指令（在 `app/GoFly`）：
  - `swift test`：全部 Core 測試，目前 337 個。
  - `xcodebuild -project GoFly.xcodeproj -scheme GoFly -destination 'generic/platform=iOS Simulator' build`
- 新測試寫完後，故意改壞對應的程式碼確認測試會失敗，再改回來。
- `GoFlyMapView.body` 的 modifier 鏈已接近編譯器型別檢查上限：再加 `onChange` 會出現
  「unable to type-check this expression」。新的 modifier 請加在 `mapContent(in:)` 的鏈上，或先完成第 5 項拆分。
- 每項各自一個 commit，訊息結尾加 `Co-Authored-By` 行（依當時的 attribution 指示）。
- 改到已確認的行為或規格時，同一個任務內更新 `app/GoFly/ARCHITECTURE.md` 等相關文件。

## 待辦（依建議順序）

### 1. 真實定位只在「可用性」改變時送 `availabilityChanged`

- 位置：`Sources/GoFlyCore/ServiceController.swift` 的 `observeRealLocation(_:)`。目前每收到一筆定位，都會
  `routeSubject.send(.availabilityChanged)` 和 `joystickSubject.send(.availabilityChanged)`，讓
  `RouteExecutionController` 與 `JoystickMovementController` 各送一次 `objectWillChange`，地圖整個重算。
- 收這個事件的地方：`RouteExecutionController.receive` 在 `.currentLocationUnavailable` 時重新規劃；
  `JoystickOriginController.receive` 補建起點；`JoystickMovementController` 只送 `objectWillChange`。
- 正確的判斷**不是**單看 `realLocation` 是否為 nil：`currentRouteOrigin`、`currentJoystickOrigin` 另外要求定位在
  15 秒內，所以一筆過期定位被新定位取代時，可用性也會從「不可用」變成「可用」。
  做法：更新前後各算一次 `currentRouteOrigin != nil` 與 `currentJoystickOrigin != nil`，有任一個改變才送事件。
- 驗收：
  - 新增測試：連續兩筆有效定位只送一次事件；過期後再收到新定位會再送一次。
  - 現有 route／joystick 測試全部通過。

### 2. 地圖 View 不要觀察 body 沒讀的物件

- 檔案：`App/GoFlyMapView.swift`。
- `recoveryStore` 是 `@ObservedObject`（約第 167 行），body 只在一個按鈕動作裡用到（`clearMovementState()`）。
  每次 checkpoint 存檔時 `isSaving` 會切換，讓整個地圖畫面重算。改成 `let recoveryStore: SessionRecoveryStore`，
  並移除 init 裡的 `_recoveryStore = ObservedObject(...)`。
- `location`（`@StateObject private var location = GoFlyRealLocation()`）在 body 裡也沒有被讀，只用在 `onReceive`
  和動作裡。改由不會跟著 View 重建的擁有者持有（例如 `GoFlyMovementModel` 的 `let location`），View 用一般參考取用；
  `onReceive(location.$observation)` 照舊。注意：`GoFlyRealLocation` 建立時會設定 `CLLocationManager`，
  必須只建立一次。
- 驗收：
  - App 能 build。
  - 行為不變：Recenter、搖桿起點、App 回到前景後重新取定位都照常。

### 3. 限制箭頭補間動畫的更新頻率

- 位置：`App/GoFlyMapCanvas.swift` 的 `animateCoordinate`（約第 287 行）建立 `CADisplayLink` 時沒有限制頻率；
  路線與漫遊每秒一次 ACK，補間長 0.25～1.1 秒，所以移動期間幾乎持續以螢幕最高刷新率（ProMotion 120Hz）執行。
- 做法：`displayLink.preferredFrameRateRange = CAFrameRateRange(minimum: 15, maximum: 30, preferred: 30)`。
- 驗收：
  - 移動中的箭頭仍然平順，不超前 ACK。
  - Reduce Motion 時仍然不播動畫（`shouldAnimate` 不變）。

### 4. 移除沒有使用的 `GoFlyRealLocation.noticeKey`

- `@Published noticeKey` 和 `dismissNotice()`、`acceptedFix()` 裡清除它的程式碼，整個 App 都沒有顯示或讀取；
  它只會觸發多餘的重算。移除 `noticeKey`、`shownNoticeCauses`、`dismissNotice()`。
  `fail(_:)` 仍要把 `observation` 設成 nil；`acceptedFix()`／`rejectedFix()` 的呼叫端在 `GoFlyMapView` 的
  `onReceive(location.$observation)`，要一併整理。
- 驗收：App 能 build；定位失敗時搖桿起點提示照常出現（`JoystickOriginController.fixUnavailable/fixRejected` 路徑）。

### 5. 解耦第 4 步：拆成子 View

- `GoFlyMapView` 約 1,900 行；`mapContent`（約第 536 行）、`bottomChrome`（約第 680 行）、`modePanel`（約第 848 行）、
  `topBar`（約第 1259 行）、`mapControls`（約第 1348 行）、`floatingSystemToast`（約第 1704 行）都是同一個 body
  的一部分，任何被觀察物件變更都會讓全部一起重算。
- 做法：拆成各自的 `View` struct，只傳入它需要的值或物件，讓每秒的移動進度只重算讀到它的那一塊。
  優先順序：`floatingSystemToast`（讀很多 controller，但很少變）→ `topBar` → `mapControls` → 面板。
- 這一步不改 UI；若需要對照設計稿，依 `AGENTS.md` 以 Figma `04 · iOS Redesign` 為準。
- 驗收：
  - App 能 build。
  - `GoFlyJoystickUITests` 在模擬器通過。
  - 畫面與互動不變。

### 6.（可選，效益小）`PositionKeepAlive` 只在有維持目標時才計時

- `Sources/GoFlyCore/PositionKeepAlive.swift`：前景時固定每 15 秒醒來，沒有 `keepAliveTarget` 就什麼都不做。
  `keepAliveTarget` 是 `ServiceController` 的 internal 屬性，需要一個「目標出現／消失」的事件才能改成按需啟動。
  若做，要保持 ADR `docs/adr/0001-event-driven-session-liveness.md` 的 15 秒心跳語意。

## 之後再評估

- 專案最低版本是 iOS 26，可把 controller 從 `ObservableObject` 改為 `@Observable`，讓 SwiftUI 只追蹤實際讀到的屬性。
  範圍大，等第 5 項完成後再評估。
- 以上項目都還沒有實機量測。完成後建議用 Instruments（SwiftUI、Energy Log）在 ProMotion 裝置上比較移動中的
  body 重算次數與耗電。
