# GoFly iOS 架構與不變量

## 模組地圖

| 模組 | 位置 | 職責 |
| --- | --- | --- |
| `GoFlyCore` | `Sources/GoFlyCore` | 純 Swift 的服務、路線、搖桿、漫步、最愛、GPX、恢復與儲存邊界；可在 macOS 測試。 |
| `GoFlyTransport` | `Sources/GoFlyTransport` | Network.framework VPN 通道探測；唯一正式端點 `10.7.0.1:49152`、兩秒期限。 |
| `GoFly` App | `App` | SwiftUI 介面與組裝；`GoFlyRuntimeAssembly` 是唯一 runtime owner。 |
| Device adapter | `Device` | `NativeDeviceService` 經單一 serial session 呼叫 arm64 native；含支援檔 resolver 與錯誤映射。 |
| NativeBridge | `NativeBridge` | 固定 idevice 來源、窄幅 patch、allowlist header 與 `build.sh`；不由 Swift 直接匯入 generated header。 |

App 啟動時只建立一份 `GoFlyRuntimeAssembly`，持有 service、session recovery、movement、favorites、
imported routes、favorite routes 與 onboarding。View 只觀察與送出使用者意圖，不建立第二個 owner。

## 命令與送點

1. `ServiceController` 是唯一裝置命令 owner。Start／Stop／Restore／Reset、瞬移、路線與搖桿全部進入
   同一個私有 FIFO；上一筆原生呼叫實際返回後才執行下一筆。native session 也維持單一 FIFO。
2. `PointDispatchGate` 是最後派送門檻。native adapter 在真正送出點之前同步 `claim()`；claim 失敗即不送。
   gate 一旦 dispatched，取消或 Stop 都不能假裝撤回已跨過的 FFI；已 claim 的呼叫等實際返回。
3. 位置只在核對過的 ACK 後更新。準備失敗保留先前位置證據；已派送但錯誤／逾時＝`unconfirmed`，
   保留候選並鎖住 Go，直到明確 Stop 完成。新的有效 GPS 不會解除未知命令鎖。
4. Stop 先撤銷舊結果的發布權，再排入唯一一筆 clear。clear 必須等已 claim 的呼叫真正返回；
   新 Start／Restore／Reset 不越過尚未返回的清理。
5. watchdog 逾時只回報未知，不算原生完成，也不釋放 handle 或另開平行操作。
   repairRequired 時只允許冪等 Stop，確保恰一筆 clear 排隊。
6. 路線／搖桿／漫步共用同一個 writer 與 500ms ACK cadence；ACK 才推進進度與模擬位置，
   不補償等待期間漏掉的步數。Stop／Cancel／新交接的遲到 ACK 不得復活舊 lease。
7. `MovementTaskAuthority` 以 snapshot／lease 同步比較健康與執行狀態；最後 gate claim 在同一次
   lock 內完成新舊 lease 替換。冷啟動不提供舊任務 Resume；上次有 active 或不確定狀態時，
   必須以實際 clear ACK 解除 hold。
8. 首次流程只要求定位權限與 VPN 可達，不建立 GPS fix、不送點。Start 只準備服務。
9. 背景持續執行由 `GoFlyContinuedProcessingDriver` 管理：有執行中的路線或漫步時 submit 一個
   BGContinuedProcessingTask，expiry 時暫停任務；回前景不自動恢復。

## 儲存位置

所有資料位於 App sandbox 的 `Library/Application Support`：

| 目錄 | 內容 |
| --- | --- |
| `GoFlySetup/` | `incoming.json`、`readback-request.json`、`readback-response.json`、`activation.json`；Mac 首次安裝交接。 |
| `FavoritePlaces/` | `favorites.json`：地點最愛與標籤。 |
| `ImportedRoutes/` | `manifest.json` 加不可變 payload：GPX 匯入紀錄。 |
| `FavoriteRoutes/` | `manifest.json` 加不可變 payload：最愛路線。 |
| `SessionRecovery/` | `session.json`：草稿、速度、來回與最後顯示狀態。 |

寫入使用同目錄 staging、權限收緊、fsync 與單次 rename；讀取先做 no-follow 一般檔案檢查與大小上限。
損壞、未知 schema 或非一般檔案會封鎖後續寫入，不覆寫原資料。所有這些檔案都不保存
native task、ACK 或 GPS 授權；恢復只還原草稿與顯示，不代表裝置狀態。
