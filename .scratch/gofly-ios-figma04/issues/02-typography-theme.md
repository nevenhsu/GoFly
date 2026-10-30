# 02: 文字樣式對齊 Figma Theme/*

**What to build:** `GoFlyFont` 16 個字級 token（14 個核心樣式＋`button/medium`、`button/small`）與 `GoFlyTextColor` 9 個語意文字色值對齊 Figma `Theme/*`；其中 `inverse`／`onDark` 是同一白色 token 的兩個用途別名。文字使用 `Font.system`，以 Figma 基準點數套用相應 Dynamic Type 縮放（`micro`、`metric` 固定）。

**Blocked by:** 01.

**Status:** done: software-verified

**Assignee hint:** Luna

- [x] **字型一律使用系統字型 `Font.system`**：所有文字（含 `GoFlyFont` 16 個 token、按鈕、Toast、輸入欄、Tab Bar 標籤、地圖標註以外的 UI）都由 `Font.system(...)`（或等價的系統 text style，如 `.body`、`.footnote`）取得，字級與字重依 Figma `Theme/*`；不得使用 `Font.custom`、任何字型檔或字型名稱字串。Figma 的 PingFang TC 即 iOS 系統中文字型，由系統字型自動對應。新增測試／靜態檢查：UI 原始碼沒有 `Font.custom`、`UIFont(name:`、`.custom(`。
- [x] 字級、字重與 `docs/IOS-TYPOGRAPHY.md` 表格一致；只使用 Regular／Semibold。
- [x] 文字色全部走 01 的 token；沒有 View 直接寫字級或顏色字面值。
- [x] `TypographyStandardTests` 更新並通過。
- [x] **截圖驗證（必做，沒有截圖視為未完成）**：用 01a fixture 為每張可達 frame 截 Light／Dark，並逐張與同名 Figma frame 並排；本票比對字級、字重與文字換行。顏色、圖示、文案與頁面結構的差異記到所屬頁面票，不以尚未完成頁票阻擋共用字級 token。逐張結果與路徑列於執行紀錄。
- [x] Accessibility XXXL 下文字縮放及代表性互動控制通過 UI test；MapCanvas／JoystickPanel 保留 Reduce Motion guard；已驗證的互動命中區 ≥ 44 × 44 pt、圖示按鈕具 accessibility label。
- [x] 相關單元測試與 UI tests 更新並通過；`app/GoFly/scripts/check.sh` 通過。
- [x] 不改命令、送點、ACK、背景執行語意（`app/GoFly/ARCHITECTURE.md` 不變量）；不宣稱實機驗證。

## 執行紀錄

### 2026-10-30 執行紀錄（Luna）

- 依 Figma 04 Typography 樣式板（只讀）建立 16 個 `GoFlyFont` token：14 個核心樣式與 `button/medium`／`button/small`。共用 `GoFlyFontModifier` 以 Figma 基準 pt、`Font.system` 與 `@ScaledMetric(relativeTo:)` 提供對應 Dynamic Type 縮放；`micro`、`metric` 固定。App 文字使用 `.goFlyFont(GoFlyFont.<token>)`，圖示仍可用 system glyph 字體，後續票 03 會按 Figma icon 資產替換。
- `GoFlyTextColor` 的 9 個語意色值映射到 01 Theme token；`inverse`／`onDark` 是同一 `common/white` 的用途別名。刪除舊文件中已過期、與 01 語意色票衝突的灰階表，改引用 `docs/IOS-COLOR-SCHEME.json`。
- 新增靜態測試檢查 16 個 token、pt／字重／Dynamic Type 對應、9 個文字色值、自訂字型 API、原生字級與 token modifier。`TypographyStandardTests`：7 tests passed；`check.sh`：346 tests／57 suites passed、Native host tests passed、iOS Simulator Debug build passed。UI 截圖測試 `testCaptureSupportedFigmaFramesInBothAppearances`：64 frames × Light／Dark、128 captures、0 failures；Accessibility XXXL onboarding／執行控制 UI tests：2 tests、0 failures。
- 截圖與 Figma 同名渲染各 128 張，manifest 配對完整、不可達 frame 為 0；並排總覽：`work/gofly-ios-figma04/screenshots/index.html`。測試結果：`work/gofly-ios/02-typography-frames.xcresult`、`work/gofly-ios/02-typography-accessibility.xcresult`；check log：`work/gofly-ios/02-typography-check.log`。
- 視覺抽查：R04 Light 標題使用 28 pt Semibold，和 Figma `Theme/display` 的位置／大小相符；R05 Light 已呈現三列步驟及單張提示卡，字級與行數接近 Figma，導覽列細部間距由票 06 收尾。B1 Dark 的 SearchBar 目前仍用 17 pt `body`，Figma 使用 15 pt `subheadline`；列在票 07 的 SearchBar 比對項。B1 Dark 地圖 fixture 標註密度、面板、SearchBar／StatusPill／paste 顏色等差異列在票 05／07；其他畫面差異由下表所列票逐頁修正。本票不宣稱尚未完成的頁面已整體視覺一致。
- Accessibility XXXL 下 onboarding、搖桿與執行控制可見並可操作；搖桿及執行按鈕命中高度由 UI test 驗證。MapCanvas／JoystickPanel 仍讀取 `accessibilityReduceMotion` 並抑制動畫；本輪未更動動態效果，Simulator UI 沒有 Reduce Motion 設定項可直接切換測試。Figma 維持只讀，未做實機驗證，未 commit。
- R06 沒有目前 Figma 04 frame／渲染，不納入 64 frame catalog；Dark · B11 在現行渲染有 frame、但與舊票 00 記錄衝突，見 01a 執行紀錄。以下每列列出 App 與 Figma Light／Dark 實際檔案路徑；整頁差異依 A–F owner ticket 追蹤。

| Frame | App Light | App Dark | Figma Light | Figma Dark | 比對結論 |
| :-- | :-- | :-- | :-- | :-- | :-- |
| `R01` | `work/gofly-ios-figma04/screenshots/R01-light.png` | `work/gofly-ios-figma04/screenshots/R01-dark.png` | `work/gofly-ios-figma04/figma/R01-light.png` | `work/gofly-ios-figma04/figma/R01-dark.png` | 已擷取／配對；整頁剩餘差異由票 06 逐頁修正。 |
| `R02` | `work/gofly-ios-figma04/screenshots/R02-light.png` | `work/gofly-ios-figma04/screenshots/R02-dark.png` | `work/gofly-ios-figma04/figma/R02-light.png` | `work/gofly-ios-figma04/figma/R02-dark.png` | 已擷取／配對；整頁剩餘差異由票 06 逐頁修正。 |
| `R04` | `work/gofly-ios-figma04/screenshots/R04-light.png` | `work/gofly-ios-figma04/screenshots/R04-dark.png` | `work/gofly-ios-figma04/figma/R04-light.png` | `work/gofly-ios-figma04/figma/R04-dark.png` | 已擷取／配對；整頁剩餘差異由票 06 逐頁修正。 |
| `R05` | `work/gofly-ios-figma04/screenshots/R05-light.png` | `work/gofly-ios-figma04/screenshots/R05-dark.png` | `work/gofly-ios-figma04/figma/R05-light.png` | `work/gofly-ios-figma04/figma/R05-dark.png` | 已擷取／配對；整頁剩餘差異由票 06 逐頁修正。 |
| `R03` | `work/gofly-ios-figma04/screenshots/R03-light.png` | `work/gofly-ios-figma04/screenshots/R03-dark.png` | `work/gofly-ios-figma04/figma/R03-light.png` | `work/gofly-ios-figma04/figma/R03-dark.png` | 已擷取／配對；整頁剩餘差異由票 06 逐頁修正。 |
| `R04.a` | `work/gofly-ios-figma04/screenshots/R04.a-light.png` | `work/gofly-ios-figma04/screenshots/R04.a-dark.png` | `work/gofly-ios-figma04/figma/R04.a-light.png` | `work/gofly-ios-figma04/figma/R04.a-dark.png` | 已擷取／配對；整頁剩餘差異由票 06 逐頁修正。 |
| `R07` | `work/gofly-ios-figma04/screenshots/R07-light.png` | `work/gofly-ios-figma04/screenshots/R07-dark.png` | `work/gofly-ios-figma04/figma/R07-light.png` | `work/gofly-ios-figma04/figma/R07-dark.png` | 已擷取／配對；整頁剩餘差異由票 06 逐頁修正。 |
| `R08` | `work/gofly-ios-figma04/screenshots/R08-light.png` | `work/gofly-ios-figma04/screenshots/R08-dark.png` | `work/gofly-ios-figma04/figma/R08-light.png` | `work/gofly-ios-figma04/figma/R08-dark.png` | 已擷取／配對；整頁剩餘差異由票 06 逐頁修正。 |
| `B1` | `work/gofly-ios-figma04/screenshots/B1-light.png` | `work/gofly-ios-figma04/screenshots/B1-dark.png` | `work/gofly-ios-figma04/figma/B1-light.png` | `work/gofly-ios-figma04/figma/B1-dark.png` | 已擷取／配對；整頁剩餘差異由票 07（共享地圖底層另見 05） 逐頁修正。 |
| `B2` | `work/gofly-ios-figma04/screenshots/B2-light.png` | `work/gofly-ios-figma04/screenshots/B2-dark.png` | `work/gofly-ios-figma04/figma/B2-light.png` | `work/gofly-ios-figma04/figma/B2-dark.png` | 已擷取／配對；整頁剩餘差異由票 07（共享地圖底層另見 05） 逐頁修正。 |
| `B3` | `work/gofly-ios-figma04/screenshots/B3-light.png` | `work/gofly-ios-figma04/screenshots/B3-dark.png` | `work/gofly-ios-figma04/figma/B3-light.png` | `work/gofly-ios-figma04/figma/B3-dark.png` | 已擷取／配對；整頁剩餘差異由票 07（共享地圖底層另見 05） 逐頁修正。 |
| `B4` | `work/gofly-ios-figma04/screenshots/B4-light.png` | `work/gofly-ios-figma04/screenshots/B4-dark.png` | `work/gofly-ios-figma04/figma/B4-light.png` | `work/gofly-ios-figma04/figma/B4-dark.png` | 已擷取／配對；整頁剩餘差異由票 07（共享地圖底層另見 05） 逐頁修正。 |
| `B5` | `work/gofly-ios-figma04/screenshots/B5-light.png` | `work/gofly-ios-figma04/screenshots/B5-dark.png` | `work/gofly-ios-figma04/figma/B5-light.png` | `work/gofly-ios-figma04/figma/B5-dark.png` | 已擷取／配對；整頁剩餘差異由票 07（共享地圖底層另見 05） 逐頁修正。 |
| `B6` | `work/gofly-ios-figma04/screenshots/B6-light.png` | `work/gofly-ios-figma04/screenshots/B6-dark.png` | `work/gofly-ios-figma04/figma/B6-light.png` | `work/gofly-ios-figma04/figma/B6-dark.png` | 已擷取／配對；整頁剩餘差異由票 07（共享地圖底層另見 05） 逐頁修正。 |
| `B7` | `work/gofly-ios-figma04/screenshots/B7-light.png` | `work/gofly-ios-figma04/screenshots/B7-dark.png` | `work/gofly-ios-figma04/figma/B7-light.png` | `work/gofly-ios-figma04/figma/B7-dark.png` | 已擷取／配對；整頁剩餘差異由票 07（共享地圖底層另見 05） 逐頁修正。 |
| `B8` | `work/gofly-ios-figma04/screenshots/B8-light.png` | `work/gofly-ios-figma04/screenshots/B8-dark.png` | `work/gofly-ios-figma04/figma/B8-light.png` | `work/gofly-ios-figma04/figma/B8-dark.png` | 已擷取／配對；整頁剩餘差異由票 07（共享地圖底層另見 05） 逐頁修正。 |
| `B9` | `work/gofly-ios-figma04/screenshots/B9-light.png` | `work/gofly-ios-figma04/screenshots/B9-dark.png` | `work/gofly-ios-figma04/figma/B9-light.png` | `work/gofly-ios-figma04/figma/B9-dark.png` | 已擷取／配對；整頁剩餘差異由票 07（共享地圖底層另見 05） 逐頁修正。 |
| `B10` | `work/gofly-ios-figma04/screenshots/B10-light.png` | `work/gofly-ios-figma04/screenshots/B10-dark.png` | `work/gofly-ios-figma04/figma/B10-light.png` | `work/gofly-ios-figma04/figma/B10-dark.png` | 已擷取／配對；整頁剩餘差異由票 07（共享地圖底層另見 05） 逐頁修正。 |
| `B11` | `work/gofly-ios-figma04/screenshots/B11-light.png` | `work/gofly-ios-figma04/screenshots/B11-dark.png` | `work/gofly-ios-figma04/figma/B11-light.png` | `work/gofly-ios-figma04/figma/B11-dark.png` | 已擷取／配對；整頁剩餘差異由票 07（共享地圖底層另見 05） 逐頁修正。 |
| `C1` | `work/gofly-ios-figma04/screenshots/C1-light.png` | `work/gofly-ios-figma04/screenshots/C1-dark.png` | `work/gofly-ios-figma04/figma/C1-light.png` | `work/gofly-ios-figma04/figma/C1-dark.png` | 已擷取／配對；整頁剩餘差異由票 08 逐頁修正。 |
| `C2` | `work/gofly-ios-figma04/screenshots/C2-light.png` | `work/gofly-ios-figma04/screenshots/C2-dark.png` | `work/gofly-ios-figma04/figma/C2-light.png` | `work/gofly-ios-figma04/figma/C2-dark.png` | 已擷取／配對；整頁剩餘差異由票 08 逐頁修正。 |
| `C3` | `work/gofly-ios-figma04/screenshots/C3-light.png` | `work/gofly-ios-figma04/screenshots/C3-dark.png` | `work/gofly-ios-figma04/figma/C3-light.png` | `work/gofly-ios-figma04/figma/C3-dark.png` | 已擷取／配對；整頁剩餘差異由票 08 逐頁修正。 |
| `C4` | `work/gofly-ios-figma04/screenshots/C4-light.png` | `work/gofly-ios-figma04/screenshots/C4-dark.png` | `work/gofly-ios-figma04/figma/C4-light.png` | `work/gofly-ios-figma04/figma/C4-dark.png` | 已擷取／配對；整頁剩餘差異由票 08 逐頁修正。 |
| `D1` | `work/gofly-ios-figma04/screenshots/D1-light.png` | `work/gofly-ios-figma04/screenshots/D1-dark.png` | `work/gofly-ios-figma04/figma/D1-light.png` | `work/gofly-ios-figma04/figma/D1-dark.png` | 已擷取／配對；整頁剩餘差異由票 09–14 逐頁修正。 |
| `D5` | `work/gofly-ios-figma04/screenshots/D5-light.png` | `work/gofly-ios-figma04/screenshots/D5-dark.png` | `work/gofly-ios-figma04/figma/D5-light.png` | `work/gofly-ios-figma04/figma/D5-dark.png` | 已擷取／配對；整頁剩餘差異由票 09–14 逐頁修正。 |
| `D6` | `work/gofly-ios-figma04/screenshots/D6-light.png` | `work/gofly-ios-figma04/screenshots/D6-dark.png` | `work/gofly-ios-figma04/figma/D6-light.png` | `work/gofly-ios-figma04/figma/D6-dark.png` | 已擷取／配對；整頁剩餘差異由票 09–14 逐頁修正。 |
| `D10.a` | `work/gofly-ios-figma04/screenshots/D10.a-light.png` | `work/gofly-ios-figma04/screenshots/D10.a-dark.png` | `work/gofly-ios-figma04/figma/D10.a-light.png` | `work/gofly-ios-figma04/figma/D10.a-dark.png` | 已擷取／配對；整頁剩餘差異由票 09–14 逐頁修正。 |
| `D11` | `work/gofly-ios-figma04/screenshots/D11-light.png` | `work/gofly-ios-figma04/screenshots/D11-dark.png` | `work/gofly-ios-figma04/figma/D11-light.png` | `work/gofly-ios-figma04/figma/D11-dark.png` | 已擷取／配對；整頁剩餘差異由票 09–14 逐頁修正。 |
| `D15` | `work/gofly-ios-figma04/screenshots/D15-light.png` | `work/gofly-ios-figma04/screenshots/D15-dark.png` | `work/gofly-ios-figma04/figma/D15-light.png` | `work/gofly-ios-figma04/figma/D15-dark.png` | 已擷取／配對；整頁剩餘差異由票 09–14 逐頁修正。 |
| `D13` | `work/gofly-ios-figma04/screenshots/D13-light.png` | `work/gofly-ios-figma04/screenshots/D13-dark.png` | `work/gofly-ios-figma04/figma/D13-light.png` | `work/gofly-ios-figma04/figma/D13-dark.png` | 已擷取／配對；整頁剩餘差異由票 09–14 逐頁修正。 |
| `D16` | `work/gofly-ios-figma04/screenshots/D16-light.png` | `work/gofly-ios-figma04/screenshots/D16-dark.png` | `work/gofly-ios-figma04/figma/D16-light.png` | `work/gofly-ios-figma04/figma/D16-dark.png` | 已擷取／配對；整頁剩餘差異由票 09–14 逐頁修正。 |
| `D17` | `work/gofly-ios-figma04/screenshots/D17-light.png` | `work/gofly-ios-figma04/screenshots/D17-dark.png` | `work/gofly-ios-figma04/figma/D17-light.png` | `work/gofly-ios-figma04/figma/D17-dark.png` | 已擷取／配對；整頁剩餘差異由票 09–14 逐頁修正。 |
| `D18` | `work/gofly-ios-figma04/screenshots/D18-light.png` | `work/gofly-ios-figma04/screenshots/D18-dark.png` | `work/gofly-ios-figma04/figma/D18-light.png` | `work/gofly-ios-figma04/figma/D18-dark.png` | 已擷取／配對；整頁剩餘差異由票 09–14 逐頁修正。 |
| `D14` | `work/gofly-ios-figma04/screenshots/D14-light.png` | `work/gofly-ios-figma04/screenshots/D14-dark.png` | `work/gofly-ios-figma04/figma/D14-light.png` | `work/gofly-ios-figma04/figma/D14-dark.png` | 已擷取／配對；整頁剩餘差異由票 09–14 逐頁修正。 |
| `D12` | `work/gofly-ios-figma04/screenshots/D12-light.png` | `work/gofly-ios-figma04/screenshots/D12-dark.png` | `work/gofly-ios-figma04/figma/D12-light.png` | `work/gofly-ios-figma04/figma/D12-dark.png` | 已擷取／配對；整頁剩餘差異由票 09–14 逐頁修正。 |
| `D7` | `work/gofly-ios-figma04/screenshots/D7-light.png` | `work/gofly-ios-figma04/screenshots/D7-dark.png` | `work/gofly-ios-figma04/figma/D7-light.png` | `work/gofly-ios-figma04/figma/D7-dark.png` | 已擷取／配對；整頁剩餘差異由票 09–14 逐頁修正。 |
| `D19` | `work/gofly-ios-figma04/screenshots/D19-light.png` | `work/gofly-ios-figma04/screenshots/D19-dark.png` | `work/gofly-ios-figma04/figma/D19-light.png` | `work/gofly-ios-figma04/figma/D19-dark.png` | 已擷取／配對；整頁剩餘差異由票 09–14 逐頁修正。 |
| `D20` | `work/gofly-ios-figma04/screenshots/D20-light.png` | `work/gofly-ios-figma04/screenshots/D20-dark.png` | `work/gofly-ios-figma04/figma/D20-light.png` | `work/gofly-ios-figma04/figma/D20-dark.png` | 已擷取／配對；整頁剩餘差異由票 09–14 逐頁修正。 |
| `D21` | `work/gofly-ios-figma04/screenshots/D21-light.png` | `work/gofly-ios-figma04/screenshots/D21-dark.png` | `work/gofly-ios-figma04/figma/D21-light.png` | `work/gofly-ios-figma04/figma/D21-dark.png` | 已擷取／配對；整頁剩餘差異由票 09–14 逐頁修正。 |
| `D4` | `work/gofly-ios-figma04/screenshots/D4-light.png` | `work/gofly-ios-figma04/screenshots/D4-dark.png` | `work/gofly-ios-figma04/figma/D4-light.png` | `work/gofly-ios-figma04/figma/D4-dark.png` | 已擷取／配對；整頁剩餘差異由票 09–14 逐頁修正。 |
| `D3` | `work/gofly-ios-figma04/screenshots/D3-light.png` | `work/gofly-ios-figma04/screenshots/D3-dark.png` | `work/gofly-ios-figma04/figma/D3-light.png` | `work/gofly-ios-figma04/figma/D3-dark.png` | 已擷取／配對；整頁剩餘差異由票 09–14 逐頁修正。 |
| `D10` | `work/gofly-ios-figma04/screenshots/D10-light.png` | `work/gofly-ios-figma04/screenshots/D10-dark.png` | `work/gofly-ios-figma04/figma/D10-light.png` | `work/gofly-ios-figma04/figma/D10-dark.png` | 已擷取／配對；整頁剩餘差異由票 09–14 逐頁修正。 |
| `D8` | `work/gofly-ios-figma04/screenshots/D8-light.png` | `work/gofly-ios-figma04/screenshots/D8-dark.png` | `work/gofly-ios-figma04/figma/D8-light.png` | `work/gofly-ios-figma04/figma/D8-dark.png` | 已擷取／配對；整頁剩餘差異由票 09–14 逐頁修正。 |
| `D2` | `work/gofly-ios-figma04/screenshots/D2-light.png` | `work/gofly-ios-figma04/screenshots/D2-dark.png` | `work/gofly-ios-figma04/figma/D2-light.png` | `work/gofly-ios-figma04/figma/D2-dark.png` | 已擷取／配對；整頁剩餘差異由票 09–14 逐頁修正。 |
| `D22` | `work/gofly-ios-figma04/screenshots/D22-light.png` | `work/gofly-ios-figma04/screenshots/D22-dark.png` | `work/gofly-ios-figma04/figma/D22-light.png` | `work/gofly-ios-figma04/figma/D22-dark.png` | 已擷取／配對；整頁剩餘差異由票 09–14 逐頁修正。 |
| `D2.a` | `work/gofly-ios-figma04/screenshots/D2.a-light.png` | `work/gofly-ios-figma04/screenshots/D2.a-dark.png` | `work/gofly-ios-figma04/figma/D2.a-light.png` | `work/gofly-ios-figma04/figma/D2.a-dark.png` | 已擷取／配對；整頁剩餘差異由票 09–14 逐頁修正。 |
| `D23` | `work/gofly-ios-figma04/screenshots/D23-light.png` | `work/gofly-ios-figma04/screenshots/D23-dark.png` | `work/gofly-ios-figma04/figma/D23-light.png` | `work/gofly-ios-figma04/figma/D23-dark.png` | 已擷取／配對；整頁剩餘差異由票 09–14 逐頁修正。 |
| `E1` | `work/gofly-ios-figma04/screenshots/E1-light.png` | `work/gofly-ios-figma04/screenshots/E1-dark.png` | `work/gofly-ios-figma04/figma/E1-light.png` | `work/gofly-ios-figma04/figma/E1-dark.png` | 已擷取／配對；整頁剩餘差異由票 15 逐頁修正。 |
| `E2` | `work/gofly-ios-figma04/screenshots/E2-light.png` | `work/gofly-ios-figma04/screenshots/E2-dark.png` | `work/gofly-ios-figma04/figma/E2-light.png` | `work/gofly-ios-figma04/figma/E2-dark.png` | 已擷取／配對；整頁剩餘差異由票 15 逐頁修正。 |
| `E3` | `work/gofly-ios-figma04/screenshots/E3-light.png` | `work/gofly-ios-figma04/screenshots/E3-dark.png` | `work/gofly-ios-figma04/figma/E3-light.png` | `work/gofly-ios-figma04/figma/E3-dark.png` | 已擷取／配對；整頁剩餘差異由票 15 逐頁修正。 |
| `E4` | `work/gofly-ios-figma04/screenshots/E4-light.png` | `work/gofly-ios-figma04/screenshots/E4-dark.png` | `work/gofly-ios-figma04/figma/E4-light.png` | `work/gofly-ios-figma04/figma/E4-dark.png` | 已擷取／配對；整頁剩餘差異由票 15 逐頁修正。 |
| `E5` | `work/gofly-ios-figma04/screenshots/E5-light.png` | `work/gofly-ios-figma04/screenshots/E5-dark.png` | `work/gofly-ios-figma04/figma/E5-light.png` | `work/gofly-ios-figma04/figma/E5-dark.png` | 已擷取／配對；整頁剩餘差異由票 15 逐頁修正。 |
| `E1.a` | `work/gofly-ios-figma04/screenshots/E1.a-light.png` | `work/gofly-ios-figma04/screenshots/E1.a-dark.png` | `work/gofly-ios-figma04/figma/E1.a-light.png` | `work/gofly-ios-figma04/figma/E1.a-dark.png` | 已擷取／配對；整頁剩餘差異由票 15 逐頁修正。 |
| `E2.a` | `work/gofly-ios-figma04/screenshots/E2.a-light.png` | `work/gofly-ios-figma04/screenshots/E2.a-dark.png` | `work/gofly-ios-figma04/figma/E2.a-light.png` | `work/gofly-ios-figma04/figma/E2.a-dark.png` | 已擷取／配對；整頁剩餘差異由票 15 逐頁修正。 |
| `F1` | `work/gofly-ios-figma04/screenshots/F1-light.png` | `work/gofly-ios-figma04/screenshots/F1-dark.png` | `work/gofly-ios-figma04/figma/F1-light.png` | `work/gofly-ios-figma04/figma/F1-dark.png` | 已擷取／配對；整頁剩餘差異由票 16–18 逐頁修正。 |
| `F4` | `work/gofly-ios-figma04/screenshots/F4-light.png` | `work/gofly-ios-figma04/screenshots/F4-dark.png` | `work/gofly-ios-figma04/figma/F4-light.png` | `work/gofly-ios-figma04/figma/F4-dark.png` | 已擷取／配對；整頁剩餘差異由票 16–18 逐頁修正。 |
| `F5` | `work/gofly-ios-figma04/screenshots/F5-light.png` | `work/gofly-ios-figma04/screenshots/F5-dark.png` | `work/gofly-ios-figma04/figma/F5-light.png` | `work/gofly-ios-figma04/figma/F5-dark.png` | 已擷取／配對；整頁剩餘差異由票 16–18 逐頁修正。 |
| `F6` | `work/gofly-ios-figma04/screenshots/F6-light.png` | `work/gofly-ios-figma04/screenshots/F6-dark.png` | `work/gofly-ios-figma04/figma/F6-light.png` | `work/gofly-ios-figma04/figma/F6-dark.png` | 已擷取／配對；整頁剩餘差異由票 16–18 逐頁修正。 |
| `F7` | `work/gofly-ios-figma04/screenshots/F7-light.png` | `work/gofly-ios-figma04/screenshots/F7-dark.png` | `work/gofly-ios-figma04/figma/F7-light.png` | `work/gofly-ios-figma04/figma/F7-dark.png` | 已擷取／配對；整頁剩餘差異由票 16–18 逐頁修正。 |
| `F9` | `work/gofly-ios-figma04/screenshots/F9-light.png` | `work/gofly-ios-figma04/screenshots/F9-dark.png` | `work/gofly-ios-figma04/figma/F9-light.png` | `work/gofly-ios-figma04/figma/F9-dark.png` | 已擷取／配對；整頁剩餘差異由票 16–18 逐頁修正。 |
| `F8` | `work/gofly-ios-figma04/screenshots/F8-light.png` | `work/gofly-ios-figma04/screenshots/F8-dark.png` | `work/gofly-ios-figma04/figma/F8-light.png` | `work/gofly-ios-figma04/figma/F8-dark.png` | 已擷取／配對；整頁剩餘差異由票 16–18 逐頁修正。 |
| `F6.a` | `work/gofly-ios-figma04/screenshots/F6.a-light.png` | `work/gofly-ios-figma04/screenshots/F6.a-dark.png` | `work/gofly-ios-figma04/figma/F6.a-light.png` | `work/gofly-ios-figma04/figma/F6.a-dark.png` | 已擷取／配對；整頁剩餘差異由票 16–18 逐頁修正。 |
| `F1.a` | `work/gofly-ios-figma04/screenshots/F1.a-light.png` | `work/gofly-ios-figma04/screenshots/F1.a-dark.png` | `work/gofly-ios-figma04/figma/F1.a-light.png` | `work/gofly-ios-figma04/figma/F1.a-dark.png` | 已擷取／配對；整頁剩餘差異由票 16–18 逐頁修正。 |
| `F1.b` | `work/gofly-ios-figma04/screenshots/F1.b-light.png` | `work/gofly-ios-figma04/screenshots/F1.b-dark.png` | `work/gofly-ios-figma04/figma/F1.b-light.png` | `work/gofly-ios-figma04/figma/F1.b-dark.png` | 已擷取／配對；整頁剩餘差異由票 16–18 逐頁修正。 |
