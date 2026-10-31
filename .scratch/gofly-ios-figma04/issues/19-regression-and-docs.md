# 19: 全流程回歸與文件同步

**What to build:** 在模擬器以 Light 與 Dark 走完所有 section 的主要流程，逐 frame 與 Figma 最後一次比對；整理差異清單，並同步文件。

**Blocked by:** 06, 07, 08, 10, 11, 12, 13, 14, 15, 17, 18.

**Status:** in progress: 2026-10-31 full screenshot matrix refreshed; frame-by-frame comparisons and remaining docs pending

**Assignee hint:** Luna

- [ ] A–F 每張 frame 有最終截圖與比對結論（一致／已知差異／Figma 缺口）。
- [ ] `docs/IOS-UI-DESIGN.md`、`docs/FIGMA-UI-RECONCILIATION.md`、`docs/IOS-COLOR-SCHEME.json` 以日期條列更新，區分 Figma 設計、App 實作與實機驗證（本輪無實機驗證須明講）。
- [ ] `app/GoFly/scripts/check.sh` 全綠；列出需要真機驗收的項目到 `.scratch/gofly-ios/DEVICE-ACCEPTANCE.md`。
- [ ] 未解的 Figma 缺口（例如 B11 Dark）只列出，不推定為已設計。

## 執行紀錄

（執行者在此記錄：日期、完成項、截圖路徑、未完成與原因、決策。）

### 2026-10-31 Full screenshot matrix refresh

- **截圖更新**：`GoFlyFigmaFrameScreenshots.testCaptureSupportedFigmaFramesInBothAppearances` 在 iPhone 17 Pro／iOS Simulator 26.2 通過，覆蓋 64 個 frame IDs 的 Light／Dark，共 128 張 App PNG；`manifest.json` 與 `index.html` 由 harness 重新生成。原 root-level 圖片依 harness 歸檔至 `screenshots/previous/2026-10-30T17-15-29Z/`。
- **阻塞處理**：先前 D20 截圖因 UI test 將 TextField／ScrollView accessibility frame 當成內容 padding 而失敗；harness 改為確認 D20 欄位、資訊內容、儲存／清除控制可見可操作及鍵盤未自動彈出，沒有改變 App 畫面程式。
- **未完成**：此次為自動截圖與可達性檢查，不是 128 張逐一人工視覺比對；D20 的 Figma reference 有「路線標籤」獨立文字，而 App fixture 沒有此文字，差異保留待票 14／產品規格確認。沒有 Figma 寫入或實機驗證。
