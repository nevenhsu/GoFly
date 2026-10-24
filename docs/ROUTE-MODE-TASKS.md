# Route Mode 開發任務清單（2026-10-24）

視覺準據：Figma `04 · iOS Redesign（Google Maps 參考）`，`D · 路線：規劃、選點、執行模式`（D1–D22、D6.a 與 Dark 對應）。D section 已大幅更新，頁面一律對照渲染畫面開發，並使用 `0 · 共用元件（正式版 token）` 的元件。
行為與元件規格：[iOS UI 設計與驗收規格](IOS-UI-DESIGN.md)，其中「2026-10-24 共用元件規格」一節列出數值。
本文件只列待辦與證據，不代表已實作或已通過真機驗證。程式路徑相對於 `app/GoFly/`。

## 已確認決定

- 進入路線 tab：D1 完整面板，不自動開 D5／鍵盤。起點預設目前位置，無最後模擬位置與真實 GPS 時留空。
- 預設選中「起點」（依 Figma D1）。點欄位只切換選中欄位；由地圖 Pin（D4）或頂部搜尋列（D5）設定選中欄位。
- 自動收合只由候選 Pin 觸發，拖曳地圖不收合。
- 起點與終點常駐 ✕（空值時停用），清除後保留空欄位；停靠點 ✕ 刪除整列；皆顯示 D9 黑底「復原」snackbar。
- 路線與搖桿／漫步共用並保存同一速度偏好：5／25／50／100，預設 25。
- D1 不顯示速度膠囊；只有 D1 右上星號開 D19，底部星號開 D20；undo 文案「復原」。
- D1b（Pin「新增」為目的地）已廢止。

## 共用元件（先做，路線頁面依賴）

| # | Figma 元件 | App 現況 | 待辦與驗收 |
| :-- | :-- | :-- | :-- |
| C1 | `Toast / 系統訊息 / danger｜warn｜success` | 兩套實作：`App/GoFlyStatusBanner.swift`，與 `App/GoFlyWarningToast.swift`（14／12 pt 字、實心 `#FF9500` 邊、固定 80 pt、寫死「重試」） | 合併為單一 tone 驅動元件：15 pt Semibold／13 pt Regular、圓角 14、內距 12／14、邊框 35% 不透明、白色 56 × 32 膠囊動作、20 pt ✕、高度隨內容。驗收：D8（danger＋重試）、D10（warn＋重試）、D18 渲染對齊；深色對齊 Dark D8／D10；最大字級可換行。<br>**狀態：已實作，待審查**（`GoFlyWarningToast` 已移除，D10 改用 `GoFlyStatusBanner(tone: .warning)`；`GoFlyToastUITests`）。 |
| C2 | `Snackbar / 2 秒自動消失`、`Snackbar / 可復原` | `App/GoFlySnackbar.swift`：`.footnote` 字、純文字 action、時長固定 2 秒（modifier 可傳 duration）、陰影 18%／12 | 白字 15 pt Medium、24 pt 綠勾、內距 10／14、Figma 雙層陰影；action 改白色 56 × 32 膠囊；可復原版本 5 秒；可指定位置（D9 為 sheet 上方約 12 pt，D22 為底部按鈕上方 12 pt）。驗收：B6、D9、D17、D22 對齊。<br>**狀態：已實作，待審查**（含 action 的 snackbar 預設 5 秒、其餘 2 秒；位置仍由 `bottomPadding` 決定，D9／D22 位置隨 R4 處理；`GoFlySnackbarUITests`）。 |
| C3 | `StatusPill / 啟動｜模擬中｜暫停｜停止｜連線中斷` | `App/GoFlyStatusPill.swift` 版型相符 | 回歸：點色 `#8E8E93`／`#34C759`／`#FF9F0A`／`#8E8E93`／`#FF3B30`、雙層陰影。D6 顯示「模擬中」、D10「暫停」、D6.a 開啟時「停止」。文案依「三模式 session pill 五態規格」。 |
| C4 | `SearchBar / 浮動`、`SearchField / focused｜normal`、Slider、Progress | 搜尋列已存在；DESIGN.md 舊規則用 `systemGray5` 輸入底 | SearchField 改 `#F2F2F7` 底、focused 1.5 pt `#007AFF`、normal 0.75 pt `#8E8E93`。路線選中列沿用 focused 樣式。Progress 6 pt、Slider 黑白軌道。驗收：D5、D1 選中列、D6 進度列、D7 slider 對齊。<br>**狀態：已實作，待審查**（`goFlySearchField(isFocused:)`、`GoFlyProgressStyle` 已套用；D1 選中列隨 R3 套用；`GoFlyFieldUITests`）。 |
| C5 | checkbox（圓形）on／off | `GoFlyCheckboxIcon`（`GoFlyFavoritesView.swift:176`、`GoFlyFavoriteRoutesView.swift:156`） | 回歸：on 24 pt 黑圓白勾（深色白圓黑勾），off 22 pt `#C7C7CC` 1.5 pt 邊（深色 `#2C2C2E` 底＋`#8E8E93` 邊），44 pt 命中。驗收：C3、D21 淺深色。 |
| C6 | `TabBar / 瞬移・路線・搖桿（等寬）` | `App/GoFlyBottomBar.swift`：圖示 22 pt、`caption2` bold／medium | 圖示 25 pt、選中 2.29 pt 黑線＋10 pt 黑字、未選 1.875 pt `#999999`；背景 `#F9F9F9` 96%＋頂部細線；高 83 pt（含 home indicator）。驗收：D1–D4、D8、D9 的 `Mode=路線` variant 對齊；執行模式（D6／D7／D10）隱藏。<br>**狀態：已實作，待審查**（`GoFlyTabBarUITests`：高 83、三格等寬、選中 trait）。 |

| C7 | 地圖右下角 `Recenter`（Figma 已同步修正為單一按鈕） | `App/GoFlyMapView.swift:1246` `mapControls` 有三顆：執行模式「跟隨方向」、地圖旋轉後「指北」、「回到定位」；位置以 `sheetHeight`＋bottom bar 計算；`GoFlyMapCanvas.swift:117／125` 殘留未使用的 `MKCompassButton` | 所有 mode 只保留「回到定位」，點擊同時重設正北；移除跟隨方向、指北與殘留 compass 程式碼與字串。按鈕固定在當下 panel 上緣上方 16 pt、右側 16 pt。驗收：B1、B2、D1、D2、D3、D6、D10、E1、E2 截圖量測間距皆 16 pt；拖曳 sheet 時按鈕跟隨；地點卡、D5、D6.a、D7 開啟時隱藏；UI test 確認 `map.followHeading`、`map.north` 不存在。<br>**狀態：已實作，待審查**（`GoFlyMapControlsUITests` 量測瞬移／路線／搖桿與收合；按鈕在地點卡、搜尋、選點時隱藏；點擊同時轉正北。未涵蓋：執行／中斷面板與 dialog 隱藏，隨 R6／R7 驗證）。 |

## 路線頁面

### R1 共用速度偏好（D7）
- 現況：`App/GoFlySpeedSheet.swift:10` 為 `[5, 20, 60, 120]`；`Sources/GoFlyCore/RouteDraft.swift:17` 預設 20；路線（`RouteDraft.speed`）與搖桿（`JoystickMovementController.speed`、`SessionRecoveryStore.joystickSpeed`）各自保存。
- Figma D7：40% dim、標題「設定移動速度」＋右上「完成」、「目前時速 25 km/h」、4 膠囊（選中黑底白字）、Slider 1–120、底部「完成設定」。
- 做法：快選改 5／25／50／100、預設 25；在 `GoFlyPreferences` 新增單一移動速度偏好，路線與搖桿共用；保留 session 復原但以偏好為初始值。
- 驗收：首次安裝兩處皆 25；D7 改 50 後漫步顯示 50，反之亦然；重開 App 保留；執行中改速即時更新 D6 剩餘時間；單元測試涵蓋共用與保存。

### R2 起訖空值與 D1／D2 清單（D1、D2）
- 現況：`RouteNodeValue` 無空值；`RouteDraft()` 只建立起點；`App/GoFlyRouteNodeList.swift:134` 只對停靠點顯示刪除。
- Figma D1／D2：清單卡 353 pt、圓角 14、0.5 pt 邊；每列 60 pt，左 grip、角色小標 12 pt（起點／停靠點 N／終點）、地點 17 pt；右側中性灰 ✕（44 pt）。
- 做法：起點與終點為固定欄位、可為空值；端點 ✕ 常駐、空值時停用；停靠點 ✕ 刪除整列；角色名稱統一「停靠點 N」。
- 驗收：任一端點為空時 Start 停用且不規劃；反轉順序同時交換空值；GPX 唯讀不顯示 ✕；VoiceOver 區分「清除起點」「刪除停靠點 N」。

### R3 選中欄位模型（D1、D4、D5）
- 現況：`App/GoFlyMapView.swift:826` `onEditNode` 直接開 D5；頂部搜尋列在路線 tab 開一般搜尋。
- Figma：D1 選中列 `#F2F2F7`＋1.5 pt `#007AFF`＋藍色游標；D5 為 `SearchField / focused`（placeholder「選擇終點」）＋灰底旗標 chip「正在選：終點」＋右側「最愛地點」，「最近搜尋」＋「清空記錄」。
- 做法：新增選中欄位狀態，預設起點；點列只切換選中；路線 tab 頂部搜尋列開 D5（chip 與 placeholder 依選中欄位）；D4 Pin「確認」與 LocationCard「確認」回填選中欄位並回到 D1。
- 驗收：進入路線 tab 不彈出 D5 或鍵盤；點終點列再點搜尋列，chip 顯示「正在選：終點」；返回不改原值；選取結果只改選中欄位；選中狀態不只靠顏色（加 `.isSelected` trait）。

### R4 D9 清除復原
- 現況：`removeNode` 無復原。
- Figma D9：C2 `Snackbar / 可復原`「已清空路線地點」＋「復原」，位於 bottom sheet 上方約 12 pt。
- 驗收：5 秒內復原原值與原位置；逾時消失；連續刪除只復原最近一次；三語；深色 Dark D9。

### R5 D1／D2 面板版面
- 現況：`GoFlyRoutePanel.editingView` 將標題、清單、新增、反轉放在同一 `ScrollView`；底部星號 50 pt 有邊框。
- Figma：sheet 高 369 pt（D1）；標題 20 pt Semibold；右上 44 pt 圓鈕（`#F2F2F7`、0.5 pt 邊）；「＋ 新增停靠點」與「⇅ 反轉順序」15 pt Semibold；底部 56 pt 星號（`#EEEEF0`、無邊）＋56 pt「開始」capsule。D2 只有清單捲動（最多 4 列可視、顯示捲動指示器），其餘固定。
- 驗收：D1、D2 截圖並排對齊；5 個以上地點時捲動清單不拖動 sheet；最大字級時可重排。

### R6 D6／D6.a 執行面板與結束確認
- 現況：`App/GoFlyRoutePanel.swift:81` 使用系統 `confirmationDialog`，文案「取消這次路線？」。
- Figma D6：頂部深色指示卡（導航箭頭、「前往 …」、剩餘距離／時間／速度）、`StatusPill / 模擬中`、右側 Follow／Recenter、底部進度列（`Progress`）、純圖示控制列（來回、方向、速度 chip「⏱ 25 ›」）、「✕ 結束」（灰 capsule）＋「⏸ 暫停」（黑 capsule）。
- Figma D6.a：35% 遮罩、居中 dialog（圓角 20），標題「結束這次路線？」，說明「確認後將停止模擬路線並保留目前位置，回到路線規劃模式。」，灰色「取消」與紅色「結束路線」並排 capsule；pill 顯示「停止」。
- 驗收：取消後路線繼續、進度不變；結束後停止送點、保留最後模擬位置並回 D1；dialog 開啟時其他元素不可操作、VoiceOver 焦點鎖定；Dark D6.a 對齊；三語。

### R6.1 移除 D1b「新增」
- 現況：`App/GoFlyMapView.swift:680` 與 `:1415` 呼叫 `route.appendDestination`（`RouteExecutionController.swift:160`）。
- 做法：與 R3 一起處理；路線 Pin 與 LocationCard 只保留「確認」（D4：Pin 上 28 pt 黑底「確認」、卡片「確認／收藏／複製」）；移除未使用的 append API、字串與 UI test。
- 驗收：路線 tab 點 Pin 不出現「新增」；選中停靠點時確認只改該停靠點。

### R7 D10 中斷恢復
- Figma D10：頂部卡改為暫停圖示＋「已暫停 · 前往 …」；`StatusPill / 暫停`；C1 warn toast「路線模擬已暫停」＋「任務意外中斷，點選重試自中斷點恢復行進。」＋「重試」＋✕；底部 76 pt 窄面板「路線已暫停 · 45%」／「剩餘 1.2 km · 預估 14 分鐘」＋黑色「繼續路線」；無 TabBar。
- 驗收：淺深色對齊；「重試」與「繼續路線」呼叫同一 resume；toast 關閉不影響面板。

### R8 回歸
- 收合：拖曳／縮放地圖不改變面板高度；放 Pin 收合為 76 pt（D3：只剩標題與兩個圓鈕）；確認或關閉 Pin 卡回 D1。
- 最近搜尋：`App/GoFlyMapView.swift:194` `recentPlaces` 已共用；D5「清空記錄」後瞬移也清空，仍只存在記憶體、最多 8 筆。
- D19／D20 入口、D1 無速度膠囊、D22 黑底「復原」維持正確。

## 建議順序

C1–C2（R4、R7、D8 依賴）→ C4、C6、C7 → R1 → R2 → R3＋R6.1 → R5 → R4 → R6 → R7 → C3、C5、R8 回歸。R2、R3、R5 都改路線面板，應在同一分支依序處理。每項需單元測試或 UI test；最後依 `docs/AI-INSTALL.md` 安裝到實機，以淺色與深色截圖對照 Figma 驗收。

## 待決與 Figma 衝突

- 預設選中起點時，第一次點 Pin 確認會取代「目前位置」起點；要設定目的地須先點終點列。這是依 Figma D1／D4 的行為，若希望第一次 Pin 直接設目的地，需改設計。
- D1 選中列帶藍色游標，看起來像可直接輸入；目前規格視為選中狀態標示，不在列內開鍵盤。
- D1 說明文字仍寫「點欄位開 D5」、D9 說明寫「搜尋列下方」與「還原」、section 說明寫「D1 右上或下方星號開 D19」，皆與渲染畫面或已確認決定不符；以渲染畫面與決定為準，說明文字待更新。
- D6／D6.a／D10 頂部卡寫「5 km/h」、Speed chip 為「9」，與 D7 預設 25 不一致；實作顯示實際偏好值。
- `StatusPill / 連線中斷` 元件實際文字為「錯誤」；`Toast / warn` 元件預設按鈕「繼續」，D10 覆寫為「重試」。
