# 06: A：啟動與首次引導

**What to build:** Figma A 區目前存在的 frame（啟動畫面、首次引導、VPN 通道步驟、連線說明、VPN 失敗與 Mac Setup 異常）在 App 完整對齊；R02/R03/R04/R04.a 不顯示頂端步驟 progress UI，R08 identity mismatch 不提供重試按鈕（需 Mac App 修復）。

**Blocked by:** 05.

**Status:** in progress: 2026-10-30 redesign corrections pending software verification

**Assignee hint:** Luna

- [x] A 區每張目前存在的 frame 都有對應 UI fixture 與 Light／Dark 截圖，逐張比對 Figma；R06 無 Figma frame，明列為設計缺口。
- [x] 啟動畫面與 Hero tile 依 Figma 綁 Common Color：Light `common/gray/50`、Dark `common/gray/900`；R01 為 70% primary 進度與 `surface/control` 軌道。此項取代舊「品牌白底／theme control 底」描述。
- [x] 首次引導流程（定位權限 → VPN 通道 → 完成）可走完；VPN 成功後自動進入 B1 並收合 sheet。
- [x] 本票圖示均經 `GoFlyIcon` 使用 Figma『0 · 共用元件（Icon）』資產，沒有 SF Symbol 或自繪替代；R02／R03 Figma 的填色 `icon/location` 不在共用 Icon 板，App 暫用 `icon/nav` 並列為視覺差異。
- [x] 本票所有 Toast／Banner 由票 04 共用 overlay 懸浮，不推動版面。
- [x] **層級（實機回饋）**：Light 背景為 `canvas`（`#EEEEF3`）、清單與卡片為 `surface/card`（`#FBFBFD`）；Dark 為 `#0B0B0D`／`#1A1A1C`；R02、R03、R04、R04.a、R05–R08 已抽查。
- [x] **R05 連線說明精簡版**：返回列置中顯示『連線說明』；一張步驟卡三列單行；前兩列保留 App Store／LocalDevVPN 連結；下方只有一張 troubleshooting 卡與一則提示；移除大標、副標、步驟小字、本機網路權限列與底部 CTA；返回後仍自動重查；三語文案同步。
- [x] 首次引導錯誤為浮動 Toast；VPN 成功無 success Toast，自動進 B1 收合 sheet。
- [x] 本票文字使用系統字型與 `Theme/*` token（`Font.system`），共用圖示經 `GoFlyIcon`；缺漏圖示已列明，無 `Font.custom`、SF Symbol 或自繪替代。
- [x] **截圖驗證**：R01、R02、R03、R04、R04.a、R05、R07、R08 Light／Dark 各有 fixture 截圖並排比對；R06 無 Figma frame，因此未製作虛構截圖。
- [x] 最大 Dynamic Type 與 Reduce Motion 下仍可操作；按鈕命中範圍 ≥ 44 × 44 pt；R05 返回按鈕實際高度 45 pt。
- [x] 相關核心與 UI tests 通過；`app/GoFly/scripts/check.sh` 通過。
- [x] 未改命令、送點、ACK、背景執行語意；未做實機驗證。

## 執行紀錄

### 2026-10-29 執行紀錄（Luna）

- R02／R03／R04／R04.a／R05／R07／R08 Light／Dark fixtures 已有截圖，另有成功後自動進 B1 收合的 `R04-auto-B1-light.png`、`R04-auto-B1-dark.png`；截圖及對照總覽在 `work/gofly-ios-figma04/screenshots/` 與 `index.html`。R05 已精簡三語步驟與提示卡；返回仍觸發既有 VPN 重查。R04 成功後無 success Toast，依使用者確認直接進 B1 收合。
- R04 標題先前比 Figma 下移約 85 pt 且字級／字重不符；已移除多餘垂直留白並對齊 Figma `121:51267` 的 x=16、y=130、361×39 pt、28 pt Semibold。實作由共享 `GoFlyFont.display` 提供；接續 02 票會統一改為 `Font.system` text-style API 並保留 Figma 的 28 pt Semibold 對應。Light／Dark 標題位置由 `testR04TypographyAndPositionMatchFigmaInBothAppearances` 驗證，最新截圖為 `R04-light.png`、`R04-dark.png`。
- R04 `已連線` 靜態 Figma 狀態與自動 B1 行為分開：`R04-connected-light.png`／`R04-connected-dark.png` 是連線狀態截圖；`R04-auto-B1-*` 驗證實際成功導覽。Figma 靜態 frame 仍有檢查 CTA，未修改 Figma。
- R05 移除「本機網路權限」列後，程式中未找到替代的直接系統設定入口，保留為產品待決事項。R06 不在目前 frame catalog；A 區全量逐 frame／最大 Dynamic Type 驗收仍未完成，維持 `in progress`。未做實機驗證。
- 使用者追加 A 區比對項（尚待本票實作／重截）：R01 progress 顏色按 Figma 修正；R04-connected 略過成功 Toast 並在連線成功後直接進入 B1（此行為已依先前決定實作）；R04.a 主按鈕文案改為「重新連線」，英文使用單字 `Reconnect`；R08 依 Figma 04 渲染全面整理 UI。對照截圖放在 `work/gofly-ios-figma04/screenshots/`。

### 2026-10-30 執行紀錄（Luna）

- **完成項目**：依當前 Figma 04 Light／Dark 渲染完成 A 區 R01、R02、R03、R04、R04.a、R05、R07、R08；R01 進度為 70%；R04 標題維持 28 pt `Theme/display` 並對齊 Figma y=130；R04.a 主動作為「重新連線」／`Reconnect`。R02／R03 隱藏 Figma 中不存在的返回列，標題／說明字級分別為 28／15 pt system font；R03 顯示已授權專用標題及狀態 pill。R07 三語內文移除 Figma 未呈現的「安裝 App 後」。R05 為三列步驟卡＋單一提示卡的精簡版，步驟連結保留，返回後自動重查。
- **R02／R03 截圖比對**：`R02-light.png`、`R02-dark.png`、`R03-light.png`、`R03-dark.png` 對照 `work/gofly-ios-figma04/figma/` 同名圖；進度、Hero 位置、標題 y=348、說明 y=400、狀態 pill 約 y=466、底部按鈕位置／寬度及色彩層級一致。剩餘差異是 Hero icon：Figma 畫面用填色 `icon/location`，共用 Icon 板沒有此資產，App 依票 03 使用 `icon/nav`；沒有自行建立或繪製替代圖。
- **逐 frame 比對結論**：R01 Light／Dark 進度與 Hero 底色一致；R02、R03 Light／Dark 除上述缺少共用 location icon 外，位置、字級與層級一致；R04 Light／Dark 標題、清單、狀態及按鈕一致；R04.a Light／Dark 錯誤狀態與 `Reconnect`／「重新連線」一致；R05 Light／Dark 三列、提示卡與返回列一致；R07 Light／Dark 內文按渲染精簡後一致；R08 Light／Dark identity mismatch 狀態與重試動作一致。狀態列時間、訊號及 Dynamic Island 為 simulator／系統 chrome，不納入 Figma App 內容差異。
- **截圖位置**：基準 frame 截圖 `work/gofly-ios-figma04/screenshots/{R01,R02,R03,R04,R04.a,R05,R07,R08}-{light,dark}.png`；定位頁最大字級／Reduce Motion `R02-{light,dark}-xxxl.png`、`R03-{light,dark}-xxxl.png`；R05 最大字級 `R05-{light,dark}-xxxl.png`；R04 成功自動進 B1 `R04-auto-B1-{light,dark}.png`。並排總覽 `work/gofly-ios-figma04/screenshots/index.html`；Figma 渲染在 `work/gofly-ios-figma04/figma/`。
- **驗證**：`testSectionAFramesInBothAppearances`、`testR04TypographyAndPositionMatchFigmaInBothAppearances`、`testR05ConnectionGuideSupportsLargestDynamicTypeInBothAppearances`、`testLocationScreensSupportLargestDynamicTypeInBothAppearances`、`testFirstLaunchVPNSuccessAutomaticallyEntersCollapsedB1WithoutToast`、`testSuccessfulVPNCheckAutomaticallyOpensCollapsedB1MapInBothAppearances`、`testVPNGuideBackAutomaticallyRechecksAndKeepsOnboardingFlow` 均通過。`app/GoFly/scripts/check.sh` 通過（349 tests／58 suites、Native handoff/service tests、unsigned simulator build）；`git diff --check` 通過。
- **Figma 缺口／產品決策**：R06 無目前 Figma frame；R02／R03 共用 Icon 板缺 `icon/location`；R05 移除「本機網路權限」列後程式中沒有直接開啟系統設定的替代入口，保留產品決策待定，沒有保留 Figma 已移除的舊列。Figma R04 靜態畫面保留檢查按鈕；實際 App 依使用者確認在成功後不顯示 Toast，直接進入 B1 並收合 sheet。未修改 Figma。
- **範圍聲明**：只做 simulator／fixture software verification，未做實機驗證；未 commit。

### 2026-10-30 使用者追加 UI 修訂（本輪）

- Figma 04 Light／Dark 已移除 R02、R03、R04、R04.a 的步驟 progress UI；R08 identity mismatch frame 移除底部「重試」按鈕。R08 需要 Mac App 重新安裝／修復，App 不提供手機端重試。
- App `GoFlyOnboardingView` 同步隱藏四張引導頁的進度 UI；`GoFlySetupLockView` 的 identity mismatch 狀態不再顯示 Retry。既有其他可重試 setup failure 狀態維持原行為。
- `app/GoFly/scripts/check.sh` 通過（359 tests／58 suites、Native handoff host tests、unsigned simulator build）。指定 UI XCTest 未進入執行：`CODE_SIGNING_ALLOWED=NO` 的測試 app 缺少 `CFBundleIdentifier`，Xcode 無法讀取 bundle identifier。依使用者要求，此阻礙留待與新項目合併處理；未做實機驗證、未 commit。
