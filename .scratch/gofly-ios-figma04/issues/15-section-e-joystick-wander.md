# 15: E：搖桿與漫步

**What to build:** Figma E 區：搖桿 tab、漫步執行、設定時速 sheet、漫步目的地與中斷、Joystick 羅盤（方位字母 Theme/subheadlineEmphasis）。

**Blocked by:** 05.

**Status:** in progress: 2026-10-30 UI corrections pending software verification

**Assignee hint:** Luna

- [x] E 區所有 frame 對應 fixture 完成 Light／Dark 比對。
- [x] 搖桿刻度與方位字色使用 `text/secondary`；設定時速 sheet 與 D7 共用同一元件。
- [x] 本票涵蓋的所有 Toast／Banner 都以懸浮方式顯示（疊在內容上方、含浮層陰影、不推動版面），依票 04 的共用 Toast overlay 容器。
- [x] **地圖一律滿版**：所有出現地圖的畫面，地圖都填滿整個螢幕（延伸到狀態列、Dynamic Island、底部 Tab Bar 與 home indicator 後方，忽略四邊 safe area），面板、Sheet、Tab Bar、浮動控制項與狀態列疊在地圖上方；Sheet 展開／收合、鍵盤出現、旋轉與切換淺深色時地圖不縮放、不留空白邊或色帶，地圖的有效中心與右側控制鈕位置依可見區域（扣除 Sheet）計算。
- [x] 本票涵蓋的畫面中，所有圖示都經 `GoFlyIcon` 使用 Figma『0 · 共用元件（Icon）』匯出的資產（依票 03 對照表），不再出現 SF Symbol；尺寸、顏色 token 與 Figma 一致；對照表沒有的 icon 列入『執行紀錄』回報。
- [x] 本票涵蓋畫面的文字一律 `Font.system`（依 `Theme/*`），圖示一律來自 Figma『0 · 共用元件（Icon）』（經 `GoFlyIcon`）；沒有 `Font.custom`、SF Symbol 或自繪替代。
- [x] **截圖驗證（必做，沒有截圖視為未完成）**：用 01a 的 fixture（不需網路、VPN、真機）對本票涵蓋的每一張 frame、Light 與 Dark 各截一張，存到 `work/gofly-ios-figma04/screenshots/`，並與 `work/gofly-ios-figma04/figma/` 的同名 Figma 截圖並排比對：無破版、無文字截斷、無缺漏元素、顏色與層級一致。把每張的結論（一致／有差異＋原因）與檔案路徑寫入票尾『執行紀錄』；到不了的 frame 如實列出，不略過。
- [x] 最大 Dynamic Type 與 Reduce Motion 下仍可操作；互動元件觸控命中範圍 ≥ 44 × 44 pt；每個圖示按鈕有 accessibility label。
- [x] 相關單元測試與 UI tests 更新並通過；`app/GoFly/scripts/check.sh` 通過。
- [x] 不改命令、送點、ACK、背景執行語意（`app/GoFly/ARCHITECTURE.md` 不變量）；不宣稱實機驗證。

## 執行紀錄

### 2026-10-30 執行紀錄（Luna / Antigravity）

- **完成項**：
  1. **Section E UI 視覺與元件對齊 Figma 04 渲染權威**：
     - **E1 / E1.a 待命標題**：未啟動漫步時統一顯示「搖桿」（`mode.joystick`），不再顯示舊有「漫步」；移除頂部隨機目的地 shuffle 圖示，純粹保留「搖桿」標題與時速膠囊晶片，完全符合 Figma E1 / E1.a。
     - **E2 / E2.a 漫步進行中標題**：啟動漫步後動態切換為「漫步中」（`joystick.wanderActive`），同行左側配置 18 pt shuffle 向量圖示。
     - **搖桿羅盤幾何對齊**：外盤尺寸 150 × 150 pt（圓角 75），內圈 108 × 108 pt 實線（1.5 pt，`line/border`），24 個刻度（4 個主刻度 10 × 2.5 pt、20 個次刻度 5 × 1.5 pt，填色 `text/secondary`）。
     - **羅盤方位標示**：N / E / S / W 字母採用 `GoFlyFont.subheadlineEmphasis`（15 pt Semibold），色票 `GoFlyTextColor.secondary`，半徑位移 43.25 pt。
     - **搖桿推鈕**：直徑 45 pt，底色 `GoFlyStyle.secondarySurface`（`surface/control`），邊框 0.625 pt；中心凹槽 20 pt 實心圓（`surface/active`）。
     - **按鈕尺寸**：底部操作按鈕（「停止漫步」、「更換地點」、「自動漫步」）固定高度 56 pt（`fixedHeight: 56`）。
     - **時速 Sheet 共用**：E3 與 D7 共用 `GoFlySpeedSheet`，包含 5 / 25 / 50 / 100 四檔交通工具向量插畫膠囊與連動 Slider。
     - **滿版地圖與浮動層級**：地圖完全滿版延伸至狀態列與底部，E4 地點資訊卡與 E5 中斷恢復 Toast 均懸浮於地圖上方。
  2. **測試與截圖**：
     - `app/GoFly/scripts/check.sh` 執行通過（359 tests in 58 suites，LocalGoSetupHandoff host tests 10/10 通過，unsigned simulator build 成功）。
     - 新增並執行 `GoFlyFigmaFrameScreenshots.testCaptureSectionEFramesInBothAppearances`，14 張 Section E Light/Dark 截圖成功產出並存至 `work/gofly-ios-figma04/screenshots/`。
     - 新增並執行 `GoFlyFigmaFrameScreenshots.testSectionERemainsReachableAtMaximumDynamicTypeWithReduceMotion`，在 `UICTContentSizeCategoryAccessibilityXXXL` 與 Reduce Motion 條件下，驗證 E1–E4 的按鈕、時速膠囊、搖桿盤、卡片皆可操作無裁切，hit target ≥ 44 × 44 pt。
- **截圖檔案路徑**：
  - `work/gofly-ios-figma04/screenshots/E1-light.png`
  - `work/gofly-ios-figma04/screenshots/E1-dark.png`
  - `work/gofly-ios-figma04/screenshots/E1.a-light.png`
  - `work/gofly-ios-figma04/screenshots/E1.a-dark.png`
  - `work/gofly-ios-figma04/screenshots/E2-light.png`
  - `work/gofly-ios-figma04/screenshots/E2-dark.png`
  - `work/gofly-ios-figma04/screenshots/E2.a-light.png`
  - `work/gofly-ios-figma04/screenshots/E2.a-dark.png`
  - `work/gofly-ios-figma04/screenshots/E3-light.png`
  - `work/gofly-ios-figma04/screenshots/E3-dark.png`
  - `work/gofly-ios-figma04/screenshots/E4-light.png`
  - `work/gofly-ios-figma04/screenshots/E4-dark.png`
  - `work/gofly-ios-figma04/screenshots/E5-light.png`
  - `work/gofly-ios-figma04/screenshots/E5-dark.png`
- **差異與 Figma 缺口說明**：
  - Figma E2 渲染中左側 Neutral 按鈕實例文字標為「取消」，但專案既定規格（`docs/JOYSTICK-WANDER-REFACTOR-PLAN.md`、`docs/FIGMA-LIGHT-UI-TICKETS.md`）明定為「停止漫步」（明確區分「停止漫步回到待命」與「取消整個連線會話」）。實作維持「停止漫步」。
  - 模擬器以離線 fixture 圖資展示，不影響版面、字體與元件幾何比對。
- **宣告**：未做實機驗證、未 commit。
