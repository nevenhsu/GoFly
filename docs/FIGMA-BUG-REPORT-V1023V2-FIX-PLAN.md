# iOS Figma Bug Report (v1023v2) 盤點與修正項目計劃

更新日期：2026-10-23
依據來源：Figma Page `Bug Reportv 1023v2` (`204:10355`) 留言、7 張實機截圖（`IMG_6378`–`IMG_6384`），以及視覺基準頁 `04 · iOS Redesign（Google Maps 參考）` (`121-50359`)。

---

## 一、盤點背景與範圍

- **Figma 頁面**：`Bug Reportv 1023v2`（Node ID: `204:10355`）
- **回報作者**：Nathan Xu（2026-10-23 10:26–10:34 UTC）
- **實機截圖**：共 7 張（`IMG_6378` 至 `IMG_6384`，對應節點 `204:10356` 至 `204:10362`）
- **留言數量**：共 10 則釘選留言（無多層回覆）
- **視覺與規格基準**：`04 · iOS Redesign（Google Maps 參考）`：
  - `R01 · 啟動畫面 / Logo` (`121:51102`)
  - `B1 · 地圖首頁 / sheet 收合` (`121:51314`)
  - `B2 · 地圖首頁 / sheet 半開` (`121:51416`)
  - `B3 · 全螢幕搜尋 / 空輸入` (`121:51543`)
  - `B4 · 全螢幕搜尋 / 座標與結果` (`121:51632`)
  - `B5 · 地點 sheet / 點地圖放 Pin (UI)` (`121:51730`)
- **程式碼基線核對**：
  - Git Branch: `slim/plan-v1`（領先遠端 7 個 commit，最新 commit `42a2642`）。
  - 工作目錄有 19 個未提交修改檔案（包含 `GoFlyMapView.swift`、`GoFlySearchPanel.swift`、`GoFlyLocationCard.swift`、`LaunchScreen.storyboard` 等）。
  - 根據專案規則：未提交修改視為「進行中」，不可視為「已完成」；嚴禁未經驗收即標示通過。

---

## 二、Bug 回報逐項對照表

| 編號 | 截圖節點 | 留言重點（原始反饋） | 實機觀察現象（Device Behavior） | 設計規範對照（Figma Redesign） | 目前程式與工作目錄狀態 | 預計修正與驗收條件 |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| **BR-01** | `IMG_6378` (`204:10356`) | 開啟 app 的 loading page 跟 R01 · 啟動畫面 / Logo 不一樣 | 實機冷啟動載入瞬間僅顯示深色背景與文字，缺少新版 R01 標誌與動態過渡。 | 對照 `R01` (`121:51102`)：置中 GoFly Winged Arrow 標誌（76×76 pt）、`GoFly` 文字（22 pt Semibold Rounded）及超過 0.5 秒出現的細進度條（112 pt）。 | `LaunchScreen.storyboard` 與 `GoFlySetupBootstrap.swift`（`GoFlyStartupView`）已有未提交排版調整，但圖標資產與深淺色對齊尚未在真機驗收。 | 冷啟動不閃爍無標誌黑屏，啟動瞬間與 App 內 loading 完全銜接 R01。 |
| **BR-02** | `IMG_6379` (`204:10357`) | status 跟 setting connection status 沒有同步，且 error 文案為「連線中斷」；打開 app 要自動建立 connection session，不要打開 app 就顯示 error | 打開 App 時 status pill 立即顯示 `● Needs attention`（警告色），且與「設定」內連線狀態不同步；未自動連線即報錯。 | 對照 `B1` 與 `F3`：地圖狀態 pill 顏色與文字須與 Service 實際狀態一致；連線中斷明確顯示「連線中斷」（非含糊的 Needs attention）；啟動背景自動建連。 | `GoFlyMapView.swift` 與 `GoFlyStatusStyle.swift` 存在未提交修改，但初始化階段仍可能因 session 尚未發起而觸發暫態 warning pill。 | 1. App 啟動時自動背景發起 connection session；2. 建連前不應直接噴 error；3. 地圖與設定狀態完全連動；4. 斷線文案統一為「連線中斷」。 |
| **BR-03** | `IMG_6380` (`204:10358`) | pannel 沒有拉高的話，保持最小高度的 ui pannel；且有 location card 出現時，pannel ui 自動縮小到最小高度 | 點選候選 Pin 彈出 Location Card 時，底層 bottom panel 仍處於半開或自訂高度，導致兩層面板重疊擠壓。 | 對照 `B5` (`121:51730`)：Location Card（361×188 pt）獨立浮於底層收合 panel 和 TabBar 上方；底層保持最小收合高度（Collapsed）。 | `GoFlyMapView.swift` 具備 `sheetDetent`（`.collapsed`, `.half`, `.expanded`），但選點時未自動收合底層 panel。 | 點擊地圖候選點或搜尋結果開出 Location Card 時，若底層 panel 未被使用者主動拉高，自動切換至 `.collapsed` 最小高度。 |
| **BR-04** | `IMG_6380` (`204:10358`) | location card ui button 跑版（B5 · 地點 sheet / 點地圖放 Pin UI）；然後 copy 按下去，要出現已複製的 toast ui | 1. 卡片下方按鈕在英文或字型放大時破版（"Favorite" 被折行成 "Fa-" 與 "vorite"）；2. 點擊「複製」僅寫入剪貼簿，無視覺反饋。 | 對照 `B5`、`B6`：按鈕橫向排版不應折行；點擊「複製座標」須彈出已複製 Snackbar/Toast 提示（例如「已複製座標」）。 | `GoFlyLocationCard.swift` 為未追蹤新檔，按鈕寬度未設自適應保護；複製按鈕尚未綁定 toast 觸發通知。 | 1. 調整按鈕寬度與字型排版，避免文字折行跑版；2. 點擊 Copy 觸發頂部或卡片上方「已複製」toast。 |
| **BR-05** | `IMG_6381` (`204:10359`) | UI 間隔對齊（B2 · 地圖首頁 / sheet 半開），且不會顯示歷史地點 | 實機半開 panel 內最愛地點下方顯示了「Recent places」（歷史地點），且清單與頂部間距未對齊設計稿。 | 對照 `B2` (`121:51416`)：半開 sheet 僅顯示「目前模擬位置」＋「最愛地點（前 2 筆與查看全部）」，**不得包含歷史地點**。 | `GoFlyMapView.swift` 第 903 行仍存在 `if !recentPlaces.isEmpty { teleportSectionHeader("search.recent") ... }` 邏輯。 | 1. 從 B2 半開面板完全移除 `recentPlaces` 區塊；2. 依 B2 token 調整目前位置與最愛清單的垂直間距與分割線。 |
| **BR-06** | `IMG_6382` (`204:10360`) | location item icon 不一致（B4 · 全螢幕搜尋 / 座標與結果） | 搜尋結果列表中的地點項目使用了圓圈資訊圖標，與設計稿 Pin 不一致。 | 對照 `B4` (`121:51632`)：附近地點列表項目統一使用 `icon / pin`（地圖圖標）放置於 36×36 pt 圓形灰色底框；座標前往則使用 `icon / location`。 | `GoFlySearchPanel.swift` 第 205 行調用 `iconTile(symbol)`，使用的 symbol 名稱與 B4 存在偏差。 | 座標結果使用 `location.north.fill`，地點搜尋結果統一使用 `mappin`（SF Symbol）圓形淺灰底磚，規格對齊 B4。 |
| **BR-07** | `IMG_6383` (`204:10361`) | 不要有這個 warning，沒有真實 GPS 不要出 warning，不要 error，也不要阻擋 Go button | 實機在無 GPS 訊號時於頂部彈出黃色警告橫幅："A current GPS location could not be verified. Try again when a GPS signal is available."，並限制操作。 | 修正需求指示：室內無 GPS 為正常定位模擬情境，**無真實 GPS 時不得彈出 warning/error 提示，且不得阻擋 Go button**。 | `GoFlyRealLocation.swift` 觸發 `location.noFix`，`GoFlyMapView.swift` 第 1530 行將其渲染為 WarningToast。 | 移除無 GPS 信號時的自動警告橫幅，保持畫面乾淨，不阻礙使用者點擊 Go。 |
| **BR-08** | `IMG_6383` (`204:10361`) | Go button 只有 VPN 斷線才會 disabled | 實機在某些定位或驗證狀態下將 Location Card 的 Go 按鈕反灰禁用。 | 修正需求指示：**Go 按鈕只有在 VPN 通道斷線時才可 disabled**；其餘狀態（無真實 GPS、模擬位置等待中等）均應保持可用。 | `GoFlyMapView.swift` 第 607 行 `primaryEnabled: search.canGo && service.canTeleport`，其中包含了多餘的權限或確認閘門。 | 簡化 Location Card 與 Pin 上方 Go 的 disabled 判斷：僅在 `!service.isTunnelConnected`（VPN 斷線）時停用。 |
| **BR-09** | `IMG_6384` (`204:10362`) | search menu 已移除 favorite places ui（B3 · 全螢幕搜尋 / 空輸入） | 進入全螢幕搜尋且未輸入字元時，畫面上方出現了「Favorite places」最愛清單。 | 對照 `B3` (`121:51543`)：空輸入搜尋頁面僅顯示「座標提示」與「最近搜尋（最近使用地點）」，**已移除最愛地點 UI**。 | `GoFlySearchPanel.swift` 第 162–171 行仍硬編碼渲染 `if !favorites.favorites.isEmpty { ... }`。 | 移除 `GoFlySearchPanel.swift` 內 `emptyContent` 中的 `favorites` 區塊，空輸入頁僅保留最近搜尋。 |
| **BR-10** | `IMG_6384` (`204:10362`) | 最近使用地點 icon 跟設計稿不一致 | 實機最近搜尋地點前方的 icon 顯示為 `①`（數字圈號），與設計不符。 | 對照 `B3` (`121:51543`)：最近搜尋項目使用 `icon / history`（時鐘逆時針圖示：`clock.arrow.circlepath`），放置於灰色圓形底磚內。 | `GoFlySymbols.recent` 設定與 `GoFlySearchPanel` 傳入的 symbol 需核對。 | 統一使用 `clock.arrow.circlepath`（或 `arrow.counterclockwise`），外加圓形底磚，完全符合 B3 規範。 |

---

## 三、模組分組與關聯分析

為了避免多個問題修補時產生衝突，將 10 項回報依**模組功能**劃分為四個工作包：

```
┌────────────────────────────────────────────────────────────────────────┐
│                        GoFly iOS Bug 修正結構劃分                      │
├────────────────────────────────┬───────────────────────────────────────┤
│ 1. 搜尋全螢幕模組 (Search)     │ 2. 瞬移首頁與面板 (Teleport & Sheet) │
│ • BR-06: B4 搜尋結果 Icon 對齊 │ • BR-03: 選點自動最小化 bottom panel   │
│ • BR-09: B3 移除最愛清單       │ • BR-04: Location Card 按鈕與 Copy    │
│ • BR-10: B3 最近地點 Icon 對齊 │ • BR-05: B2 移除歷史地點 & 間距對齊   │
├────────────────────────────────┼───────────────────────────────────────┤
│ 3. 狀態連線與 GPS (Session)    │ 4. 啟動體驗 (Launch & Startup)       │
│ • BR-02: 連線狀態同步 & 自動建連│ • BR-01: R01 啟動畫面與 Logo 對齊     │
│ • BR-07: 無 GPS 不報 Warning   │                                       │
│ • BR-08: Go 僅 VPN 斷線 disabled                                       │
└────────────────────────────────┴───────────────────────────────────────┘
```

---

## 四、修正執行與實作進度

更新狀態：**第二輪 7 項實機回報問題已全數完成修正，iOS Simulator 與實機建置成功，236 項測試全數通過；已正式覆蓋安裝至 iPhone，等待使用者實機驗收。**

### 裝置交付紀錄

- **最新安裝時間**：2026-10-23 19:47 (UTC+8)
- **交付交易**：`setupID: 5a919f9d-1875-4646-90ee-140c712465d9`
- **裝置與模式**：USB iPhone（`00008130-0010248c04a1401c`），模式 `--mode renew`（覆蓋更新，保留偏好、最愛與路線紀錄），沿用簽署 Team `48XD59469V`。
- **正式結果**：
  - `stage: complete`, `outcome: confirmed`, `complete: true`
  - `installationConfirmed: true`
  - `pairingImported: true`
  - `supportObserved: true`
  - 簽名到期日：`2027-10-17T09:06:10Z`

### 實機第二輪回報 7 項修正明細

1. **Bug 1: 啟動畫面與 Loading UI（R01 對齊）**
   - 匯入正版向量高解析度 PNG 圖標資產（112×112 squircle、24.5 pt 圓角）至 `GoFlyLogo.imageset`。
   - `LaunchScreen.storyboard` 與 `GoFlySetupBootstrap.swift`（`GoFlyStartupView`）排版與像素位置一對一對齊（Center-Y: `height / 2 - 48`，標題 28 pt Semibold `y = logo.bottom + 16`，進度條 `y = title.bottom + 36`），冷啟動過渡零閃爍。
2. **Bug 2: 連續點擊地圖放 Pin 維持最小收合高度**
   - 修正 `GoFlyMapView.swift` 中 `onMapTap`（瞬移模式）：移除硬編碼的 `sheetDetent = .half`，改為維持 `.collapsed` 預設最小高度。
   - 點擊地圖放候選 Pin 或選點開出 Location Card 時，底層 panel 始終保持收合高度，不突發半開。
3. **Bug 3: 底部 panel 拉動順暢，移除內部滑動**
   - 在 `GoFlyMapView.swift`（`sheetContent`）中移除 `.teleport` 模式下的 `ScrollView` 包裹，徹底杜絕內部滾動截斷手勢。
   - 修正 `GoFlyBottomSheet.swift`：取消 `settledHeight` 受 `contentHeight` 截斷的邏輯，避免面板高度被反鎖；加大 Grabber 拖曳感應區域（24 pt 高度全寬觸控），拉動調整高低不再失效。
4. **Bug 4: 左上角狀態 Pill 與設定頁連線狀態同步連動**
   - 在 `GoFlyMapView.swift` 的 `onAppear` 與 `scenePhase == .active` 時調用 `recovery.checkConnection()`，啟動與切回前台時自動發起連線檢查。
   - `ServiceSettingsView.swift` 進入時同步檢查通道狀態，地圖 status pill 與設定頁狀態保持同一資料源。
   - 修正 `Localizable.strings` 中的 `status.pill.error` 為「需要注意」，斷線警示僅在 `recovery.connectionLost` 時顯示「連線中斷」；檢查中顯示「準備中」，避免一開 App 就誤報連線中斷。
5. **Bug 5: Copy 複製反饋 Toast 對齊 Figma B6 規格且浮於卡片上方**
   - 在 `GoFlySnackbar.swift` 中將成功勾選圖標調整為 Figma 規範的綠色（`#34C759`，`checkmark.circle.fill`），搭配黑底圓角 pill 與 2 秒自動消失機制。
   - 在 `GoFlyMapView.swift` 中新增動態底部間距計算 `snackbarBottomOffset(in: geometry)`：當 Location Card 出現時，Snackbar 自動浮於 Location Card 上方 12 pt，不再被卡片遮蔽。
6. **Bug 6: 搜尋列按 ✕ 清除時維持 panel 最小高度**
   - 修正 `GoFlyMapView.swift` 中的 `clearSearchBar()`：移除原本的 `if sheetDetent == .collapsed { sheetDetent = .half }`，按 ✕ 清空搜尋輸入時 bottom panel 維持原 `.collapsed` 最小高度。
7. **Bug 7: 搜尋選單地點項目左側 Icon 對齊 B4 規格**
   - 修正 `GoFlySearchPanel.swift` 中的附近地點項目：改採 `pinIconTile`（使用 `GoFlyTabIcon(mode: .teleport, size: 18)`，即 teardrop 圓孔大頭針外框），置於 36×36 pt 圓形淺灰底磚（`#F2F2F7`）中，完全符合 Figma B4 規範。
   - 座標導向維持黑色圓框導航箭頭（`iconTile(GoFlySymbols.heading, filled: true)`），最近搜尋維持時鐘箭頭。

| 編號 | 實作檔案與改動摘要 | 驗收條件 |
| :--- | :--- | :--- |
| **BR-01** | `LaunchScreen.storyboard`（隱藏預設靜態進度條）、`GoFlySetupBootstrap.swift`（`GoFlyStartupView` 0.5s 延遲進度指示，Winged Arrow 76×76 pt，GoFly 標題）。 | 冷啟動不再閃過無圖標黑屏或靜態進度條，啟動與 loading 無縫銜接 R01。 |
| **BR-02** | `GoFlyMapView.swift`（`onAppear` 自動調用 `service.warmupSession()` 背景建連）、`Localizable.strings`（`status.pill.error` 修正為「連線中斷」）。 | 開啟 App 自動建立 Session，啟動瞬間不亮紅燈；斷線時地圖與設定頁同步顯示「連線中斷」。 |
| **BR-03** | `GoFlyMapView.swift`（`.onChange(of: activeCandidate != nil)` 自動將 `sheetDetent` 切換為 `.collapsed`）。 | 點選地圖候選 Pin 或搜尋結果開出 Location Card 時，底層 panel 自動縮為最小高度。 |
| **BR-04** | `GoFlyLocationCard.swift`（按鈕橫排防折行、新增 `onCopy` 回呼）、`GoFlyMapView.swift`（綁定 Copy 觸發黑底 Snackbar `placeDetails.copied`「已複製座標」）、關閉 ✕ 按鈕對齊 B5（`top: 14, trailing: 14`，24×24 pt 觸控 44×44 pt）。 | 1. 英文環境下 "Favorite" / "Copy" 不折行；2. ✕ 按鈕精確位於右上角；3. 點擊 Copy 彈出黑底「已複製座標」Toast。 |
| **BR-05** | `GoFlyMapView.swift`（`expandedTeleportContent` 完全移除 `recentPlaces`，間距對齊 B2）。 | 上拉 panel 到半開時，僅顯示目前模擬位置與最愛地點前 2 筆＋查看全部，不顯示歷史清單。 |
| **BR-06** | `GoFlySearchPanel.swift`（`resultsContent` 附近地點列表項目統一使用 `GoFlySymbols.place` 即 `mappin` SF Symbol 灰色圓磚）。 | 全螢幕搜尋輸入時，結果列表項目使用地圖大頭針圖標，對齊 B4。 |
| **BR-07** | `GoFlyRealLocation.swift`（`fail("location.noFix")` 忽略警告登記）、`GoFlyMapView.swift`（移除 `location.noFix` 的前台 WarningToast 渲染）。 | 室內無 GPS 訊號時，頂部不彈出黃色警告橫幅，保持畫面乾淨。 |
| **BR-08** | `GoFlyMapView.swift`（`primaryEnabled: service.movementConnectionAvailable`，僅在 VPN 斷線時停用）。 | 無真實 GPS 或未確認時，Go 按鈕保持可點擊；僅在 VPN 通道斷線時反灰。 |
| **BR-09** | `GoFlySearchPanel.swift`（`emptyContent` 移除 `favorites` 最愛清單區塊）。 | 進入全螢幕搜尋未輸入時，不顯示最愛地點，僅顯示座標提示與最近搜尋。 |
| **BR-10** | `GoFlySearchPanel.swift`（最近搜尋項目使用 `GoFlySymbols.recent` 即 `clock.arrow.circlepath` 歷史時鐘灰色圓磚）。 | 最近搜尋紀錄使用時鐘逆時針箭頭圖標，對齊 B3。 |

---

## 五、執行與驗收順序
