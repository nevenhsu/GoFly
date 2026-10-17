# 15：正式背景接線與原子派送邊界

狀態：approved-v2 / implementation-complete / device-verification-pending。執行基準 `703309ea5b5c2c9d223a13968b0c95088c50e884`，build 17。

Advisor 第 1 輪核准 v1；第 2 輪核准 v2 的單一 Scene 邊界，兩輪皆無 finding。每方案最多五輪，目前尚餘三輪。Root 負責方案、整合及最後驗證；本文件整理已核准決策，不新增產品範圍。

## 產品行為與證據界線

2026-10-18 使用者確認保留現有無期限來回與漫步；背景受限、未取得或失去執行資格時暫停，回前景由使用者明確繼續。不新增時長、距離或圈數上限，不自動續租，也不追補背景期間的移動。

正式 App 接入 `BGContinuedProcessingTask` 候選。系統接受提交與實際執行資格分開：只有身分相符、仍有效的實際 launch grant，加上同一個已安裝且健康執行中的 native owner，才能在非前景送點。背景 App 重新整理開關、SDK 可用性、TCP 成功、GPS 或畫面狀態都不是這份資格。

所有 iPhone、USB、簽署、實體安裝、鎖屏、接收 App 與真實 iOS 26／27 scheduler 測試，依使用者要求集中最後驗收。controlled-device、Core、模擬器及未簽署建置只證明各自邊界，不宣稱已支援真實背景定位。

官方依據：Apple [WWDC25 背景執行](https://developer.apple.com/videos/play/wwdc2025/227/) 13:16–14:28 與本機 SDK 27.1 header。Info 允許 wildcard；register 與 submit 使用同一個完整 UUID identifier。BGC 不受傳統 didFinishLaunching 註冊期限限制，只使用預設 CPU／network，不新增 BGProcessing mode、Always location、GPU 或 audio。

## 明確意圖、交接與提交

- 路線 Start 在規劃完成、intent 存在且前景／generation 仍有效後發布需求。Resume、啟用／重試漫步及有效的前景 RT 目標變更，才建立新的需求。手動搖桿本身不申請背景工作。
- demand 與 ACK 各用同步、非重播的 publisher。畫面 redraw、GPS、場景返回、自動換目的地及 objectWillChange 不產生新的同意或提交。
- 新任務準備期間保留舊健康 owner 與背景工作；準備失敗或未 claim 的取消不取代它。新任務的實際首次 ACK 確立健康 owner 後才可提交；已健康且妥善暫停的明確 Resume 可沿用同一 lease。
- 僅保留一個目前候選、一個最新 pending demand，以及一個實體 submit Task。即使舊 submit 不理會取消，也保留其 handle 至真正返回；其後仍須重新確認前景、同一需求與實際 owner，才可處理最新 pending。
- 所有回覆核對 requestID、movementID 與 lease。退休身分先於 driver.cancel，舊回覆不得暫停同 lease 的新工作。RT 目標改變會使用新 requestID；不更換 native lease。
- 有效 grant 下的前景 RT 切換可取代背景候選。已關閉的 grant 不能靠 RT 切換解除：先暫停，等待明確 Resume。關閉漫步但仍持有手動輸入，是明確的前景手動同意，可退休自動工作的 binding；進背景仍釋放手動輸入。

## 真實 ACK 與進度

Route controller 只在接受實際 ACK 後發布序號、路徑距離增量、實際位置軸及有限路線抵達標記。首次 route ACK 為 sequence 0、距離 0，仍計一次寫入。Service 的搖桿 ACK 只在實際 queue head 計算、claim 且接受 ACK 後發布球面距離，不從 UI、GPS、時間或預計 recipe 推算。

每個候選僅保留目前身分的最後序號、次數及距離，拒絕重複或較舊序號。拒絕數值溢位及非有限值，不使用 wrapping arithmetic。序號到上限前暫停，不重送或繞回 0；Service 也在 `lastSequence + 1` 前檢查上限。

有限路線新 Start 的目標是全程；Resume／RT-off 的目標是當下位置軸到目前方向下一端點的剩餘距離。候選捕獲當時位置軸，後續距離使用 `abs(ACK位置軸 - 起始軸)`，使真正端點與目標使用同一組運算元；不從很大的 RT 累計值相減，也不以 clamp 偽造抵達。剩餘為 0 時不建立 BGC 工作，前景路線仍由真實端點 ACK 結束。

RT／漫步保留無期限語意，進度 total = -1，次數與距離只累計真實工作，不顯示假的完成百分比，也不把無期限工作宣告成功。有限 terminal ACK 在清空 intent／phase 及 endRoute 前發布，讓候選同步完成；若 expiry 已先封閉，系統結果仍為失效，不能覆寫 native 的真實抵達。

## 原子派送與失效順序

`MovementTaskAuthority` 保留前景旗標與可撤銷的具體 grant binding。鎖順序固定為 gate → authority → grant；不在鎖內呼叫外部 callback。場景與 binding 變化遞增 revision，連線與 cold-recovery 門檻仍各自獨立。

新 lease 的 install CAS 必須在前景，並通過原有健康／身分／連線／cold 門檻。前景同 lease 送點不得略過已關閉的 binding；背景則須有有效且相符的具體 grant。不同舊 lease 的 binding 不妨礙明確的新前景 claim。任何 runtime 操作都不提高 native health、不提供位置證據。

Service 在 bind 時核對實際已安裝、健康且執行中的 owner，不因該健康 owner 有一筆實際指令尚未結算，或另一任務正在準備，就錯誤拒絕。退休 binding 依具體身分與型別化理由檢查；一般退休不能清除仍健康執行中的 closed grant。明確 Resume 在同一 authority lock 內確認前景、健康且已暫停、連線／cold 可用後，退休舊 binding 並恢復 running。

系統 expiry 先在 callback queue 同步封閉 grant，再通知 MainActor。若尚未 claim 的指令先遇到這個封鎖，只有已確認未送出的 runtime denial 才可原子暫停健康 owner，並同步通知既有 controller；保留 intent、位置、目標及進度。已 claim、未知、畸形 ACK 或實際 native 逾時仍走既有不確定／恢復路徑，不能被背景狀態掩蓋。

進背景先關閉前景派送門檻，再停止前景 probe；只有相符、健康且有有效 grant 的 route／自動漫步繼續。手動輸入與 gesture 同步清除並修訂 input，已 claim 的一步可結算，下一步使用原自動目標；未 claim 的手動輸入不重播。

回前景先檢查已關閉的 binding 並暫停，再開前景門檻並啟動票 13 的 fresh probe。資格、VPN 或畫面返回都不自動 Resume。提交被拒但尚未綁定 grant 時，前景工作可繼續並顯示原因；進背景若仍未取得資格，則暫停並顯示背景不可用。

## 實際 SDK adapter 與資源界線

正式 App 使用同一個 process singleton driver，private initializer。`register()` 僅檢查設定；每個新提交先保留完整 requestID，再向 SDK 一次註冊相同 identifier 的 handler 並使用 `.fail` 提交。handler 只捕獲 weak driver 與預期 UUID，核對實際 task 類型、identifier 及目前身分後才建立 grant。

SDK 沒有 unregister handler API，因此 registration book 固定保留每 process 最多 256 次嘗試，失敗也計入，不驅逐、不重用。超限在呼叫 SDK 前回報 `registrationLimitReached`；這是 App 資源界線，並非 Apple 限制。不自動重啟、續租或改寫無期限產品目標。失敗的新註冊不自行退休另一個目前工作。

同一 framework task 以 weak-key object identity 對應唯一 TaskBox。atomic completion 由第一個結果固定；重複／遲到 callback 不可二次完成。expiry 同步封閉 admission 與 completion，再於 MainActor 完成 framework task 及通知 Core。

## v2：單一 Scene 與穩定生命週期

實際整合 bundle 原本啟用 multiple scenes，與 process 單一 Service／driver 的假設衝突。Advisor 第 2 輪核准明確設置 `UIApplicationSupportsMultipleScenes = false`。Xcode 的自動 scene manifest 曾蓋過來源值，因此 source 明列 scene configuration 並關閉其生成；release 檢查讀回實際未簽署 device 與 simulator bundle，而非只看來源檔。

Apple [UIApplicationSupportsMultipleScenes](https://developer.apple.com/documentation/BundleResources/Information-Property-List/UIApplicationSceneManifest/UIApplicationSupportsMultipleScenes) 說明 false 限制為一個 Scene；[WindowGroup](https://developer.apple.com/documentation/swiftui/windowgroup) 說明各視窗有獨立 State／StateObject。本票未增加多視窗功能。

App 在建立 SwiftUI observers 前一次建立 `GoFlyMovementModel`，持有同一份 route、joystick、recovery 與 continuation。Map 僅觀察這些物件；畫面、語言或外觀變更不得重建 native owner。這也避免初始化時向其他被觀察物件發布變更的 runtime warning。

## 凍結 public Interface

既有 `RouteCommandOutcome.acknowledged`、四參數 `JoystickStepReceipt` initializer 及票 14 呼叫者保持相容。新增範圍如下；實際建構 ACK／demand 的 initializer 只供模組內生產者使用，不新增私有測試入口。

| Interface | 契約 |
| --- | --- |
| `MovementAcknowledgement` | 唯讀 movementID、lease、sequence、source、acknowledgedDistanceMeters、routePositionMeters?、finiteArrival |
| `MovementContinuationDemand` | 唯讀 movementID、lease、kind、goal?；有限剩餘 0 使用 nil |
| `MovementContinuationIdentity` | movementID／lease 的控制身分，不是健康證據 |
| `MovementContinuationControlEvent` | requested(demand)／withdrawn(identity, reason)，同步、非重播 |
| `MovementContinuationWithdrawalReason` | userPaused／userCancelled／automaticDisabled(manualInputContinues:)／ended |
| `MovementContinuationRetirement` | ownerPausedOrEnded／foregroundGoalChange／foregroundManualAfterAutoOff |
| `ContinuedProcessingRegistrationBook` | MainActor，固定 maximumRegistrations = 256；reserve(UUID) 回傳 reserved／alreadyAttempted／capacityReached |
| Route／Joystick | continuationControlEvents；releaseForInactiveScene(continuingLease: nil) 保持舊呼叫行為；continuationDidBecomeUnavailable() 使用 backgroundUnavailable 原因 |
| Route／Service | movementAcknowledgements 分別發布 route／joystick 的真實 ACK |
| Service | setMovementSceneActive、bindMovementContinuation、hasMovementContinuation、依身分／理由 retireMovementContinuation；不開放任意健康提升 |
| `ContinuedProcessingController` | 新增有預設值的同步 onRuntimeAvailable(grant) callback；儲存且驗證 running 後呼叫，callback 後重查 generation／身分／有效性，避免重複進度 |
| `MovementContinuationController` | 使用實際 Service／route／joystick／recovery／driver 與本地化 presentation closure；公開 sceneDidBecomeActive、releaseForInactiveScene、refreshPresentation，唯讀 state／hasRuntime／noticeKey／receipts |

Facade 不提供 UI 直接開始背景工作的 API。refreshPresentation 只更新相同工作文字／真實進度，不發 native 指令或新提交。receipts 最多 256 筆、僅記憶體內，無座標、UDID、憑證或新 durable log；冷啟動資料不序列化 grant、request consent 或手動輸入。

## 驗證及目前交付

公開邊界測試經實際 controller／Service 與 controlled Device／driver 觀察，涵蓋首次 ACK、延遲 submit、accepted 尚未 launch、交接失敗、同 lease RT 切換、零剩餘、長 RT 後有限端點、手動接管釋放、expiry-before-claim、已 claim 的不確定結果及明確 Resume。初期界線程式先於完整行為測試，未倒推宣稱 RED；後續實際 RED、harness 修正與 GREEN 分別記錄於 work 證據。

完整 Swift 395 項、未簽署 SDK27.1 device／simulator build17、352 key 三語資源及兩軸零 finding 均通過。完整模擬器 UI 45／45 PASS（runner 2105.041s；xcresult wall 2127.022s）；審查修正後 current-source 背景 UI 2／2、三語最大字級單項及淺色單項另通過，全部零 runtime warning。Root 視讀深／淺色與三語捲動畫面確認可讀。序號上限以來源守衛及正常公開回歸檢查，不注入私有序號或宣稱執行了天文數量的操作。真實 scheduler／鎖屏／接收端及 iPhone／iPadOS 單視窗仍待最後手機驗收。
