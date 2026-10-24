# Section E · 搖桿與漫步重構

日期：2026-10-24。依正式方案核准建立 01–07 七票；逐票實作與驗收。軟體驗證不等於實機驗收；本輪不操作實機、不提交、不發布。

| 票 | 狀態 | 依賴 | 驗收記錄 |
|---|---|---|---|
| 01 對齊 E 區靜態線框與狀態語意 | implemented; static-design-verified | — | 淺深色 E1.a/E3/E4 渲染已修改並讀回；App/Simulator/裝置待後續票驗證 |
| 02 手動搖桿自動定位與共用 Go 瞬移 | implemented; software-verified | 01 | 270 Core tests, 13 native boundary scenarios, iOS Simulator build, diff check pass |
| 03 從有效起點開始道路漫步 | implemented; static-design-verified; software-verified | 02 | E2/E2.a四張渲染讀回；路線overlay、距離/ETA、1m起點連續及ACK進度接入；275 Core tests通過；native 13情境及iOS Simulator build通過 |
| 04 無位置自動起步與規劃重試 | implemented; design-read; software-verified | 03 | 視野中心有限搜尋、匹配起點ACK gate、獨立規劃Retry、無起點按鈕與測試完成；Core/native/iOS Simulator checks通過 |
| 05 確認目的地、更換地點與手動接管回路 | implemented; static-design-verified; software-verified | 04 | E4/E2 Light/Dark 已讀；最終讀圖時修正 E4 Light 缺候選Pin、Dark誤用CandidatePin，兩者均為空心DestPin並重新截圖讀回；成功後原子換路、手動放開重規劃並保留原目的地、同lease續行；Pin卡panel收合行為及負向resume測試通過 |
| 06 按速度續航、共用速度 pill 與設定 sheet | implemented; software-verified | 04 | 已讀 E1/E2/E2.a/E3/E5 淺深色共10畫面；pill/sheet共用既有模組及持久化同步；終點ACK後以ACK起點、最新速度重選終點並規劃，首敗重新選點一次；速度同步及續段Core驗收通過 |
| 07 漫步中斷恢復與共用狀態一致 | implemented; software-verified | 03 | E5 Light/Dark結構一致；checkpoint含原目的地、速度、ACK座標/方位與歷史；connection recovery沿用原lease與任務，不經規劃Retry；既有前景probe測試通過 |

逐票證據及未驗證事項記在 `issues/` 對應票單。Core 275 tests與native boundary 13情境通過；iOS Simulator build通過。官方 `check.sh` 被 GoFlyTransportTests 兩個 loopback 測試中止（`eachCheckMakesFreshLoopbackConnection`、`closedEndpointCannotReportSuccessAndFinishesWithinDeadline`，均 `.socket`）；其餘 Transport tests通過。未執行 UI tests。實機定位、背景限制與外部地圖接收留待正式裝置驗收。
