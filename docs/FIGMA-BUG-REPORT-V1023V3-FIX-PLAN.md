# GoFly iOS Figma Bug Report v1023v3 修正規格與驗收紀錄

> 建立時間：2026-10-23 20:40 (UTC+8)
> 依據來源：Figma 頁面 `Bug Reportv 1023v3`（`206:10363`）8 張實機截圖與 9 則 comments，對齊權威設計頁 `04 · iOS Redesign（Google Maps 參考）`（`121:50359`）。

---

## 一、回報項目對齊與根因明細

### 1. 啟動畫面殘留舊 UI 與舊 Logo 修正（對齊 R01）
- **截圖依據**：`IMG_6386`（`206:10364`）與 `IMG_6387`（`206:10365`）
- **Comments**：
  - `206:10364`：「loading page 有殘留舊的 ui (logo也是錯的), 要更新為正確UI」
  - `206:10365`：「loading page 隨後淡入的畫面是正確的」
- **根因**：
  1. `GoFlyLogo.imageset` 殘留歷史 `logo.pdf` 與 `logo-dark.pdf` 舊箭頭向量檔。
  2. `LaunchScreen.storyboard` 原使用 `systemBackgroundColor`，在深色模式下顯示黑底。
- **修正**：
  - 徹底移除舊向量檔案 `logo.pdf` 與 `logo-dark.pdf`，僅保留正式 1x/2x/3x 新版翼星圓角 Logo。
  - `LaunchScreen.storyboard` 與 `GoFlyStartupView.swift` 背景一律強制為純白（`#FFFFFF`），文字與進度條為純黑（`#000000`），排版以 R01 為依據；像素重合與冷啟動過渡仍需實機驗證。

### 2. 左上角 Status Pill 連線狀態連動與文案更正（對齊 B1）
- **截圖依據**：`IMG_6388`（`206:10366`）
- **Comments & 使用者指示**：
  - `206:10366`：「左上角的 status pill 要連動 session. 狀態, 現在打開app 還是 need attention (改成錯的ui/ux了)」
  - 使用者指示：「`status.pill.error` = `Needs attention`; 不要有這個模糊的錯誤, 连接中断 才是正確的!」
- **根因**：
  - 語系檔中 `status.pill.error` 誤設為「需要注意」（`Needs attention`）。
- **修正**：
  - `Localizable.strings` 恢復 `status.pill.error` 為明確的「連線中斷」（zh-Hant: `連線中斷`、zh-Hans: `连接中断`、en: `Connection lost`）。
  - 地圖與設定 Pill 改用同一份 session display state，啟動／探測尚未確認時顯示待命；只有 probe 明確失敗或瞬移 session 修復一次後仍失敗才顯示紅色「連線中斷」。一般錯誤不映射為斷線。前景需求以 pending 保留至舊 probe／native busy 排空。

### 3. 複製座標 Toast 位置異常修正（對齊 B5 / B6）
- **截圖依據**：`IMG_6389`（`206:10367`）與 `IMG_6390`（`206:10368`）
- **Comments**：
  - `206:10367`：「location card 的 copy toast 位置錯誤, 與 location card 上方的間隔太多」
  - `206:10368`：「panel location copy toast 太低, 要放在panel 上緣的上方,」
- **根因**：`snackbarBottomOffset` 計算未區分浮動 Location Card 與收合 Bottom Panel。
- **修正**：
  - 顯示 Location Card 時：Toast 底緣依實測 Location Card 上緣定位，間距 6 pt（本次實機回饋修訂）。
  - 顯示 Bottom Panel 時：瞬移 Toast 底緣依實測 Bottom Panel 上緣定位，間距 6 pt，不重複加入 safe area；其他模式本次不修改。

### 4. 底部 Panel 最大高度限制為半開高度（移除全展開 Detent）
- **截圖依據**：`IMG_6391`（`206:10369`）
- **Comments**：`206:10369`：「panel 最大高度改成目前半開panel的高度, 不要這個完全展開的高度」
- **根因**：瞬移模式下的 Bottom Sheet 支援 `.expanded`（88% 螢幕高）。
- **修正**：
  - 瞬移面板依目前內容加 24 pt grabber 自適應、以上層可用高度為上限，不再鎖定 328 pt。保留收合／半開內容及把手拖曳，不恢復 ScrollView。
  - 點擊 Grabber 或 Pill 僅在 `.collapsed` 與 `.half` 內容間切換，實際高度由內容決定。

### 5. 半開 Panel 之最愛地點清單間距過大與異常豎線修正（對齊 B2）
- **截圖依據**：`IMG_6392`（`206:10370`）
- **Comments**：`206:10370`：「favorite list 間隔太大, 要參考 B2 · 地圖首頁 / sheet 半開 ui design」
- **根因**：
  - SwiftUI 的 `Divider()` 放在 HStack overlay 時被誤算為垂直分割線。
  - 多層嵌套 VStack padding 導致清單行距過大。
- **修正**：
  - 最愛地點行改用 0.5 pt 橫向矩形底線，徹底消除中間豎線。
  - 列表行至少 64 pt，面板依內容自適應；Figma B2 的 328 pt 保留為普通字級視覺參考。

### 6. 地圖 Pin 之 Go 按鈕 Disabled 條件錯誤修正（對齊 Location Card）
- **截圖依據**：`IMG_6393`（`206:10371`）
- **Comments**：`206:10371`：「pin 的 Go button disabled條件錯誤, panel 的Go button 可以正常點擊 是正確的」
- **根因**：Pin 上的小型 Go 按鈕綁定了 `search.canGo` 與 `service.canTeleport` 等過度嚴苛之條件，而 Location Card 的 Go 按鈕只檢驗 `service.movementConnectionAvailable`。
- **修正**：
  - Pin Go 與 Location Card Go 共用 `service.canTeleport` 核心允許條件及 `search.canGo` 選點有效性；忙碌／不確定操作顯示 disabled。已接受的 Go 沿用 native session manager 修復一次，移除瞬移外層重試疊加；失敗後顯示連線中斷，取消／配對／身分等錯誤不冒充斷線。

### 7. Location Card 文字與按鈕間隔縮小（對齊 B5）
- **截圖依據**：`IMG_6393`（`206:10371`）
- **Comments**：`206:10371`：「location card text 與 button 中間的間隔太大, 縮小一些」
- **根因**：卡片內固定高 188 pt 且包含無約束的 `Spacer()`，導致經緯度文字與按鈕列間距高達 54 pt。
- **修正**：
  - 標題最多 1 行、地址固定保留 2 行；文字固定上內距 24 pt、按鈕列固定下內距 18 pt，卡片固定高 188 pt，不隨內容增高，地址無論有無／長短都保留兩行高度。這是使用者實機回饋後修訂，未宣稱既有 Figma 已涵蓋兩行地址。

---

## 二、驗收狀態

- **上一版測試回報（非本次驗收）**：曾回報 Core 與 Transport 共 236 項通過；審查重跑時 Core 通過，Transport 有 2 項 loopback socket 環境失敗，不能作為本次全數通過證據。
- **上一版建置回報（非本次驗收）**：曾回報 `xcodebuild` Debug 成功；本次驗證另列於下方。
- **實機安裝交付紀錄**：
  - **安裝時間**：2026-10-23 20:47 (UTC+8)
  - **交付交易**：`setupID: 2e8080ab-afa0-4c0b-9303-057baa1f2102`
  - **裝置與模式**：USB iPhone（`00008130-0010248c04a1401c`），模式 `--mode renew`，Team `48XD59469V`
  - **驗收結果**：
    - `stage: complete`, `outcome: confirmed`, `complete: true`
    - `proof: { installationConfirmed: true, pairingImported: true, supportObserved: true }`
    - `build: "28"`, `expiresAt: "2027-10-17T09:06:10Z"`
    - 保留使用者設定、最愛地點與路線紀錄。

### 本次實機回饋後修正

- 新增要求：編輯最愛名稱輸入框改用較淺的語意灰底（淺色 systemGray6／深色 systemGray4）；只修改此欄位，不調整全域 input token。
- 本次程式驗證：27 項聚焦測試通過（ConnectionRecoveryControllerTests、PointServiceControllerTests、CoreRetryTests），涵蓋取消中的前景補檢與 native busy 後補檢；iOS generic device Debug 未簽署建置成功。僅做所改行為的聚焦測試、建置與 diff 檢查，不追加其他防禦性測試。
- 裝置驗證：使用者已證實上一版存在啟動誤報斷線、兩個 Pill 不一致及 UI 問題；本次修正尚未重新安裝或完成實機驗收。上列 build 28 安裝紀錄不代表本次修正已交付。
