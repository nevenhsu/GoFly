# 03 · 從有效起點開始道路漫步

狀態：實作完成並軟體驗收。依賴：02。

## 本票變更

- 共用 `RouteExecutionController` 中既有的道路 planner，新增漫步路段規劃入口；不建立第二個路線執行控制器或送點 owner。
- App 先從已確認的搖桿起點選終點並規劃道路，成功且仍是同一有效起點後才安裝路段、啟動原 `JoystickMovementController` owner。等待／失敗或過期的規劃結果不會啟動漫步。
- 地圖路線折線、位置 marker 路程取樣沿用路線地圖呈現介面。漫步進度只在該路段 ACK 後提交；頂部資訊列使用真實道路剩餘距離與速度 ETA；路段變更以 revision 隔離過期 ACK。
- 起點連續度檢查收緊至 1m，不以 joystick target 在道路折線前插入直線連接。只有服務端確認的模擬標記或新鮮 GPS 可當執行起點，保留的歷史模擬位置不能開啟搖桿 owner。
- Figma E2、E2.a 四個淺／深色畫面已校正為相同折線幾何，保留既有 150pt 搖桿、速度 pill、停止漫步與更換地點。

## 驗收

- Core：完整 suite 的275項 Core tests通過；專屬漫步整合測試通過。GoFlyTransportTests有2個loopback測試回報`.socket`，造成官方check中止。
- Native boundary：13情境通過；iOS Simulator build通過。
- Figma：E2、E2.a Light/Dark 四張渲染已讀回；線段路徑資料一致。
- `git diff --check`：通過。
- 未驗證：真實地圖道路回應、外部服務 ACK、實機位置與背景執行；本輪不操作實機。
