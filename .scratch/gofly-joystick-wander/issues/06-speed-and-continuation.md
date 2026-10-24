# 06 · 按速度續航、共用速度 pill 與設定 sheet

狀態：已實作並完成軟體驗收。依賴：04。

## Figma 讀稿

票開始前以 Figma Console 檢視並渲染唯一 iOS redesign page 的 E1/E2/E2.a/E3/E5 Light/Dark（共 10 個 frame）。既有稿的速度 pill 與 E3 設定 sheet 已共用一致結構：5/25/50/100 快選、1–120 slider、當前值與提交；E5 深色恢復列與淺色結構一致。無需本票修改 Figma，未增加 prototype wiring。

## 本票變更

- 路線與搖桿持續使用同一 `GoFlySpeedChip`、`GoFlySpeedSheet`、`MovementSpeedSynchronizer`、格式與持久化偏好。
- 漫步道路完成只在終點 step ACK 後推進進度；保留 ACK 座標與既有 lease，暫停期間按最新 speed 重選下一終點並向共用 planner 取路。
- 自動續段首次選點／規劃失敗會重新選一次終點並重規劃；第二次失敗才顯示「無法規劃路線」與 Retry。Retry 不使用直線 fallback。
- 當段每步取樣按最新速度更新，下一段的距離預算由 selector 依最新速度計算；道路距離與 ETA 依實際規劃路線及 ACK 進度。

## 驗收

- `MovementSpeedSynchronizerTests` 通過，涵蓋雙向同步、偏好儲存與避免來回覆寫；`realArrivalWithoutNextTargetPausesAuthorityAndGoThenRetryUsesTheSameLease` 改驗收ACK終點後裝入道路續段並沿用相同lease。
- iOS Simulator build、native boundary 13情境、Core 275 tests通過。完整 `check.sh` 在 Transport loopback `.socket` 兩項失敗；見 tracker。
- 未驗證：外部道路服務在實機上的回應及背景執行行為；不操作實機。
