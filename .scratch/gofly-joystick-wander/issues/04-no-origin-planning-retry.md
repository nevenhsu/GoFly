# 04 · 無位置自動起步與規劃重試

狀態：實作完成並軟體驗收。依賴：03。

## 本票變更

- 規劃錯誤使用獨立 danger toast「無法規劃路線」＋「重試」；重試呼叫漫步道路規劃流程，不共用背景中斷的恢復入口。
- 起點只採用已確認且有效的模擬位置，其次採用有效目前定位。沒有兩者時，從目前地圖視野中心及附近有限候選搜尋，最多三組起訖路段。
- 有效路段成功後才以道路入口送出起點瞬移；只有該瞬移 ACK 後才安裝路線並啟動同一搖桿 owner。規劃錯誤、過期結果與未 ACK 起點不會啟動漫步。
- 起點候選以視野中心與可視範圍內的有限偏移生成；不無限搜尋。速度距離預算沿用 `WanderTargetSelector` 的速度×600 秒。
- E1「自動漫步」在沒有有效位置時仍可啟動規劃；按鈕 admission 與搖桿 owner admission 分開。既有定位操作正在準備時，點擊會綁定該 intent，僅匹配的 ACK 可一次性消耗開始請求。

## 驗收

- Core：`WanderStartRequestGateTests` 與完整275項 Core tests通過。GoFlyTransportTests 2個loopback測試因`.socket`失敗，官方check中止。
- Native boundary 13情境、iOS Simulator build與`git diff --check`通過；未執行 UI tests。
- Figma：開始票前讀取 E5 淺／深色渲染；沿用現有 danger Toast 元件樣式，不新增狀態組合畫面、不修改 E5 原任務恢復設計。
- 未驗證：無 GPS 的實機 MapKit 道路可用率、系統定位授權與真實裝置 ACK；本輪不操作實機。
