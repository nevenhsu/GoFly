# GoFly iOS 架構與不變量

## 模組

| 模組 | 職責 |
| --- | --- |
| `GoFlyCore` | 服務、路線、搖桿、漫步、最愛、GPX、恢復與檔案邊界；可在 macOS 測試。 |
| `GoFlyTransport` | VPN 通道探測；唯一正式端點 `10.7.0.1:49152`、兩秒期限。失敗時保留 iOS 回報的最後連線狀態（NWError、path 狀態／原因、介面）供 B01 原文顯示；只作診斷。連線被拒絕（ECONNREFUSED）立即判定無法連線，不等兩秒期限。 |
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

## 首次啟動與 setup 身分

1. 沒有 `incoming.json`、`readback-request.json` 或 activation 時直接一般啟動，不讀身分。
2. activation 與 input 的啟動比對只綁 bundle ID；build、profile、executable 雜湊不參與啟動阻擋。
   重建、覆蓋安裝與 `renew` 會改變雜湊，但不會把 App 鎖在 `identityMismatch`。
3. Mac readback 握手仍綁完整身分（bundleID、build、兩個 SHA-256）。只有這條流程會計算
   profile 與執行檔（上限 256 MiB）的雜湊；一般啟動不計算。

## 儲存

資料位於 `Library/Application Support`：

| 目錄 | 格式 |
| --- | --- |
| `GoFlySetup/` | setup 交接與 activation；不屬本機存檔重構。 |
| `FavoritePlaces/` | `favorites.json`（schemaVersion 1）。 |
| `ImportedRoutes/` | `manifest.json` 索引＋`<uuid>.gpx` payload。 |
| `FavoriteRoutes/` | `manifest.json` 索引＋`<uuid>.route` payload。 |
| `SessionRecovery/` | `session.json`（schemaVersion 1）。 |
| `Diagnostics/` | `gofly.jsonl`：JSONL ring，上限 2 MiB，超出時在行邊界保留最新一半。 |

`AtomicFile` 是唯一讀寫 primitive：no-follow、大小上限、`.atomic` 寫入、0700／0600、
`completeUntilFirstUserAuthentication`。路線新增先寫 payload 再換 manifest；刪除先換 manifest 再刪 payload，
失敗只忽略；不做目錄掃描或 orphan cleanup。manifest 有但 payload 缺失的項目標為不可用，不自動移除。
損壞或未知 schema 會封鎖後續寫入，不覆寫原檔；檔案不存在視為空資料，不先建立目錄。
復原只在 store 記憶體保留最近一次刪除的 record＋payload，重啟後不可復原。

## 診斷

1. 所有診斷同時送 `os.Logger`（subsystem `com.neven.gofly`，category 為 `movement`、`device`、
   `background`、`tunnel`）與 `Diagnostics/gofly.jsonl`。關鍵事件（phase 轉換、watchdog、session
   建立／關閉／重用、FFI 失敗、背景 submit／launch／expire、通道探測、路徑變化、scene 變化）用
   `.notice` 以上；每個 tick 的細節用 `.debug`，只留在 App 內檔案。
2. 每個 tick 記序號、每個 FFI 呼叫的名稱與耗時、結果；失敗只記數字 `code`／`subcode` 與對應的
   `DeviceServiceFailure`。**不記 FFI message**（可能含配對資料、裝置 ID、路徑）。
3. 座標最多三位小數；不記裝置識別碼、配對內容。檔案權限 0700／0600，沿用 `AtomicFile` 重寫。
4. 匯出在「設定 › 裝置資訊」；只產生暫存分享檔，不改動 ring。

## VPN 通道需要 Wi‑Fi

GoFly 的端點 `10.7.0.1:49152` 是 iOS 的 remotepairingd，LocalDevVPN 只把封包繞回手機本機。2026-10-19 實機觀察：iPhone 只用行動網路時，該服務沒有在聽（連線被拒絕，path 經 utun 已滿足）；連上 Wi‑Fi 後服務出現在 49152，檢查才可能成功。因此引導、設定與錯誤文案都要求先連 Wi‑Fi。飛航模式加 Wi‑Fi 但未加入網路、個人熱點，以及使用中途 Wi‑Fi 中斷的行為尚未驗證。
