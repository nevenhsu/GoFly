# 03: 按鈕、Icon Button 與輸入欄共用元件

**What to build:** 按鈕板（Figma Light／Dark『0 · 共用元件（按鈕）』）所有元件在 App 有唯一實作並可在元件展示頁（`GoFlyComponentGallery`）檢視：Icon Button（Standard／Route／Ghost／Clear／More／MapControls／Copy，Large 44／Medium 40／Small 36／Extra Small 32，Enabled／Disabled，外框 `line/separator` 0.5 pt）、Icon + Text 與 Text 按鈕（Primary／Neutral／Danger／Ghost，四種尺寸與 Inline，內容置中）、Check、Status action、Text Field（Default／Focused／Disabled）。

**Blocked by:** 01, 02.

**Status:** ready-for-agent

**Assignee hint:** Luna

- [ ] 每個 variant 與 Figma 按鈕板逐一比對（尺寸、底色、邊線、字級、置中）；視覺小於 44 pt 者命中範圍仍 ≥ 44 pt。
- [ ] Primary 按鈕文字與圖示為純白；Enabled 圓形 Icon Button 外框為 0.5 pt `line/separator`。
- [ ] Text Field 三態：Default 使用 control 色、Focused 使用 active 色並有 primary 外框、Disabled 對照 Figma。
- [ ] 展示頁 Light／Dark 截圖與按鈕板一致；既有畫面改用共用元件，不留重複手刻副本。
- [ ] **圖示一律匯出成資產，不使用 SF Symbol**：Figma『0 · 共用元件（Icon）』的 52 個 `icon/*` 全部匯出為單色 template 資產（`.imageset`，向量 PDF 或 SVG，命名與 Figma 一致，例如 `icon/star` → `icon-star`），由單一 `GoFlyIcon` 入口（enum 或等價型別）統一提供，可著色、尺寸可指定、隨 Dynamic Type 縮放的容器內使用。App 內既有的 `GoFlySymbols` 與所有 `Image(systemName:)`、`Label(systemImage:)` 全數改用 `GoFlyIcon`，完成後 UI 層沒有殘留 SF Symbol（系統原生控制，如導覽返回鈕、原生鍵盤、分享 sheet，不在範圍）。建立並維護對照表（寫入票尾）：每個 `icon/*` ↔ 資產名；App 用了但目錄沒有的圖示，列出清單回報，不自行新增、不挑相近圖示。新增單元測試：52 個資產都存在且為 template 渲染，`GoFlyIcon` 無遺漏 case。
- [ ] **截圖驗證（必做，沒有截圖視為未完成）**：用 01a 的 fixture（不需網路、VPN、真機）對本票涵蓋的每一張 frame、Light 與 Dark 各截一張，存到 `work/gofly-ios-figma04/screenshots/`，並與 `work/gofly-ios-figma04/figma/` 的同名 Figma 截圖並排比對：無破版、無文字截斷、無缺漏元素、顏色與層級一致。把每張的結論（一致／有差異＋原因）與檔案路徑寫入票尾『執行紀錄』；到不了的 frame 如實列出，不略過。
- [ ] 最大 Dynamic Type 與 Reduce Motion 下仍可操作；互動元件觸控命中範圍 ≥ 44 × 44 pt；每個圖示按鈕有 accessibility label。
- [ ] 相關單元測試與 UI tests 更新並通過；`app/GoFly/scripts/check.sh` 通過。
- [ ] 不改命令、送點、ACK、背景執行語意（`app/GoFly/ARCHITECTURE.md` 不變量）；不宣稱實機驗證。

## 執行紀錄

（執行者在此記錄：日期、完成項、截圖路徑、未完成與原因、決策。）
