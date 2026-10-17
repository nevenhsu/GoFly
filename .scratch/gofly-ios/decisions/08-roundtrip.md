# 票 08：來回走動方案（Advisor 已核准）

2026-10-17：07 最終 UI 回歸期間整理；須 07 實作、驗證與提交完成，才開始08 Executor；Advisor 已正式核准並要求下列 watchdog／端點ETA補充。真機全部延後。先前研究的「只有 controller direction revision、不增加 service control revision」建議已作廢：await callee entry 前可重入，沒有 pending gate 仍須撤銷舊方向計算。

## 執行與位置

沿用同一 frozen RouteExecutionIntent／PlannedRoute／speed／lease，增加執行期 heading（forward／reverse）、roundTripEnabled、usesPositionAxis 鎖存。路線座標軸永久是原起點0…原終點total，途經點及折返不重設。ACK 才提交 axisMeters；每次500ms cadence 依當下 heading 從最後 ACK 加／減 speed×0.5並夾到端點，不以累計總旅程距離當位置。Progress 的 committedDistanceMeters 仍指原路線位置，fraction 為 axis/total；ETA 依實際 heading 的下一端點距離。ActiveElapsed 沿用暫停凍結，非位置軸或反向里程。

控制器持有可編輯及運作／暫停共用的來回選項；取消保留選項、草稿及最後模擬位置。新執行 heading 初始化 forward，usesPositionAxis 初始化為開始時選項；執行途中首次勾選後鎖存為 true，關閉不解除，下一次全新單次才 reset。規劃／準備／pausing／cancelling／unknown／interrupted不接受方向操作；可編輯設定與 running／paused checkbox 以明確 setter 驗證狀態。

每端點只有真實 ACK 才判斷，先原子決定heading再發布progress／ETA，避免折返後短暫顯示0 ETA：roundTripEnabled 則轉向內側並等待下一cadence，不重送端點；關閉則在該端點完成。抵達終點／起點完成的 coordinate 必須是實際端點。關閉只改終止規則、不改向、不作廢現有 tick；ACK 已折返後才關閉就朝對面端點收尾。端點向外切換為 no-op，避免重複同端點／無位移命令。暫停改向及關閉維持 paused；Pause先接受後 pausing 不改向，方向先接受再Pause保留方向。

## 原子控制修訂與派送

Advisor 窄研究已推薦 lease-scoped service control revision，正式方案採此最小控制 seam，不修改 Rust gate、Stop generation 或每 adapter call FIFO：

- RouteCommanding 增加同步讀取 routeControlRevision(executionID:lease:) -> UInt64? 與 reviseRouteControl(executionID:lease:) -> UInt64?。只有同一 begun、未ended／unknown、目前健康 owner lease 可用，running／paused可修訂。修訂永遠遞增，即使沒有 pending tick；若 tick 未claim，以現有 gate.invalidateIfAvailable 原子作廢並記 controlCancelled。已claim不作廢真實結果。同步回傳新revision；失敗不更新controller heading。
- sendRoutePoint 增加 expectedControlRevision。scheduler 同一 MainActor turn 擷取 heading／位置／control revision 再計算 coordinate，將捕獲revision傳進 async send。service 在建立／claim gate前核對 owner／lease／revision；舊修訂明確回 .controlCancelled，沒有 native dispatch。處理 callee entry 前重入，不依賴「同actor await會先進入callee」。
- 修訂只管 pre-dispatch admission；已claim後不能以新revision抑制 ACK／unknown。舊方向已claim的命令必須等真正返回，發布真實 ACK 位置／進度，再從該位置按最新方向下一cadence；不能以新方向預先推算反向假ACK。
- 只有 gate.invalidateIfAvailable 確實由 available 原子轉為 invalidated，才能標記 tick.controlCancelled，並取消其 watchdog；尚未建立watchdog時，稍後入adapter也不得重新啟動。已因Pause／Cancel／Stop／timeout失效的gate不得被改寫原因。completion沿用既有timeout／協定不確定性與lifecycle quarantine優先，最後才是成功標記且adapter最終證明未派送的controlCancelled。timeout已先鎖存時，晚到claimedACK仍unconfirmed(operationTimedOut)，不得發布；任意unconfirmed／claimednotSent／未claim卻ACK都不能降為安全取消。control已成功撤銷且未claim的舊tick不得在等待FIFO／adapter返回期間誤判timeout。
- 新 .controlCancelled 僅代表 control 撤銷且尚未claim的 notSent／未建立gate。保留 owner、lease、健康、速度、序號與位置，等待該 call 真正結束後再等500ms重算，不重入／補發。未claim序號未消耗，沿既有 lastSequence+1；只有被確認ACK才前進。重複切向收斂最新heading，不累積 tick。
- 已claim notSent、任意unconfirmed、未claim卻acknowledged仍unknown／Stop required，不能被 controlCancelled掩蓋；逾時、Stop、Cancel／owner取代、Pause的既有原因與 settlement不得混淆。所有 native work仍最大1，舊gate無法在新heading越過claim；claim早於修訂則允許真實結果收斂。

## UI 與分工

初始路線細項加來回 checkbox，進行中／暫停面板是位置／進度、同列 checkbox＋單一無框方向切換、取消＋暫停／繼續。checkbox與方向為分離≥44pt命中區，icon在方向文字左側，原規格126×44pt為最小方向控件，DynamicType可增高／寬但保持同列並可捲動可達。關閉立即收起方向切換，原位置軸與 top bar實際目標保留到結束。普通未啟用單次不顯示方向與固定端點標示；位置軸鎖存時顯示0%起點／100%終點與目前位置百分比。不可增加運作時編輯入口。已存在paused取消確認沿用。

Core Executor擁有 RouteCommanding／ServiceController route extension／RouteDraft相關execution models／RouteExecutionController與其測試；不動其他 native／FIFO邊界。UI Executor擁有 RoutePanel／三語字串／UITests，以正式公開controller狀態接入，不造serviceACK／GPS來展示成功執行。Root擁有MapView topbar、docs/config、整合驗證與提交。UI與Core先確認 public seam；不是另一個任務或mode。

## 必要驗證

公開 seam TDD：一般單次回歸、forward/reverse距離、每段途經點連續位置、端點只ACK折返與無重複、實際端點完成、midpath改向無跳點、roundtrip關閉固定軸與方向至下一端點、新執行reset、paused改向／關閉／Resume、Pause與端點／改向競合、取消保留選項。

service與scheduler競合必驗：計算後await callee-entry前改向；無pending、FIFOqueued、adapter內未claim、已claim、連續兩次切向；control成功撤銷後既有／尚未建立watchdog不誤觸timeout、timeout先贏不得改寫為control取消；claimedACK正常發布、claimednotSent／unconfirmed不能安全取消化；Stop／owner取代不復活、現有repair／retry不退化、maxnative1、500ms ACK後cadence／無追趕。使用明確手動clock／adapter gate，禁止短wall-clock猜時間。

Simulator只驗可達的真實編輯／規劃失敗、三語、深淺／DynamicType與≥44pt，已有公開Core seam承擔running／paused行為，不添加假的成功native/GPS。完整Swift與UI、未簽署iPhoneOS build、native verifier、git diff --check與Standards／Spec雙軸；主機MapKit僅是規劃非移動。最終集中手機清單列往返、即時改向、暫停／關閉與實際位置待使用者驗收。不回寫Figma、不聲稱新Console讀回。
