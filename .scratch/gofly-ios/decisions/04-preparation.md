# 票 04：準備嘗試、取消與單一任務權限

狀態：2026-10-17 Advisor 核准執行；實作基準 0379d10。手機驗收依使用者安排全部延後，不連接、不安裝或操作手機。

## 有界準備

- ServiceController 保持生命週期、FIFO 與真正 native 完成的 owner；不在 NativeDeviceService 中加重試迴圈。Core 每次呼叫 adapter 一次，嘗試間釋放 native queue，讓已排程的健康舊任務能執行。
- PreparedOperationSource 明列 start／point(PointMoveIntent)，PreparedOperationSnapshot 保存穩定 request ID、不可變來源、有效的第 1–3 次嘗試及 preparing／failed／cancelled 狀態。Start 只準備服務；point 沿用整個原候選快照，不改投目前新選點。
- 自動重試必須同時符合 notSent、gate 仍 available、要求世代仍有效且未滿三次。未派送不等於仍可派送：invalidated gate 不重試。相同 round 重用同一 intent 及 one-shot gate；整個 round 共用一個 watchdog，不因重試重新計時。
- claimed gate、unconfirmed、watchdog、Stop 或取消都永久結束該 round 的自動重試。adapter 若在 claim 後錯誤回報 notSent，正規化為 unknown，不當成準備失敗重送。
- cancelPreparation(id:) 只取消尚未 claim 的指定新要求，保留舊任務與候選／草稿。輸給 claim 競態時回報取消失敗，不能發布 cancelled。底層仍持有 handle 時 nativeBusy 保持，必須等真正返回；取消不要求 clear。
- retryPreparedOperation(id:) 只從已保存、確定未送出的失敗來源建立新 request／gate／三次 round；不重播未知或已派送要求。取消／過期 ID／另一筆準備期間不新增工作。

## 任務交接權限

- MovementTaskAuthority 提供 MovementTaskLease、MovementAuthoritySnapshot 與 confirmedHealthy／interrupted(failure)／unknown 健康狀態；running／paused 仍屬任務 owner，不能把健康與運作狀態混為一談。
- 準備失敗只更新新要求的 snapshot，不憑此改舊任務健康。只有來自該 lease 的排程器／原生命令結果等明確證據能發布中斷或未知。舊任務在準備期間被確定中斷時，原 captured authority 失效，不得假稱健康並交接。
- PointDispatchGate 公開 available／dispatched／invalidated 狀態，並可要求「仍為目前 lease」或「以新 lease 原子替換精確 captured authority snapshot」。gate 持有自己的 lock 執行 authority compare-and-swap；authority 不回呼 gate，避免反向鎖定。
- 新要求最後 native claim 成功時，同步撤銷舊 lease 並安裝新 lease，然後才 setLocation。未 claim 前不終止健康舊任務。未來 06／11 排程的每一筆 point 必須在同一最後門檻要求自己的 lease，交接後已排隊舊命令也無法寫入。
- 舊命令已 claim 時等待它真正完成；新命令不與它並行。新 unknown 留新 lease 為 unknown，不復活舊 lease。Stop 立即作廢 pending gate 與目前 authority，再 FIFO 執行必要 clear；遲到 ACK／clear 完成不恢復舊權限。
- 相同健康／run state 的重複證據不增加 authority 版本，避免健康舊任務持續 ACK 讓新要求永遠無法交接；真正健康／暫停狀態改變才作廢 captured snapshot。送點前 watchdog 不改健康舊任務的 ready、位置或權限，但仍等待底層返回。
- adapter 若違反契約，在未 claim 時回報 ACK／unconfirmed，Core 保守撤銷權限、關閉準備面板並鎖未知結果，不捏造 handoff、不自動 clear。
- 不為票 04 製造舊任務 UI 或空排程器；這是 06／11 正式排程必須消費的有界共用能力。

## UI 與既有契約

共用底面板對應 O11／O12／O14／O16：準備次數與取消、三次失敗具體原因及原來源重試、位置待確認提供設定／返回地圖。返回地圖仍鎖原 Go，Pin 詳情保留，收藏於 05 接入；不新增不存在的核對能力。原候選與草稿留在各自 owner，面板關閉不改裝置位置。與缺少真實 GPS 的非模態提示分開。H06 是「已停止送點／GPS 待確認」，即使 GPS 為 nil 或 clear 未確認仍可 Start 準備服務；它與 O16 尚未作廢的位置命令未知不同，O16 仍先由明確 Stop 終結原要求。不新增 repairRequired 下繞過 Stop 的另一個啟動入口。

沿用 03 的不可變候選、相同 session 身分、correlated ACK、持續 native session、FIFO／watchdog、未知結果鎖、GPS／模擬來源與等待箭頭。使用既有 Figma Console 本機讀回及截圖，這輪沒有重新讀回或修改 Figma。

## 公開驗證界線

- Start／point 在第 1／2／3 次成功、恰三次全失敗、發出的原快照與發布嘗試次數。
- 取消／Stop／watchdog 發生於嘗試間或底層未返回時：不再呼叫後續嘗試，不提前解除 nativeBusy；claim 後 notSent 不重送。
- 健康舊 lease 在取消／準備全失敗後保持；舊任務確定中斷使 pending handoff 失效。
- 同步排序：舊 claim 在交接前先完成；新 claim 撤銷舊 lease 後才寫入；已排隊舊 claim 隨後失敗。ACK、unknown、遲到 ACK、Stop／clear 不能復活舊權限。
- 模擬器驗面板／來源／重試／返回與實際 viewport；不使用假 native ACK 宣稱硬體成功。所有接收 App 與手機位置效果留在集中驗收表。
