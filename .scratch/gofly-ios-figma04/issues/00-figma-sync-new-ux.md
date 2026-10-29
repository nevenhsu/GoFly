# 00: Figma 04 同步新 UX（Claude 執行，不交給 Luna）

**What to build:** 把本輪三項 UX 決定先畫進 Figma 04 的 Light 與 Dark，讓後續 App 票有視覺準據：(1) 路線「＋ 新增停靠點」新欄位加在清單最後當終點；(2) 無法規劃路線的 toast 按鈕由「重試」改「修正」；(3) 設定服務卡新增「重置成功」一態（單一按鈕變「啟動模擬」，上方出現 success toast）。

**Blocked by:** None (can start immediately).

**Status:** done: software-verified

**Assignee hint:** Claude（Figma Console）

- [x] D8 Light／Dark 的 toast 按鈕文字為「修正」，D8 說明文字更新為『系統自動調整地點順序後重新規劃』。
- [x] D1／D2 說明文字寫明：新增停靠點的空欄位加在最後並成為終點、原終點降為停靠點。
- [x] 新增 `F1.b · 設定首頁 / 重置成功`（Light 與 Dark，位於 F1.a 右側）：導覽列下方懸浮（疊在內容上方、不推動版面）的 `Toast / 系統訊息 / success`（標題「已重置連線」、說明「可以重新啟動模擬」）、服務卡只有一顆主按鈕「啟動模擬」、pill 為非錯誤狀態。
- [x] F1／F1.a／F1.b 三態說明文字寫清楚單一按鈕在各狀態的文字（正常停止＝啟動模擬、運行中＝停止服務、停止失敗＝重置連線、重置成功＝啟動模擬）。
- [x] 新 frame 全部綁定對應 Theme 變數與共用元件 instance，不新增 Variable、不動 Light／Dark Color Scheme 板；Light 與 Dark 成對。
- [x] `docs/IOS-UI-DESIGN.md` 與 `docs/FIGMA-UI-RECONCILIATION.md` 以日期條列同步，區分 Figma 設計更新與 App 狀態（App 待實作）。

## 執行紀錄

### 2026-10-29 只讀驗收（Figma 04）

- **Figma 設計更新**：本次只讀驗收，未修改 Figma。D8 Light `222:10536`／Dark `322:40937` 的 action 顯示「修正」，兩份說明均要求重排所有節點（含起點），成功才採用新順序，失敗保留原順序與提示。D1／D2 Light／Dark 說明均寫明空欄位加在清單最後並成為終點、原終點降為停靠點。
- **Figma 設計更新**：F1.b Light `322:51696`／Dark `322:51847` 成對位於 F1.a 右側；截圖已讀回導覽列下方 success toast「已重置連線／可以重新啟動模擬」、單一「啟動模擬」主按鈕及中性 pill。F1／F1.a／F1.b 的 Light／Dark 說明已列出各狀態的單一主按鈕文案。六個 F1 狀態 frame 共用 component instances；本次未新增或修改 Variables，也未改 Color Scheme。
- **規格文件**：`docs/IOS-UI-DESIGN.md` 與 `docs/FIGMA-UI-RECONCILIATION.md` 的 2026-10-29 條目已列出三項 Figma 更新，並明確標示 App 待實作、未做實機驗證。
- **截圖位置**：Figma Desktop Bridge 當前渲染截圖已核對 D8 Light `222:10536`、D8 Dark `322:40937`、F1.b Light `322:51696`、F1.b Dark `322:51847`；屬 Figma-only 票，未產生 App fixture 截圖。
- **Figma 缺口／差異**：本票要求的 Light／Dark variants 與文案皆存在，未發現本票缺口。B11 Dark 缺少設計與本票無關，依規範保留，不推定。
- **App 實作／裝置驗證**：App 行為仍待票 10、11、17 實作；未做實機驗證。
- **驗證**：`bash app/GoFly/scripts/check.sh` 通過（343 tests／56 suites、native service checks、unsigned iOS Simulator build）。
