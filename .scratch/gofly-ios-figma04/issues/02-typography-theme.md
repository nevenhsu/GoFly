# 02: 文字樣式對齊 Figma Theme/*

**What to build:** `GoFlyFont` 14 個字級 token 與 `GoFlyTextColor` 9 個文字色角色對齊 Figma `Theme/*`（含 `button/medium`、`button/small`），仍隨 Dynamic Type 縮放（`micro`、`metric` 固定）。

**Blocked by:** 01.

**Status:** ready-for-agent

**Assignee hint:** Luna

- [ ] **字型一律使用系統字型 `Font.system`**：所有文字（含 `GoFlyFont` 14 個 token、按鈕、Toast、輸入欄、Tab Bar 標籤、地圖標註以外的 UI）都由 `Font.system(...)`（或等價的系統 text style，如 `.body`、`.footnote`）取得，字級與字重依 Figma `Theme/*`；不得使用 `Font.custom`、任何字型檔或字型名稱字串。Figma 的 PingFang TC 即 iOS 系統中文字型，由系統字型自動對應。新增測試／靜態檢查：UI 原始碼沒有 `Font.custom`、`UIFont(name:`、`.custom(`。
- [ ] 字級、字重與 `docs/IOS-TYPOGRAPHY.md` 表格一致；只使用 Regular／Semibold。
- [ ] 文字色全部走 01 的 token；沒有 View 直接寫字級或顏色字面值。
- [ ] `TypographyStandardTests` 更新並通過。
- [ ] **截圖驗證（必做，沒有截圖視為未完成）**：用 01a 的 fixture（不需網路、VPN、真機）對本票涵蓋的每一張 frame、Light 與 Dark 各截一張，存到 `work/gofly-ios-figma04/screenshots/`，並與 `work/gofly-ios-figma04/figma/` 的同名 Figma 截圖並排比對：無破版、無文字截斷、無缺漏元素、顏色與層級一致。把每張的結論（一致／有差異＋原因）與檔案路徑寫入票尾『執行紀錄』；到不了的 frame 如實列出，不略過。
- [ ] 最大 Dynamic Type 與 Reduce Motion 下仍可操作；互動元件觸控命中範圍 ≥ 44 × 44 pt；每個圖示按鈕有 accessibility label。
- [ ] 相關單元測試與 UI tests 更新並通過；`app/GoFly/scripts/check.sh` 通過。
- [ ] 不改命令、送點、ACK、背景執行語意（`app/GoFly/ARCHITECTURE.md` 不變量）；不宣稱實機驗證。

## 執行紀錄

（執行者在此記錄：日期、完成項、截圖路徑、未完成與原因、決策。）
