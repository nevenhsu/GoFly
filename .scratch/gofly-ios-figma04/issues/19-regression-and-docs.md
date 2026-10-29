# 19: 全流程回歸與文件同步

**What to build:** 在模擬器以 Light 與 Dark 走完所有 section 的主要流程，逐 frame 與 Figma 最後一次比對；整理差異清單，並同步文件。

**Blocked by:** 06, 07, 08, 10, 11, 12, 13, 14, 15, 17, 18.

**Status:** ready-for-agent

**Assignee hint:** Luna

- [ ] A–F 每張 frame 有最終截圖與比對結論（一致／已知差異／Figma 缺口）。
- [ ] `docs/IOS-UI-DESIGN.md`、`docs/FIGMA-UI-RECONCILIATION.md`、`docs/IOS-COLOR-SCHEME.json` 以日期條列更新，區分 Figma 設計、App 實作與實機驗證（本輪無實機驗證須明講）。
- [ ] `app/GoFly/scripts/check.sh` 全綠；列出需要真機驗收的項目到 `.scratch/gofly-ios/DEVICE-ACCEPTANCE.md`。
- [ ] 未解的 Figma 缺口（例如 B11 Dark）只列出，不推定為已設計。

## 執行紀錄

（執行者在此記錄：日期、完成項、截圖路徑、未完成與原因、決策。）
