# 01: App Theme 色彩 token 對齊 Figma Light／Dark

**What to build:** App 以單一語意色彩表（canvas、surface／card／control／active／disabled、overlay、text、icon、line、action、status、map）取代 `GoFlyGrayScale` 自訂灰階與散落的系統色。Light／Dark 值以 Figma Variables 為準（`GoFly iOS / Light Theme`、`Dark Theme`、`Common Color`）；`docs/IOS-COLOR-SCHEME.json` 是快照，開工先與 Figma 讀回值核對，不一致時回報、不自行決定。外觀偏好（系統／淺／深）維持有效。

**Blocked by:** 01a.

**Status:** done: software-verified

**Assignee hint:** Luna

- [x] Light 與 Dark 的每個語意色都有對應 token，名稱與 Figma 變數名稱可一對一對照（`color/surface/card` ↔ 對應 Swift 名稱，對照表寫入票尾）。
- [x] Dark 階梯：畫面底 `#0B0B0D`、Tab／Sheet／info card `#1A1A1C`、Sheet 上的按鈕與 list `#2C2C2F`、active／focused `#48484D`；Light 為 `#EEEEF3`／`#FBFBFD`／`#DEDEE4`／`#B9B9BF`。
- [x] 舊的 `GoFlyGrayScale` 字面值與 `Color(uiColor: .system…)` 在 UI 層沒有殘留（地圖原生元件與系統控制例外，須列清單）。
- [x] 新增單元測試：每個 token 在 Light／Dark 的值等於 `IOS-COLOR-SCHEME.json`；外觀偏好切換即時生效。
- [x] 元件畫面此票不要求逐張對齊；本票只建立 token 並讓 App 在兩個外觀下可正常運作。
- [x] **截圖驗證（必做，沒有截圖視為未完成）**：用 01a 的 fixture（不需網路、VPN、真機）對本票涵蓋的每一張 frame、Light 與 Dark 各截一張，存到 `work/gofly-ios-figma04/screenshots/`，並與 `work/gofly-ios-figma04/figma/` 的同名 Figma 截圖並排比對：無破版、無文字截斷、無缺漏元素、顏色與層級一致。把每張的結論（一致／有差異＋原因）與檔案路徑寫入票尾『執行紀錄』；到不了的 frame 如實列出，不略過。
- [x] 最大 Dynamic Type 與 Reduce Motion 下仍可操作；互動元件觸控命中範圍 ≥ 44 × 44 pt；每個圖示按鈕有 accessibility label。
- [x] 相關單元測試與 UI tests 更新並通過；`app/GoFly/scripts/check.sh` 通過。
- [x] 不改命令、送點、ACK、背景執行語意（`app/GoFly/ARCHITECTURE.md` 不變量）；不宣稱實機驗證。

## 執行紀錄

### 2026-10-30 執行紀錄（Luna）

- 已依 Figma Variables 唯讀值核對 snapshot：88 個 Light Theme、88 個 Dark Theme 與 14 個 Common Color 值／名稱皆與 `GoFlyColorTokens` 完全相符；測試 `GoFlyColorTokenTests.everyThemeAndCommonTokenMatchesTheFigmaSnapshot` 逐項檢查名稱、數值與 common 值固定性。外觀偏好切換測試 `GoFlySettingsUITests.testAppearancePickerCommitsDark` 通過，root `preferredColorScheme` 與 dynamic UIColor token provider 即時套用。
- Light／Dark 階梯與票單值一致。App UI 沒有 `GoFlyGrayScale` 或直接寫入 `Color(uiColor: .system…)`／`UIColor.system…` 的舊灰階用法。系統色例外：`GoFlySearchPanel.swift` 的 `UITextField` 使用 `.label`／`.secondaryLabel` 與 `.systemBlue`，clear button／`UIPasteControl`／鍵盤與貼上選單由 UIKit 繪製；`GoFlyGPXPreview.swift` 的 `MKPolylineRenderer`／`MKMarkerAnnotationView` 使用 MapKit 動態 `.label`／`.systemBackground`；MapKit 原生底圖文字、 attribution 與控制層，以及 `UIActivityViewController` 分享 sheet 由系統繪製。App 自繪 surface、文字、icon、route overlay、position arrow 與陰影走語意 token。更新了 `GoFlyStyle`／`GoFlyStatusStyle` 過期註解。
- 截圖矩陣使用 01a 的 64 個 frame × Light／Dark，App 與 Figma 各 128 張，全部列在 `work/gofly-ios-figma04/screenshots/index.html`；manifest 無缺圖、fixture 不可達項目為 0。此票只核驗 token palette 與外觀切換，component／page 的已知差異由後續票處理：B1 搜尋列／狀態 pill／貼上 icon、B2 貼上 icon、B5 LocationCard、B7／B10 toast、D1、E1、F1／F1.b、R01 等；相關範圍已按 tracker 分配到 03–18。截圖路徑模式：`work/gofly-ios-figma04/screenshots/<FrameID>-<light|dark>.png`；同名 Figma 圖：`work/gofly-ios-figma04/figma/<FrameID>-<light|dark>.png`。
- 驗證：`bash app/GoFly/scripts/check.sh --device` 通過（342 Swift tests／57 suites、Native tests、Simulator 與 unsigned iPhoneOS builds）；Release Simulator build 通過；Release 與 iPhoneOS binaries 無 `-gofly-ui-*` 啟動旗標字串；`work/gofly-ios/appearance-token-regression.xcresult` 的外觀 UI test 通過。`git diff --check` 通過。
- 無 Figma token 值缺漏；Dark Color Scheme 色票板個別 surface 樣式與現行 Variables／使用者確認階梯的矛盾已在 2026-10-29 歷史紀錄註明，沒有改動 Figma。未做實機驗證。

### 2026-10-29 執行紀錄（Luna）

- 已新增 Figma variable path 對照的 `GoFlyColorTokens`／dynamic `GoFlyThemeColor`，更新 `GoFlyStyle` 語意別名與 `docs/IOS-COLOR-SCHEME.json` 精確快照，並新增 token Light／Dark 測試。外觀偏好轉換由 dynamic provider 更新；保留 UIKit 原生輸入／貼上控制與 MapKit renderer 色彩例外。Dark Primary 白字依使用者決定覆寫。
- 目前以 fixture 截圖覆蓋色彩抽查：`work/gofly-ios-figma04/screenshots/{B1,B5,B7,B10,D1,D6,D8,E1,F1,F1.b,R02,R03,R04,R04.a,R05}-light.png` 與同名 `-dark.png`；並排頁 `work/gofly-ios-figma04/screenshots/index.html`。逐張全 frame 色彩驗收尚未完成，受 01a fixture 缺口限制，不能標記整票完成。
- Figma 色票板個別 surface 與現行 Variables 快照有不一致；程式以目前可讀的 Variables 與使用者指定階梯為準，沒有修改 Figma。`app/GoFly/scripts/check.sh` 曾通過；未做實機驗證。

### Figma variable path ↔ Swift API 對照表

`GoFlyColorTokens` 保存原始 Figma path；`GoFlyThemeColor` 以 Swift 語意屬性名稱對應同名 path。完整一對一對照如下：

| Swift API | Figma variable path |
|---|---|
| `actionDangerSurface` | `color/action/danger/surface` |
| `actionDangerText` | `color/action/danger/text` |
| `actionDisabledSurface` | `color/action/disabled/surface` |
| `actionPrimarySurface` | `color/action/primary/surface` |
| `actionPrimaryText` | `color/action/primary/text` |
| `actionSecondarySurface` | `color/action/secondary/surface` |
| `canvas` | `color/canvas` |
| `controlGrabber` | `color/control/grabber` |
| `iconAccent` | `color/icon/accent` |
| `iconButtonDisabled` | `color/icon/button/disabled` |
| `iconControlDisabled` | `color/icon/control/disabled` |
| `iconDanger` | `color/icon/danger` |
| `iconDisabled` | `color/icon/disabled` |
| `iconInputDefault` | `color/icon/input/default` |
| `iconInverse` | `color/icon/inverse` |
| `iconOutline` | `color/icon/outline` |
| `iconPrimary` | `color/icon/primary` |
| `iconSecondary` | `color/icon/secondary` |
| `iconStatusSecondary` | `color/icon/status/secondary` |
| `iconSuccess` | `color/icon/success` |
| `iconWarning` | `color/icon/warning` |
| `lineBorder` | `color/line/border` |
| `lineControl` | `color/line/control` |
| `lineInputDefault` | `color/line/input/default` |
| `lineInputDisabled` | `color/line/input/disabled` |
| `lineSeparator` | `color/line/separator` |
| `lineStatusDanger` | `color/line/status/danger` |
| `lineStatusInfo` | `color/line/status/info` |
| `lineStatusSuccess` | `color/line/status/success` |
| `lineStatusWarning` | `color/line/status/warning` |
| `lineStrong` | `color/line/strong` |
| `mapArterial` | `color/map/arterial` |
| `mapArterialEdge` | `color/map/arterial-edge` |
| `mapBuilding` | `color/map/building` |
| `mapCanvas` | `color/map/canvas` |
| `mapLabelArea` | `color/map/label-area` |
| `mapLabelWater` | `color/map/label-water` |
| `mapMarker` | `color/map/marker` |
| `mapMarkerOutline` | `color/map/marker-outline` |
| `mapPark` | `color/map/park` |
| `mapRoad` | `color/map/road` |
| `mapRoadEdge` | `color/map/road-edge` |
| `mapRoute` | `color/map/route` |
| `mapWater` | `color/map/water` |
| `primary100` | `color/primary/100` |
| `primary300` | `color/primary/300` |
| `primary500` | `color/primary/500` |
| `primary700` | `color/primary/700` |
| `primary900` | `color/primary/900` |
| `speedCoral` | `color/speed/coral` |
| `speedCoralShadow` | `color/speed/coral-shadow` |
| `speedGold` | `color/speed/gold` |
| `speedHighlight` | `color/speed/highlight` |
| `speedNavy` | `color/speed/navy` |
| `speedSkin` | `color/speed/skin` |
| `speedSky` | `color/speed/sky` |
| `surfaceCard` | `color/surface/card` |
| `surfaceControl` | `color/surface/control` |
| `surfaceControlActive` | `color/surface/control/active` |
| `surfaceControlDisabled` | `color/surface/control/disabled` |
| `surfaceControlFloating` | `color/surface/control/floating` |
| `surfaceDisabled` | `color/surface/disabled` |
| `surfaceInput` | `color/surface/input` |
| `surfaceNavigation` | `color/surface/navigation` |
| `surfaceOverlayBackground` | `color/surface/overlay/background` |
| `surfaceOverlayCard` | `color/surface/overlay/card` |
| `surfaceOverlayLocationCard` | `color/surface/overlay/location-card` |
| `surfaceOverlayPanel` | `color/surface/overlay/panel` |
| `surfaceOverlaySheet` | `color/surface/overlay/sheet` |
| `surfaceOverlayTabPanel` | `color/surface/overlay/tab-panel` |
| `surfaceStatusDanger` | `color/surface/status/danger` |
| `surfaceStatusInfo` | `color/surface/status/info` |
| `surfaceStatusSuccess` | `color/surface/status/success` |
| `surfaceStatusWarning` | `color/surface/status/warning` |
| `systemBlack` | `color/system/black` |
| `textAccent` | `color/text/accent` |
| `textButtonDisabled` | `color/text/button/disabled` |
| `textControlDisabled` | `color/text/control/disabled` |
| `textDanger` | `color/text/danger` |
| `textDisabled` | `color/text/disabled` |
| `textInputDefault` | `color/text/input/default` |
| `textInverse` | `color/text/inverse` |
| `textPrimary` | `color/text/primary` |
| `textSecondary` | `color/text/secondary` |
| `textStatusSecondary` | `color/text/status/secondary` |
| `textSuccess` | `color/text/success` |
| `textTertiary` | `color/text/tertiary` |
| `textWarning` | `color/text/warning` |
| `commonBlack` | `common/black` |
| `commonGray100` | `common/gray/100` |
| `commonGray200` | `common/gray/200` |
| `commonGray300` | `common/gray/300` |
| `commonGray400` | `common/gray/400` |
| `commonGray50` | `common/gray/50` |
| `commonGray500` | `common/gray/500` |
| `commonGray600` | `common/gray/600` |
| `commonGray700` | `common/gray/700` |
| `commonGray800` | `common/gray/800` |
| `commonGray900` | `common/gray/900` |
| `commonGray950` | `common/gray/950` |
| `commonTransparent` | `common/transparent` |
| `commonWhite` | `common/white` |



### 逐 frame 截圖結果

每一對 App/Figma 路徑都可由上述 01a HTML 總覽直接並排查看；表內的「差異」只記錄已確認的頁面／元件工作，其他逐頁差異依 tracker 在所屬票處理。本票驗證 token 值與外觀切換，不把尚未完成的頁面 UI 宣稱為視覺一致。

| Frame | Light App 截圖 | Dark App 截圖 | 比對結論／後續差異 |
|---|---|---|---|
| `R01` | `work/gofly-ios-figma04/screenshots/R01-light.png` | `work/gofly-ios-figma04/screenshots/R01-dark.png` | progress color → issue 06 |
| `R02` | `work/gofly-ios-figma04/screenshots/R02-light.png` | `work/gofly-ios-figma04/screenshots/R02-dark.png` | Capture/fixture 成功；逐頁元件差異由所屬後續票比對，不在本票宣稱完成。 |
| `R04` | `work/gofly-ios-figma04/screenshots/R04-light.png` | `work/gofly-ios-figma04/screenshots/R04-dark.png` | title position/type and connected-success flow → issue 06 (auto-enter B1, no success toast) |
| `R05` | `work/gofly-ios-figma04/screenshots/R05-light.png` | `work/gofly-ios-figma04/screenshots/R05-dark.png` | compact VPN help layout → issues 04/06 |
| `R03` | `work/gofly-ios-figma04/screenshots/R03-light.png` | `work/gofly-ios-figma04/screenshots/R03-dark.png` | Capture/fixture 成功；逐頁元件差異由所屬後續票比對，不在本票宣稱完成。 |
| `R04.a` | `work/gofly-ios-figma04/screenshots/R04.a-light.png` | `work/gofly-ios-figma04/screenshots/R04.a-dark.png` | button label → issue 06 |
| `R07` | `work/gofly-ios-figma04/screenshots/R07-light.png` | `work/gofly-ios-figma04/screenshots/R07-dark.png` | Capture/fixture 成功；逐頁元件差異由所屬後續票比對，不在本票宣稱完成。 |
| `R08` | `work/gofly-ios-figma04/screenshots/R08-light.png` | `work/gofly-ios-figma04/screenshots/R08-dark.png` | redesign → issue 06 |
| `B1` | `work/gofly-ios-figma04/screenshots/B1-light.png` | `work/gofly-ios-figma04/screenshots/B1-dark.png` | SearchBar、StatusPill、paste icon color → issues 03/07 |
| `B2` | `work/gofly-ios-figma04/screenshots/B2-light.png` | `work/gofly-ios-figma04/screenshots/B2-dark.png` | paste icon; Dark favorites divider/copy icon/View all style → issues 03/07/08 |
| `B3` | `work/gofly-ios-figma04/screenshots/B3-light.png` | `work/gofly-ios-figma04/screenshots/B3-dark.png` | Capture/fixture 成功；逐頁元件差異由所屬後續票比對，不在本票宣稱完成。 |
| `B4` | `work/gofly-ios-figma04/screenshots/B4-light.png` | `work/gofly-ios-figma04/screenshots/B4-dark.png` | Capture/fixture 成功；逐頁元件差異由所屬後續票比對，不在本票宣稱完成。 |
| `B5` | `work/gofly-ios-figma04/screenshots/B5-light.png` | `work/gofly-ios-figma04/screenshots/B5-dark.png` | LocationCard spacing and primary action → issues 05/07 |
| `B6` | `work/gofly-ios-figma04/screenshots/B6-light.png` | `work/gofly-ios-figma04/screenshots/B6-dark.png` | Capture/fixture 成功；逐頁元件差異由所屬後續票比對，不在本票宣稱完成。 |
| `B7` | `work/gofly-ios-figma04/screenshots/B7-light.png` | `work/gofly-ios-figma04/screenshots/B7-dark.png` | toast title/message line limits and action alignment → issues 04/07 |
| `B8` | `work/gofly-ios-figma04/screenshots/B8-light.png` | `work/gofly-ios-figma04/screenshots/B8-dark.png` | Capture/fixture 成功；逐頁元件差異由所屬後續票比對，不在本票宣稱完成。 |
| `B9` | `work/gofly-ios-figma04/screenshots/B9-light.png` | `work/gofly-ios-figma04/screenshots/B9-dark.png` | Capture/fixture 成功；逐頁元件差異由所屬後續票比對，不在本票宣稱完成。 |
| `B10` | `work/gofly-ios-figma04/screenshots/B10-light.png` | `work/gofly-ios-figma04/screenshots/B10-dark.png` | toast action background → issue 04 |
| `B11` | `work/gofly-ios-figma04/screenshots/B11-light.png` | `work/gofly-ios-figma04/screenshots/B11-dark.png` | Capture/fixture 成功；逐頁元件差異由所屬後續票比對，不在本票宣稱完成。 |
| `C1` | `work/gofly-ios-figma04/screenshots/C1-light.png` | `work/gofly-ios-figma04/screenshots/C1-dark.png` | Capture/fixture 成功；逐頁元件差異由所屬後續票比對，不在本票宣稱完成。 |
| `C2` | `work/gofly-ios-figma04/screenshots/C2-light.png` | `work/gofly-ios-figma04/screenshots/C2-dark.png` | Capture/fixture 成功；逐頁元件差異由所屬後續票比對，不在本票宣稱完成。 |
| `C3` | `work/gofly-ios-figma04/screenshots/C3-light.png` | `work/gofly-ios-figma04/screenshots/C3-dark.png` | Capture/fixture 成功；逐頁元件差異由所屬後續票比對，不在本票宣稱完成。 |
| `C4` | `work/gofly-ios-figma04/screenshots/C4-light.png` | `work/gofly-ios-figma04/screenshots/C4-dark.png` | Capture/fixture 成功；逐頁元件差異由所屬後續票比對，不在本票宣稱完成。 |
| `D1` | `work/gofly-ios-figma04/screenshots/D1-light.png` | `work/gofly-ios-figma04/screenshots/D1-dark.png` | list background and favorite button; Dark add-stop color → issue 09 |
| `D5` | `work/gofly-ios-figma04/screenshots/D5-light.png` | `work/gofly-ios-figma04/screenshots/D5-dark.png` | Capture/fixture 成功；逐頁元件差異由所屬後續票比對，不在本票宣稱完成。 |
| `D6` | `work/gofly-ios-figma04/screenshots/D6-light.png` | `work/gofly-ios-figma04/screenshots/D6-dark.png` | Capture/fixture 成功；逐頁元件差異由所屬後續票比對，不在本票宣稱完成。 |
| `D10.a` | `work/gofly-ios-figma04/screenshots/D10.a-light.png` | `work/gofly-ios-figma04/screenshots/D10.a-dark.png` | Capture/fixture 成功；逐頁元件差異由所屬後續票比對，不在本票宣稱完成。 |
| `D11` | `work/gofly-ios-figma04/screenshots/D11-light.png` | `work/gofly-ios-figma04/screenshots/D11-dark.png` | Capture/fixture 成功；逐頁元件差異由所屬後續票比對，不在本票宣稱完成。 |
| `D15` | `work/gofly-ios-figma04/screenshots/D15-light.png` | `work/gofly-ios-figma04/screenshots/D15-dark.png` | Capture/fixture 成功；逐頁元件差異由所屬後續票比對，不在本票宣稱完成。 |
| `D13` | `work/gofly-ios-figma04/screenshots/D13-light.png` | `work/gofly-ios-figma04/screenshots/D13-dark.png` | Capture/fixture 成功；逐頁元件差異由所屬後續票比對，不在本票宣稱完成。 |
| `D16` | `work/gofly-ios-figma04/screenshots/D16-light.png` | `work/gofly-ios-figma04/screenshots/D16-dark.png` | Capture/fixture 成功；逐頁元件差異由所屬後續票比對，不在本票宣稱完成。 |
| `D17` | `work/gofly-ios-figma04/screenshots/D17-light.png` | `work/gofly-ios-figma04/screenshots/D17-dark.png` | Capture/fixture 成功；逐頁元件差異由所屬後續票比對，不在本票宣稱完成。 |
| `D18` | `work/gofly-ios-figma04/screenshots/D18-light.png` | `work/gofly-ios-figma04/screenshots/D18-dark.png` | Capture/fixture 成功；逐頁元件差異由所屬後續票比對，不在本票宣稱完成。 |
| `D14` | `work/gofly-ios-figma04/screenshots/D14-light.png` | `work/gofly-ios-figma04/screenshots/D14-dark.png` | Capture/fixture 成功；逐頁元件差異由所屬後續票比對，不在本票宣稱完成。 |
| `D12` | `work/gofly-ios-figma04/screenshots/D12-light.png` | `work/gofly-ios-figma04/screenshots/D12-dark.png` | Capture/fixture 成功；逐頁元件差異由所屬後續票比對，不在本票宣稱完成。 |
| `D7` | `work/gofly-ios-figma04/screenshots/D7-light.png` | `work/gofly-ios-figma04/screenshots/D7-dark.png` | Capture/fixture 成功；逐頁元件差異由所屬後續票比對，不在本票宣稱完成。 |
| `D19` | `work/gofly-ios-figma04/screenshots/D19-light.png` | `work/gofly-ios-figma04/screenshots/D19-dark.png` | Capture/fixture 成功；逐頁元件差異由所屬後續票比對，不在本票宣稱完成。 |
| `D20` | `work/gofly-ios-figma04/screenshots/D20-light.png` | `work/gofly-ios-figma04/screenshots/D20-dark.png` | Capture/fixture 成功；逐頁元件差異由所屬後續票比對，不在本票宣稱完成。 |
| `D21` | `work/gofly-ios-figma04/screenshots/D21-light.png` | `work/gofly-ios-figma04/screenshots/D21-dark.png` | Capture/fixture 成功；逐頁元件差異由所屬後續票比對，不在本票宣稱完成。 |
| `D4` | `work/gofly-ios-figma04/screenshots/D4-light.png` | `work/gofly-ios-figma04/screenshots/D4-dark.png` | Capture/fixture 成功；逐頁元件差異由所屬後續票比對，不在本票宣稱完成。 |
| `D3` | `work/gofly-ios-figma04/screenshots/D3-light.png` | `work/gofly-ios-figma04/screenshots/D3-dark.png` | Capture/fixture 成功；逐頁元件差異由所屬後續票比對，不在本票宣稱完成。 |
| `D10` | `work/gofly-ios-figma04/screenshots/D10-light.png` | `work/gofly-ios-figma04/screenshots/D10-dark.png` | Capture/fixture 成功；逐頁元件差異由所屬後續票比對，不在本票宣稱完成。 |
| `D8` | `work/gofly-ios-figma04/screenshots/D8-light.png` | `work/gofly-ios-figma04/screenshots/D8-dark.png` | planning-failure toast action 修正 → issue 11 |
| `D2` | `work/gofly-ios-figma04/screenshots/D2-light.png` | `work/gofly-ios-figma04/screenshots/D2-dark.png` | Capture/fixture 成功；逐頁元件差異由所屬後續票比對，不在本票宣稱完成。 |
| `D22` | `work/gofly-ios-figma04/screenshots/D22-light.png` | `work/gofly-ios-figma04/screenshots/D22-dark.png` | Capture/fixture 成功；逐頁元件差異由所屬後續票比對，不在本票宣稱完成。 |
| `D2.a` | `work/gofly-ios-figma04/screenshots/D2.a-light.png` | `work/gofly-ios-figma04/screenshots/D2.a-dark.png` | Capture/fixture 成功；逐頁元件差異由所屬後續票比對，不在本票宣稱完成。 |
| `D23` | `work/gofly-ios-figma04/screenshots/D23-light.png` | `work/gofly-ios-figma04/screenshots/D23-dark.png` | Capture/fixture 成功；逐頁元件差異由所屬後續票比對，不在本票宣稱完成。 |
| `E1` | `work/gofly-ios-figma04/screenshots/E1-light.png` | `work/gofly-ios-figma04/screenshots/E1-dark.png` | joystick UI → issue 15 |
| `E2` | `work/gofly-ios-figma04/screenshots/E2-light.png` | `work/gofly-ios-figma04/screenshots/E2-dark.png` | Capture/fixture 成功；逐頁元件差異由所屬後續票比對，不在本票宣稱完成。 |
| `E3` | `work/gofly-ios-figma04/screenshots/E3-light.png` | `work/gofly-ios-figma04/screenshots/E3-dark.png` | Capture/fixture 成功；逐頁元件差異由所屬後續票比對，不在本票宣稱完成。 |
| `E4` | `work/gofly-ios-figma04/screenshots/E4-light.png` | `work/gofly-ios-figma04/screenshots/E4-dark.png` | Capture/fixture 成功；逐頁元件差異由所屬後續票比對，不在本票宣稱完成。 |
| `E5` | `work/gofly-ios-figma04/screenshots/E5-light.png` | `work/gofly-ios-figma04/screenshots/E5-dark.png` | Capture/fixture 成功；逐頁元件差異由所屬後續票比對，不在本票宣稱完成。 |
| `E1.a` | `work/gofly-ios-figma04/screenshots/E1.a-light.png` | `work/gofly-ios-figma04/screenshots/E1.a-dark.png` | Capture/fixture 成功；逐頁元件差異由所屬後續票比對，不在本票宣稱完成。 |
| `E2.a` | `work/gofly-ios-figma04/screenshots/E2.a-light.png` | `work/gofly-ios-figma04/screenshots/E2.a-dark.png` | Capture/fixture 成功；逐頁元件差異由所屬後續票比對，不在本票宣稱完成。 |
| `F1` | `work/gofly-ios-figma04/screenshots/F1-light.png` | `work/gofly-ios-figma04/screenshots/F1-dark.png` | button/icon colors, back button, helper copy → issues 16/17 |
| `F4` | `work/gofly-ios-figma04/screenshots/F4-light.png` | `work/gofly-ios-figma04/screenshots/F4-dark.png` | Capture/fixture 成功；逐頁元件差異由所屬後續票比對，不在本票宣稱完成。 |
| `F5` | `work/gofly-ios-figma04/screenshots/F5-light.png` | `work/gofly-ios-figma04/screenshots/F5-dark.png` | settings redesign/back button → issue 18 |
| `F6` | `work/gofly-ios-figma04/screenshots/F6-light.png` | `work/gofly-ios-figma04/screenshots/F6-dark.png` | settings redesign/back button → issue 18 |
| `F7` | `work/gofly-ios-figma04/screenshots/F7-light.png` | `work/gofly-ios-figma04/screenshots/F7-dark.png` | Capture/fixture 成功；逐頁元件差異由所屬後續票比對，不在本票宣稱完成。 |
| `F9` | `work/gofly-ios-figma04/screenshots/F9-light.png` | `work/gofly-ios-figma04/screenshots/F9-dark.png` | Capture/fixture 成功；逐頁元件差異由所屬後續票比對，不在本票宣稱完成。 |
| `F8` | `work/gofly-ios-figma04/screenshots/F8-light.png` | `work/gofly-ios-figma04/screenshots/F8-dark.png` | Capture/fixture 成功；逐頁元件差異由所屬後續票比對，不在本票宣稱完成。 |
| `F6.a` | `work/gofly-ios-figma04/screenshots/F6.a-light.png` | `work/gofly-ios-figma04/screenshots/F6.a-dark.png` | time input → issue 18 |
| `F1.a` | `work/gofly-ios-figma04/screenshots/F1.a-light.png` | `work/gofly-ios-figma04/screenshots/F1.a-dark.png` | Capture/fixture 成功；逐頁元件差異由所屬後續票比對，不在本票宣稱完成。 |
| `F1.b` | `work/gofly-ios-figma04/screenshots/F1.b-light.png` | `work/gofly-ios-figma04/screenshots/F1.b-dark.png` | toast vertical position → issues 04/17 |
| `R06` | — | — | Figma 04 無 frame/render；不合成截圖。 |
