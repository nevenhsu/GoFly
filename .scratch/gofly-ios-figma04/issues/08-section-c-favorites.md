# 08: C：最愛地點

**What to build:** Figma C 區：最愛地點清單、編輯最愛 sheet（遮罩為黑色壓暗）、多選批次刪除、刪除後 snackbar 可復原。

**Blocked by:** 05.

**Status:** in progress: 2026-10-30 C2/D20 spacing and surface deltas pending UI verification

**Assignee hint:** Luna

- [x] C 區四張 frame 對應 fixture 並完成 Light／Dark 比對。
- [x] 編輯 sheet 內輸入欄與動作按鈕比 sheet 底亮兩階；多選 checkbox 兩態對照 Figma。
- [x] 刪除後 snackbar 位置與可復原行為不變，只改外觀。
- [x] 本票涵蓋的畫面中，所有圖示都經 `GoFlyIcon` 使用 Figma『0 · 共用元件（Icon）』匯出的資產（依票 03 對照表），不再出現 SF Symbol；尺寸、顏色 token 與 Figma 一致；對照表沒有的 icon 列入『執行紀錄』回報。
- [x] 本票涵蓋畫面的文字一律 `Font.system`（依 `Theme/*`），圖示一律來自 Figma『0 · 共用元件（Icon）』（經 `GoFlyIcon`）；沒有 `Font.custom`、SF Symbol 或自繪替代。
- [x] **截圖驗證**：用 01a fixture 對每張 frame、Light 與 Dark 各截一張，存到 `work/gofly-ios-figma04/screenshots/`，並與 `work/gofly-ios-figma04/figma/` 同名圖逐張並排比對；無破版、文字截斷或缺漏元素，顏色與層級符合 Figma。
- [x] 最大 Dynamic Type 與 Reduce Motion 下仍可操作；互動元件觸控命中範圍 ≥ 44 × 44 pt；每個圖示按鈕有 accessibility label。
- [x] 相關單元測試與 UI tests 更新並通過；`app/GoFly/scripts/check.sh` 通過。
- [x] 不改命令、送點、ACK、背景執行語意（`app/GoFly/ARCHITECTURE.md` 不變量）；不宣稱實機驗證。
- [x] 2026-10-30 追加：C1–C4 清單頂部留白 16 pt；C2 儲存按鈕下方至 Home indicator 留白 40 pt；C1／C4 success snackbar 使用雙色圓形 check。

## 執行紀錄

### 2026-10-30 執行紀錄（Luna）

- 完成 C1–C4 最愛地點清單、編輯 sheet、多選刪除與 snackbar 復原；清單背景／card 層級、64 pt row、分隔線 inset、C2 標籤 placeholder 與編輯資訊卡依 Figma 更新。TextField 套用 `GoFlyFont.body`（`Font.system`），checkbox Button 對 VoiceOver 暴露 `.isSelected` 狀態。
- Light／Dark 同名 Figma 對照結論：C1 刪除 1 項後七列與 snackbar；C2 編輯 sheet、輸入欄、資訊卡與儲存按鈕；C3 第 2、4 列選中與批次刪除按鈕；C4 刪除 2 項後五列與復原 snackbar，均無破版、截字或缺漏，色彩與間距層級相符。Figma 圖位於 `work/gofly-ios-figma04/figma/C1-light.png`、`C1-dark.png`、`C2-light.png`、`C2-dark.png`、`C3-light.png`、`C3-dark.png`、`C4-light.png`、`C4-dark.png`；App fixture 圖在相同檔名的 `work/gofly-ios-figma04/screenshots/`。
- 螢幕尺寸記錄：Figma frame 為 393 × 852 pt；目前 simulator 截圖為 402 × 874 pt，依等比例畫面對照，沒有發現影響驗收的視覺差異。C 區所用圖示均由 `GoFlyIcon` 資產提供；checkbox 未選取態的圓環為控制項外框，選取勾號使用 Figma `icon/check` 資產。未發現本票 Figma 缺口。
- UI tests：`testFavoritePlaceFrameFixturesShowExpectedStatesInBothAppearances` 通過並重產 8 張截圖；`testFavoriteBulkDeleteCanBeUndoneInBothAppearances` 通過；`testFavoriteEditorRemainsAccessibleAtMaximumDynamicTypeWithReduceMotion` 通過（Light／Dark）。`bash app/GoFly/scripts/check.sh` 通過：349 tests／58 suites、LocalGoSetupHandoff host tests、unsigned simulator build；`git diff --check` 通過。
- 未做實機驗證；未 commit。

### 2026-10-30 追加回饋執行紀錄（Luna）

- C1–C4 清單卡片統一在 NavBar 下方留 16 pt，使用 `GoFlyStyle.favoriteListTopSpacing`；Figma 目前 NavBar 到清單為 10 pt，App 按使用者要求多留 6 pt。C2 儲存按鈕下方至 Home indicator 留 40 pt，使用 `GoFlyStyle.favoriteEditorSaveBottomSpacing`。資訊卡到按鈕仍為 40 pt。Light／Dark 同步。
- C1／C4 success snackbar 改用 Figma `icon/okfill` 外觀的雙色圓形 check 資產，深淺色均保留綠色描邊、勾號與淺綠內填色，不再以單色模板 tint。
- 截圖更新：`work/gofly-ios-figma04/screenshots/C1-light.png`、`C1-dark.png`、`C2-light.png`、`C2-dark.png`、`C3-light.png`、`C3-dark.png`、`C4-light.png`、`C4-dark.png`；Figma 對照為 `work/gofly-ios-figma04/figma/` 同名圖，總覽 `work/gofly-ios-figma04/screenshots/index.html`。C1 snackbar check 與 Figma 雙色圓形圖示相符。C2 儲存按鈕依本次明確使用者要求改為距 Home indicator 40 pt；目前 Figma C2 仍為 20 pt，為已記錄的 App／使用者規格差異，Figma 未修改。
- `testFavoritePlaceFrameFixturesShowExpectedStatesInBothAppearances` 通過（iPhone 17 Pro simulator，Light／Dark 共 8 張截圖，1 passed／0 failed；`work/gofly-ios/ticket08-c-followup-ui-configured.xcresult`）。第一次未帶專案 Bundle ID 的測試建置未啟動 UI tests；使用 `check.sh` 相同 simulator build 設定重跑成功。
- `testFavoriteBulkDeleteCanBeUndoneInBothAppearances` 與 `testFavoriteEditorRemainsAccessibleAtMaximumDynamicTypeWithReduceMotion` 通過（2 passed／0 failed；`work/gofly-ios/ticket08-c-accessibility-ui.xcresult`）。`bash app/GoFly/scripts/check.sh` 通過：349 tests／58 suites、LocalGoSetupHandoff host tests、unsigned simulator build；`git diff --check` 通過。未做實機驗證；未 commit。
