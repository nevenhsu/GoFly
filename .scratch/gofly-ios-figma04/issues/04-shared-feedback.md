# 04: 狀態回饋共用元件

**What to build:** Toast（danger／warning／success）、Snackbar（2 秒自動消失／可復原）、StatusPill（啟動／模擬中／暫停／連線中斷）、StatusBanner、Progress、Slider（`Value` 0–100 比例軌道）與 Overlay／Dim（黑色 40%，Light 與 Dark 同一色）對齊 Figma 共用元件。

**Blocked by:** 01, 02.

**Status:** ready-for-agent

**Assignee hint:** Luna

- [ ] Toast 三個 tone 與 Figma Light／Dark 一致：標題 15 pt Semibold、說明 13 pt Regular、動作為膠囊按鈕、✕ 20 pt、高度隨內容。
- [ ] Snackbar 與 StatusPill 對照 Figma；Dark 色不使用純白。
- [ ] Overlay／Dim 在 Dark 為黑色遮罩（不得是淺色遮罩）；Sheet、ActionSheet、系統分享 sheet 後方畫面皆被壓暗。
- [ ] Progress 與 Slider 可在展示頁互動，Slider 縮放寬度時進度比例不變。
- [ ] **截圖驗證（必做，沒有截圖視為未完成）**：用 01a 的 fixture（不需網路、VPN、真機）對本票涵蓋的每一張 frame、Light 與 Dark 各截一張，存到 `work/gofly-ios-figma04/screenshots/`，並與 `work/gofly-ios-figma04/figma/` 的同名 Figma 截圖並排比對：無破版、無文字截斷、無缺漏元素、顏色與層級一致。把每張的結論（一致／有差異＋原因）與檔案路徑寫入票尾『執行紀錄』；到不了的 frame 如實列出，不略過。
- [ ] 最大 Dynamic Type 與 Reduce Motion 下仍可操作；互動元件觸控命中範圍 ≥ 44 × 44 pt；每個圖示按鈕有 accessibility label。
- [ ] 相關單元測試與 UI tests 更新並通過；`app/GoFly/scripts/check.sh` 通過。
- [ ] 不改命令、送點、ACK、背景執行語意（`app/GoFly/ARCHITECTURE.md` 不變量）；不宣稱實機驗證。

## 執行紀錄

（執行者在此記錄：日期、完成項、截圖路徑、未完成與原因、決策。）
