# 07 · 漫步中斷恢復與共用狀態一致

狀態：既有恢復路徑核對完成，軟體驗收通過。依賴：03。

## Figma 讀稿

票開始前以 Figma Console 檢視並渲染 E5 Light/Dark。兩者均為相同的收合恢復列、目的地及速度資訊；Dark 已與 Light 共用結構與控件，只使用深色 tokens。無需修改 Figma，未新增 prototype wiring。

## 核對結果

- `ConnectionRecoveryController` 保存 wander 原目的地、當前速度、ACK歷史、最後ACK座標與方位；恢復沿用 movement lease/continuation，沒有觸發重新選目的地的規劃 Retry。
- `MovementContinuationController` 僅在同一 execution ID/lease 的 owner 健康且 running 時認定漫步延續。
- App 進入 inactive 時取消未提交的 wander route planning 並淘汰其 generation；回到 active、完成 fresh recovery probe 且連線有效後，從原目的地或原 ACK 終點接續規劃。Core route-resume admission 同時要求 scene active，過期規劃不能在背景復活送點。
- Interrupted planner checkpoint 只在有新 active checkpoint 時更新；連續 scene／connection interruption 不會覆寫已保存的目的地。離開 joystick 或 view 消失會清空 checkpoint，已取消的 startup 不會延遲復活。
- foreground fresh probe 期間禁止 wander Retry 和手勢，已有 `freshProbeBlocksWanderRetryAndGestureUntilActualResult` 驗收。
- 規劃失敗 Retry 與連線／背景 recovery 分離；後者接續保存任務。既有背景上限不變。

## 驗收

- `freshProbeBlocksWanderRetryAndGestureUntilActualResult` 通過；漫步整合測試亦確認失活時 resume 拒絕且目的地／路線不變。ConnectionRecoveryControllerTests通過。Core 275 tests、native boundary 13情境及iOS Simulator build通過。
- App-level lifecycle race 由 reviewer 複核上述 checkpoint 清理與保存順序；iOS UI lifecycle 自動化未執行。
- 官方 check 的 Transport loopback兩項 `.socket` 失敗，見 tracker。
- E5 Figma 畫面核對完成；UI 同步不代表實機背景限制已驗收。
- 未驗證：planner await 中真正的 iOS lifecycle/UI 事件時序、實機背景／藍牙中斷恢復；本輪依授權不操作實機，也未執行 UI tests。
