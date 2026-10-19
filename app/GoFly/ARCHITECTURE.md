# GoFly iOS 架構與不變量

## 模組

| 模組 | 職責 |
| --- | --- |
| `GoFlyCore` | 服務、路線、搖桿、漫步、最愛、GPX、恢復與檔案邊界；可在 macOS 測試。 |
| `GoFlyTransport` | VPN 通道探測；唯一正式端點 `10.7.0.1:49152`、兩秒期限。 |
| `GoFly` App | SwiftUI 與 `GoFlyRuntimeAssembly`；只建立一份 runtime owner。 |
| `Device`／`NativeBridge` | 單一 serial session、固定 idevice 來源、窄幅 patch 與 allowlist header。 |

## 命令與送點

1. `ServiceController` 是唯一裝置命令 owner；Start／Stop／Restore／Reset／瞬移／路線／搖桿共用私有 FIFO，
   上一筆原生呼叫實際返回後才執行下一筆。
2. `PointDispatchGate` 是最後派送門檻；native adapter 真正送點前同步 `claim()`。已 dispatched 的呼叫
   不能被取消或 Stop 假裝撤回。
3. 位置只在核對過的 ACK 後更新；`unconfirmed` 保留候選並鎖住 Go，直到明確 Stop 完成。
4. Stop 先撤銷舊結果發布權，再排入唯一一筆 clear；clear 必須等已 claim 呼叫返回。
5. watchdog 逾時只回報未知；`repairRequired` 時只允許冪等 Stop。
6. 路線／搖桿／漫步共用一個 writer 與 500ms ACK cadence；遲到 ACK 不得復活舊 lease。
7. `MovementTaskAuthority` 以 lease／snapshot 同步比較健康與執行狀態；背景 dispatch 需有效 grant。
8. 背景由 `GoFlyContinuedProcessingDriver` 管理：有執行中的路線／漫步時 submit 一個
   `com.neven.gofly.movement` 任務；有終點路線回報 ACK 距離比例，其餘不確定進度；自然完成呼叫
   `setTaskCompleted(success: true)`，expiry 只暫停並回到前景提示。
9. 冷啟動只還原草稿／顯示位置；上次有 active 或不確定狀態時啟動自動送一次 clear。失敗保持 stopped、
   不設錯誤、不彈窗，只保留 `coldClearPending` 與地圖提示；Start 不受影響。ACK 後清空 session
   的 active／uncertainty 並 flush 成功才解除提示。

## 儲存

資料位於 `Library/Application Support`：

| 目錄 | 格式 |
| --- | --- |
| `GoFlySetup/` | setup 交接與 activation；不屬本機存檔重構。 |
| `FavoritePlaces/` | `favorites.json`（schemaVersion 1）。 |
| `ImportedRoutes/` | `manifest.json` 索引＋`<uuid>.gpx` payload。 |
| `FavoriteRoutes/` | `manifest.json` 索引＋`<uuid>.route` payload。 |
| `SessionRecovery/` | `session.json`（schemaVersion 1）。 |

`AtomicFile` 是唯一讀寫 primitive：no-follow、大小上限、`.atomic` 寫入、0700／0600、
`completeUntilFirstUserAuthentication`。路線新增先寫 payload 再換 manifest；刪除先換 manifest 再刪 payload，
失敗只忽略；不做目錄掃描或 orphan cleanup。manifest 有但 payload 缺失的項目標為不可用，不自動移除。
損壞或未知 schema 會封鎖後續寫入，不覆寫原檔；檔案不存在視為空資料，不先建立目錄。
復原只在 store 記憶體保留最近一次刪除的 record＋payload，重啟後不可復原。
