# 任務：模擬位置運行後突然停止——先除錯，再上手機抓證據驗證與修復

你在 repo `/Users/neven/Documents/projects/ianygo` 工作，對象是 iOS App `app/GoFly`（SwiftUI，iOS 26，Swift 6）。

GoFly 的運作方式：
- 透過 LocalDevVPN 通道連到手機本機的 remotepairingd（`10.7.0.1:49152`）。
- 再用 idevice FFI 的 DVT `location_simulation`，每 500ms 送一個點。
- 路線、搖桿、漫步共用這條路徑。

**工作分三階段，順序不可跳**：A 本機除錯與加診斷 → B 使用者在手機上重現並回傳證據 → C 依證據修復並再驗證。**你不能操作手機**：安裝、操作、拔插 USB 都由使用者執行，你只提供步驟。

> **停下規則**：依 `.scratch/prompts/00-master-order.md`「何時才停下」。其他問題照本文件建議做法自行決定，寫進 `work/gofly-dev/DECISIONS.md` 後繼續。

---

## 症狀與現有證據

路線或漫步執行一段時間後突然停止，**前景、背景都會發生**。實機是 iPhone 15 Pro、iOS 27.0.1、Wi‑Fi。

截圖在 `.scratch/bug-report/`：

- `IMG_6293.PNG`（前景）：漫步中停止。畫面顯示 `error.serviceUnavailable`「The device service could not be reached…」，狀態「Service ready · No active task」，下方有 Retry。
- `IMG_6294.PNG`（從背景回來）：畫面顯示 `background.expired`「The system ended background continuation…」，狀態「Joystick paused」。

這兩種**可能是不同根因**，請分開判定。

---

## 先讀

1. `AGENTS.md`；`app/GoFly/ARCHITECTURE.md`。其中「命令與送點」9 條不變量、「VPN 通道需要 Wi‑Fi」都不可違反。
2. 送點路徑：
   - `Sources/GoFlyCore/ServiceController.swift`：FIFO、watchdog（`operationTimeout` 30 秒）、`repairRequired`／`unconfirmed`，約第 720–1020 行。
   - `Sources/GoFlyCore/RouteExecutionController.swift`、`JoystickMovementController.swift`：500ms tick。
   - `Sources/GoFlyCore/VerifiedDeviceSession.swift`：每次送點前都會 `verifyIdentity()`。
   - `Device/NativeDeviceService.swift`：`movePoint` **每個 tick 都呼叫 `prepare()`**（identity → DDI／cryptex 查詢 → identity → location channel），然後 `setLocation`；`idevice_set_global_timeout(10)`。
   - `Device/NativeDeviceSession.swift`、`Device/NativeErrorMapping.swift`：除了少數 code，FFI 錯誤一律 fallback 成 `.serviceUnavailable`，原始 code／subcode 沒有留下。
   - `Sources/GoFlyCore/ConnectionRecoveryController.swift`：前景每 2 秒做通道探測。
3. 背景路徑：
   - `App/GoFlyContinuedProcessingDriver.swift`：`BGContinuedProcessingTask`，`strategy = .fail`；漫步的進度是不確定總量 `totalUnitCount = -1`。
   - `Sources/GoFlyCore/ContinuedProcessingController.swift`、`MovementContinuationController.swift`。
4. 既有手機驗收清單：`.scratch/gofly-ios/DEVICE-ACCEPTANCE.md`。

---

## 待驗證的假設（每一個都要以證據確認或排除）

| ID | 情境 | 假設 |
| --- | --- | --- |
| H1 | 前景 | 每個 tick 做 4 次以上 lockdown／RSD／image-mounter 往返，任何一次短暫失敗就變成 `notSent`／`unconfirmed`，接著進入 `repairRequired` |
| H2 | 前景 | 送點失敗後 `ownedSession` 沒有關閉或重建，死掉的連線被持續重用；Retry 也打在同一個 handle 上，只有 Stop（clear 時 close）才會清掉 |
| H3 | 前景 | 錯誤全部顯示成 serviceUnavailable，無法分辨 timeout（code 109）、通道斷、RSD 失敗 |
| H4 | 前景 | 通道或 Wi‑Fi 不穩：Wi‑Fi 省電、LocalDevVPN 斷線、remotepairingd 重啟，或 2 秒探測與送點互相干擾 |
| H5 | 背景 | 系統讓 `BGContinuedProcessingTask` 到期：可能和進度回報頻率、不確定進度、沒有終點、鎖定螢幕、電量或時間長度有關。查 Apple 文件確認系統要求，附來源，不要憑記憶 |
| H6 | 背景 | 任務只被接受、還沒 launch，或 grant 還沒綁定時就進入背景，導致 App 被暫停、連線中斷 |

---

## 階段 A：本機除錯與加診斷（不需要手機）

1. **讀程式碼驗證假設**：H1–H3、H6 能從程式碼推出多少，就先寫下推論與對應的程式碼位置。
2. **能用單元測試重現的先重現**：例如死 session 重用、錯誤對應、tick 失敗後的狀態轉換、grant 未綁定就進背景。`DeviceService`／`DeviceSession` 都有 protocol 可以注入假實作。先寫會失敗的測試，**這階段先不修**。
3. **加入診斷**（Debug 與 Release 都保留，成本要低）：
   - 用 `os.Logger`，subsystem `com.neven.gofly`，category 分為 `movement`、`device`、`background`、`tunnel`。
   - **關鍵事件用 `.notice` 以上等級**。`.info`／`.debug` 不會寫進裝置的持久日誌，事後抓不到。
   - 記錄內容：
     - 每個 tick：序號、每個 FFI 呼叫的名稱與耗時、結果。
     - 失敗時的原始 FFI code／subcode：**只記數字**，不記 FFI message，因為裡面可能有配對資料、裝置 ID、路徑。
     - session 的建立、關閉、重用。
     - `ServiceController` phase 轉換，watchdog 觸發。
     - scenePhase 變化；BGContinuedProcessingTask 的 submit／launch／progress 更新／expire 時間點；`NWPathMonitor` 的 Wi‑Fi／路徑變化。
   - **App 內診斷檔**：手機拔掉 USB 後也要能留下證據。
     - 在 `Library/Application Support/Diagnostics/` 寫 JSONL ring buffer，上限約 2 MiB，用既有 `AtomicFile` 規則，或 append-only 加大小上限。
     - 在「設定 › 裝置與簽名」或隱藏的開發者選項加「匯出診斷記錄」，用系統分享 sheet 輸出。
   - 不記錄完整精度座標（最多 3 位小數）、裝置識別碼、配對內容。
4. 跑 `bash app/GoFly/scripts/check.sh`，以及有改到原生邊界時的 `bash app/GoFly/scripts/check.sh --device`，都要通過。
5. **階段 A 回報**後，這個任務等使用者做階段 B（需要手機，必須停）。等待期間依總順序繼續下一個任務。回報內容：
   - 各假設的程式碼推論、已重現的失敗測試、診斷加了哪些點。
   - 給使用者的**手機重現步驟**（格式見下一節）。

---

## 階段 B：使用者在手機上重現（你負責寫步驟，使用者執行）

在階段 A 回報中，給出可直接照做的步驟，至少包含：

1. **安裝含診斷的 build**：用 Mac App 裝置頁的「更新 GoFly」覆蓋安裝，資料會保留。寫出要先執行的建置指令。不要求使用者刪除 App 或資料。
2. **前置條件**：iPhone 連 Wi‑Fi、LocalDevVPN 顯示 Connected、GoFly 的 VPN 通道檢查成功。記下時間、電量、是否開低耗電模式。
3. **測試矩陣**：每組記下開始時間、停止時間、畫面訊息並截圖。
   - F1：前景、漫步 20 km/h，螢幕保持開啟 15 分鐘。
   - F2：前景、多點路線，跑到完成或停止。
   - B1：開始漫步後切到其他 App 10 分鐘，再回來。
   - B2：開始有終點的路線後鎖定螢幕 10 分鐘，再解鎖回來。
   - 選做：同 F1，但接著 USB；用來比較 USB 對通道的影響。
4. **抓證據**（兩種都做）：
   - App 內「匯出診斷記錄」，傳回 Mac，放到 `work/gofly-ios/debug-movement-stops/device-<日期>/`。
   - 接上 USB 後在 Mac 執行以下指令（需要密碼）。若無法使用，改用 Console.app 選取 iPhone，篩選 `subsystem:com.neven.gofly`，即時串流後存檔。
     - `sudo log collect --device --last 1h --output work/gofly-ios/debug-movement-stops/device-<日期>/gofly.logarchive`
     - `log show work/gofly-ios/debug-movement-stops/device-<日期>/gofly.logarchive --predicate 'subsystem == "com.neven.gofly"' --style compact > work/gofly-ios/debug-movement-stops/device-<日期>/gofly.log`
   - 另外截下 LocalDevVPN 在同一時段的狀態或 log。
5. 提醒使用者：原始日誌與 logarchive **不要貼到聊天、不要提交**，只放在 `work/`。

---

## 階段 C：依證據修復並再驗證

1. 讀 `work/gofly-ios/debug-movement-stops/` 的證據，對每個假設寫下結論：確認、排除或仍不明，並附日誌片段（遮蔽後）。
2. **前景、背景各自定出根因**。證據不足時說明還缺什麼，再請使用者補一輪，不要猜修。
3. 依根因修復，可能方向如下（必須有證據支持才採用）：
   - 每個 tick 的 identity／DDI 檢查改為只在建立 session 時做，或降為低頻率。
   - 送點失敗後關閉並重建 session，再走一次 prepare。
   - 只對**確定未送出**（`notSent`，且 gate 未 claim）的點，做有限次數的退避重試。
   - 錯誤對應保留 timeout、通道斷、RSD 失敗等分類，讓 banner 給出正確的修復指引。
   - 背景：調整進度回報方式或頻率；grant 綁定前不進入可背景執行的狀態。
4. **嚴守不變量**：
   - 已 claim 的點不能假裝撤回。
   - `unconfirmed` 不能自動重送。
   - clear 不能盲目重送。
   - 遲到的 ACK 不能復活舊 lease。
   - `repairRequired` 時只允許冪等的 Stop。
   - 任何放寬這些規則的修法，先在回報中說明理由，經同意後再改 `ARCHITECTURE.md`。
5. 階段 A 的失敗測試要轉為通過；`check.sh`（含 `--device`，若有改原生邊界）要通過。
6. 給使用者**修正後的手機驗證清單**：同一個測試矩陣，加上通過標準。例如 F1 連續 15 分鐘沒有停止；B1、B2 回前景時狀態一致、沒有復活舊任務。再次抓同樣的證據做前後對比。
7. 更新 `.scratch/gofly-ios/DEVICE-ACCEPTANCE.md` 的相關項目，以及 `app/GoFly/ARCHITECTURE.md`（若行為有改）。區分「程式已修」「單元測試已驗證」「真機已驗證」。

---

## 限制

- 不改 UI 外觀，另有 UI 重構任務。錯誤文案要調整時，三語一起改。
- 不跑 Prettier。不提交憑證、配對檔、原始裝置日誌或 `work/` 產出。
- 保留工作樹中其他未提交的修改。
- 原生 patch 或 FFI header 需要變動時，先停下說明，不要自行重建 NativeBridge。

## 每階段回報格式

1. 各假設的狀態（確認／排除／待證據）與證據位置。
2. 修改了哪些檔案、為什麼不違反不變量。
3. 測試與 `check.sh` 結果（失敗附輸出）。
4. 下一步需要使用者在手機上做的事。
5. 不把「模擬器或單元測試通過」寫成「已修好」；只有階段 C 的真機證據通過才算修好。
