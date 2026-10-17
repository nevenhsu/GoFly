# 票 06：兩點路線、ACK 進度與共用命令 pump

狀態：2026-10-17 Advisor 已核准；票 05 已提交 bcf9d0d（70 Swift／15 UI 通過），Executor 開始。手機集中驗收，開發期間不連接或操作手機。

## 草稿與規劃

- RouteDraft 與 execution 分開；06 先有兩個穩定 RouteNodeID 的節點，07 才增刪排序。節點值為 current／place(MapPlace)，06 只有起點可 current。
- 開始時解析並凍結：確認模擬位置優先，其次當下有效 realLocation；positionMarker／等待快取不作起點。沒有位置可手選，不補假座標。
- RouteSpeed 驗證 2–100 km/h、預設 20、step 1，Core 換算 m/s。
- RoutePlanning.plan(from:to:) async throws -> [GeoCoordinate] 是純 Core protocol；PlannedRoute 先驗原始 2…10,000 點、相鄰去重與正距離；原始首尾距所選起終點各不得超過 50m，才補入精確端點，保留全部道路頂點，最後再驗 2…10,000 點及正累積球面距離。
- App 用 MapKitWalkingRoutePlanner，沒路線明確失敗，不偷偷改直線；planner 不接觸 UDID／配對／裝置資料。規劃不動裝置。
- RouteExecutionIntent 保存 execution ID、lease、完整不可變 draft snapshot、planned route、速度；PreparedOperationSource 加 route(intent)，Retry 仍用同 intent/path。
- 第一筆 native 命令恆為精確指定起點，無目前位置到起點的 approach leg；第一 ACK 後 progress 仍為 0。

## Picker 與 UI

RouteExecutionController 為 MainActor ObservableObject，發布 draft、picker session、planning／preparing／running／pausing／paused／cancelling／unknown 與 progress。Picker session 綁原 RouteNodeID，使用獨立 CandidateController；Confirm 才寫回仍存在的相同 node，Cancel／遲到搜尋／節點更換均不改 draft。Favorite star 直接寫共用 store，Cancel 不回滾收藏。

運作／暫停只有精簡控制，沒有 mode tab、草稿編輯或其他隱藏模式入口。Paused Cancel 先確認，返回／關閉維持同一暫停與進度；Running Cancel 可直接取消。自然完成回編輯、保留草稿與服務、短暫顯示完成，不另做完成頁。

## 唯一命令 owner 與有界 FIFO

不讓 route 直接呼叫 DeviceService。新增窄 RouteCommanding seam，ServiceController 是唯一正式實作：

- beginRoute(intent) async 發共用 preparation、最多三次 round、handoff gate 與精確起點命令。三次失敗後等使用者 Retry／Cancel；只有 ACK／Cancel／Stop／unknown 結束 await，每個 continuation 恰完成一次。
- sendRoutePoint(executionID:lease:sequence:coordinate:) async。
- exact-lease pause／resume／end authority；取消與自然完成用 conditional revoke，不傷較新 task。

把現有整輪 tail 改為 ServiceController 私有 MainActor FIFO command pump：每一次 adapter call 是一筆 queue item，先完成該筆 completion 才取下一項。Preparation retry 結果後才重排到尾端，已排健康舊 tick 才可在 attempts 間實際執行。Start／Go／route tick／Stop clear 全走 pump。

每個 lease 最多一筆 queued／in-flight tick，真正返回後才安排下一筆；同時最多一個 preparation attempt、一個必要 clear。Stop 立即撤 authority／gates；已進 FFI 等真正返回，未執行 stale tick preflight 跳過；clear 仍 FIFO。外層 preflight 只省工作，不能取代 verified native 最後一步 gate claim。

nativeBusy 仍表示使用者可見準備／repair／clear，健康 tick 不反覆鎖 UI，但 pump 必須追蹤它真正完成。保留 01–05 watchdog、GPS／模擬證據、未知鎖與原子收藏契約。

## 排程、暫停與完成

- 可注入單調 RouteClock；ACK 後才開始下一個固定 500ms cadence，每次最多前進一個 cadence 的距離。native latency、主執行緒延遲、暫停／背景時間都不補歷史 tick。
- ACK 才更新確認模擬位置、marker 與 RouteProgress（committed distance／total／fraction／active elapsed／estimated remaining）。unknown 停排程、新 lease unknown，要求明確 Stop，不復活舊 lease。
- Pause 立即使 lease paused、作廢未 claim tick，顯示 pausing 並等已 claim FFI 返回；Resume 仍同 lease/path/distance，重新等 cadence。
- Cancel conditional revoke，等實際工作返回；不 clear、保留最後 ACK 位置與 draft，不可 Resume 舊 execution。
- 最終端點 ACK 後 conditional revoke、停 scheduler、服務 ready、保留端點／草稿，回編輯只發一次完成提示。最終 unknown 不自然完成。

## 必要公開驗證

Draft／node 身分、Picker Confirm／Cancel／遲到、Favorite 即時提交；current 解析優先與等待 cache 拒絕；snapshot 不隨 GPS 改。Core 路徑驗證與 MapKit 取消；精確起點且無前段。準備 1／2／3 次／全失敗、Retry 原 intent/path、Cancel／Stop。

舊 tick 在新 preparation attempts 間真正執行；新 first-point claim 後舊 queued gate 拒絕。Fake native 最大 concurrency 1，不同 latency 無重疊／積壓／catch-up。進度／marker 只 ACK 更新，notSent／unknown／遲到不推進。Pause 在 claim 前後、Resume 同 lease、Running Cancel、Paused 確認返回／確認。最終 ACK 完成、unknown 不完成；Stop／Cancel／新 handoff 後 callback 不復活。

UI 驗草稿、共用搜尋／收藏、規劃／準備、精簡運作／暫停、確認窗、完成提示、三語／深色／最大字級。模擬器不製造 native ACK；真正 scheduler 由 Core injected command seam 驗，不當手機效果。

06 不提前加入多點、來回、GPX、最愛路線、搖桿、背景恢復或持久化 execution。

## Advisor 核准的競態優先順序

規劃前擷取 routeAdmissionRevision；接受 Start／Go／Route／Stop／Restore／Reset 時同步遞增，健康 tick 不遞增。遲到規劃不得越過使用者較新動作。已接受 route 的 Retry 只略過原規劃 revision 比較，仍須符合原 intent 身分、目前 unknown lock 與 lifecycle guards。

未 claim 的一般 tick notSent 只有在相同 execution 仍 running 且未有 Pause／Cancel／Stop／handoff 接管時才變 interrupted；中斷不可 Resume，須 Cancel 再明確開始。Pause 作廢的 tick 收斂為 paused，Cancel 收斂取消，Stop／handoff 遲到結果抑制。已 claim 的 notSent 與 unconfirmed 仍 unknown 且須 Stop。

Pause 在 claim 後可接收一次相符 ACK；若正是最終端點，優先自然完成。Cancel／Stop／新交接不發布舊 ACK。activeElapsed 從 running 起算，包含 pausing／native 等待，排除 paused；下一步仍只在 ACK 後重新等 500ms。

Standards 複查補強共用 CandidateController：已有候選後輸入新非空名稱，未明確選取新 options 前不可 Go／Confirm；保留舊候選及星號，不以搜尋結果自動預選。空 query 只解除名稱改查的未選取鎖，不能解除無效座標鎖；明確有效選取或有效座標才解除後者。這避免 route picker 在舊 option 已隱藏時悄悄確認舊地點。

## 端點道路吸附限定（本票 Spec 複查後新核准）

2026-10-17 Advisor 核准 50m 為明確上限，並非先前已有的數值規則。原始路徑先驗點數／去重／正距離；其第一點到明確起點、最後點到明確終點的有限球面距離各須 <=50m。超限整份失敗，不能用任意長直線補齊。合格時以 prepend／append 補入不相同的精確端點，保留每個原始道路頂點，再去重、檢查最終 10,000 點上限及正距離。這是所選地點到道路網的有界吸附，不是目前裝置位置到指定起點的接近路段；第一筆 native 仍精確起點、ACK 後零進度。真實 MapKit probe 若超限，回報實測偏差並重新決策，不能為讓測試過而偷偷放寬。

## 取消後的實際結果

waitForRouteIdle 回傳 RouteIdleSettlement：settled 或 requiresStop(failure)。Cancel 即時撤 lease／gate，但保留 pending context 與忙碌，等真正返回。只有未 claim 的 notSent 或已 claim 的驗證 ACK 可安全收斂；已 claim notSent、任何 unconfirmed、沒有 claim 的 ACK 都隔離為未知並要求 Stop，不因取消而解鎖；晚 ACK 不發布位置／進度。Controller 明確使用 typed settlement，不靠 Combine 發布時序推測安全。Stop generation 在撤任務前遞增，較早命令未知不得重鎖已停止狀態，mandatory clear 仍排在實際返回後；未知 owner 留到 Stop 通知結束。

## 最新使用者地圖 Pin 規則（取代原編輯情境 No Pin）

使用者明確要求路線地點編輯也能用 map Pin 帶入地名／地址／經緯度，Pin 上不可有 Go。只在 active picker 顯示共用 44pt Pin／詳情操作；Confirm 才改草稿，Cancel 保留原節點。Map tap 立即建立精確座標候選，App 可取消的 MKReverseGeocodingRequest 經 Core PlaceResolving 僅補 metadata。Advisor 核准必須重建 .coordinate(exactTap) MapPlace、保留原候選 UUID 與精確座標，忽略 resolver 回傳的 id／座標；query／select／新 map tap 以既有 revision 作廢舊結果，nil／error 保留座標且不冒充名稱搜尋錯誤。反向查詢不開始規劃或移動。

Confirm 可凍結立即座標，遲到 metadata 不能寫已關閉／換位 picker。Root camera 依 UUID 去重，僅補地名不得重新置中；編輯 Pin 仍保留兩倍實測 Pin 高度的可見區，Go 只屬瞬移。搜尋選項及星號不因短鍵盤 viewport 直接刪除，必要時整張搜尋面板捲動可達；模式控制用實際 44pt 語意按鈕。舊 Figma 快取的 No Pin 為已被使用者取代的設計，本輪 Console transport closed，沒有聲稱回寫。


## 短高度版面補強

回歸實測：模式列加入後，瞬移最大字級＋鍵盤令搜尋 input 底部超出鍵盤上緣；原 Spacer 硬編碼 44pt 回中高度也多預留空間。改以實測回中／Pin 高度共用同一 map band。Advisor 另核准只在實際高度不足時採精簡狀態 card：一般真實位置省略視覺上重複的「目前位置」標題，保留服務狀態與完整 44pt 控制；模擬來源仍可見，未知狀態仍可見，VoiceOver 一律包含來源及狀態。以正常 card 的穩定實測高度判斷，不以精簡後 topFrame 反向切換；空間恢復自動還原，旋轉／字級改變重新量測。這是版面補強，不新增模式或移動能力。


最大字級輸入框以實測 input 高度＋padding 作搜尋面板最小高度；不能以固定 76pt 裁切 65pt 字級加邊距。路線編輯的上層 ScrollView 以底部 anchor 保持搜尋框完整可見，長標題／取消仍可向上捲回，Confirm 固定在捲動區外。Debug simulator 沿用明確 map metrics 旗標回報實際 viewport，測試須驗完整輸入與 44pt 清除控制在 viewport 內且不撞 Confirm，不能以 AX content rect 代替裁切後可見範圍。
