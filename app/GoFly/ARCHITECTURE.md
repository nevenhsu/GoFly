# 正式 GoFly：服務、首次流程與單點瞬移

2026-10-17。票 01 為正式 App 的地圖、裝置服務啟停與恢復 GPS／VPN 修復；票 02 加入首次開啟、選用定位與必要 VPN 確認。既有 iOS 專案維持 prototype，不把它的完成紀錄繼承為正式驗收。

## Target 與資料

- `GoFlyCore`：Swift 6 純 Swift 服務 protocol、狀態及驗證邊界，可在 macOS 執行測試，不連結原生 archive。
- `GoFly`：iOS 26+ SwiftUI App，獨立 `com.neven.gofly` sandbox。App／Device／Resources 為正式來源；只明列沿用配對 store、setup codec、handoff 三個來源，不編入 prototype UI、JIT、診斷或 DDI 下載服務。
- `iphoneos` 才匯入／連結 arm64 device FFI；模擬器使用明確失敗的 device-required adapter，不用假成功掩蓋原生能力限制。
- 首次配對交付沿用既有版本化的私密 Mac handoff，位於新 App 自己的 Application Support。Mac 的目標 bundle profile 固定正式 App；M1 已完成軟體實作，裝置驗證仍待集中執行，不能讀取另一 App 的 sandbox 當作資料移轉。

## 身分與原生生命週期

Native adapter 串行擁有自己的 session，配對核對、DDI 與 clear 都使用該 session 的同一 adapter／handshake；重新開 session 必須重新讀取並核對綁定 UDID。通道只可透過固定版本重建的 verify-only export，驗證失敗直接回傳，不能走 pair-setup。原有 archive 的通用連線 API 會在失敗後嘗試配對，正式 target 禁用。任何實際裝置寫入前都再核對身分，原始 RP／UDID／原生錯誤不記錄到 UI 或一般 log。

Start 只驗證裝置、必要支援及定位服務可用，不接收座標也不呼叫 set。缺支援資料由 Mac 處理；僅重用／掛載已交付的必要項目，不下載。Native Cryptex 掛載可能需要 Apple 簽名網路，這不代表下載支援檔；該分支實機效果待驗證。

清理順序是 location → remote server → handshake → adapter，包含部分建立失敗。Reset 只處理 GoFly 自己的連線／探測，重新實測可達性；不 clear、不 mount、不切換 LocalDevVPN、不刪使用者資料。

## 狀態與命令不變量

- 服務狀態、本機送點終止、裝置清除確認、有效實際位置是獨立結果。沒有 clear 回覆，不宣稱解除模擬；沒有有效新位置，不宣稱取得 GPS；不以此推導其他接收 App 已恢復。
- `realLocation` 僅保存目前接受的 GPS 證據；Stop／Restore 或拒絕讀值仍將其設為 nil。最後顯示座標與來源另外保存在 controller 私有記憶體，僅透過唯讀 `positionMarker` 投影供地圖顯示：等待時 50% 透明、有效時 100%，無圓底；未曾取得有效位置時不畫箭頭。快取不持久化、不供路線起點或 clear 判斷，已確認模擬位置優先於 GPS 顯示與鏡頭；尚無模擬位置時才使用新接受的 `realLocation`。Reset 本身不清除位置；clear 前有效位置可顯示，但只有 clear 後的有效觀察才證明恢復序列。
- Stop 立即作廢舊結果的發布權，但它排定的安全 clear 必須執行。準備工作先返回，再執行 clear；新 Start／Restore／Reset 不越過尚未返回的清理。
- 原生全域網路 timeout 在任何 FFI 前設為 10 秒；controller 另有 watchdog。watchdog 逾時只回報未知，**不算原生完成**，不釋放還在使用的 handle、不平行另開操作，也不解除 `nativeBusy`。
- repairRequired 且底層未返回時，只能冪等 Stop，確保恰一筆 clear 排隊；其他副作用命令拒絕。真正返回且安全清理已執行後才解鎖。遲到成功不能覆寫逾時／Stop 的未知結果。
- 任一世代最多一個服務操作；controller 與 native queue 都維持 FIFO。GPS 不作為 prepare／clear 的前置條件。
- 從首頁 Start 發生的服務失敗，直接以可關閉的非模態提示顯示具體原因；關閉只隱藏提示，不清除服務錯誤、改變停止狀態或宣稱修復成功。

## 審查與證據

在執行前由獨立 reviewer 作 Advisor 審查，要求同 session 身分、不可取消的 clear、真正完成與 watchdog 分開、target 分離及來源 allowlist；以上已納入。測試界線沿用票 01 的 service public interface 及 device 系統邊界，不測私有欄位。

自動化測試只證明 host 狀態／故障注入。device build、simulator build、模擬器畫面與實機定位效果分開記錄；沒有裝置結果不標 done，但可標 Implementation: complete 並維持 verification-pending／deferred-by-user；前置實作與自動驗證完成即可繼續後續票。依使用者安排，開發期間不要求接 iPhone、不等待 USB、不安裝或操作實機，全部完成後才由使用者集中測試，含背景與跨端項目。沿用 setup 來源見 `NativeSources.json`；正式 native 來源固定 idevice commit `3854a5df4a5a6dee71ffce4d8befc2ea356a8065` 加窄幅安全 patch，重建證據另記 commit／lockfile／patch／header／archive hash。Swift 只匯入 allowlist shim，不匯入完整 generated header。舊 archive 的通過建置不能代替這份安全修正版的重新建置或裝置驗收。

## 首次流程（票 02）

歡迎 → 選用定位 → VPN 通道 → 地圖。允許、拒絕與略過定位皆能繼續；此步只要求權限，不要求 GPS fix。GPS 小提示與位置有效性沿用地圖既有獨立邊界。首次／完成引導及外部返回都不啟動服務或送點。

- `GoFlyCore.OnboardingController` 依公開 `TunnelProbing`／`LocationAuthorizing` 及可注入單調時鐘管理流程，Core 不知道端點、Network.framework 或 UserDefaults。權限及 VPN 各自作廢離頁舊 callback。
- `GoFlyTransport` 單向依賴 Core，擁有 Network.framework 探測與唯一 `LocalTunnelEndpoint` 生產設定（10.7.0.1:49152、兩秒逾時）。App／同步 native reset 共用該設定；reset 仍在既有 native serial queue 執行。任意端點及短 timeout 只作 internal host-test 注入。
- VPN 頁可見且前景 active 時立即檢查，之後維持每五秒起始節奏；一筆尚未完成就合併檢查，不重疊或補跑積壓 tick。定時複查保留上次結果，失敗才撤銷下一步可用性。
- 按下一步後必須新建一次 probe；若已有檢查，等待其真正返回，再執行下一步專用新 probe。只有目前頁面／scene 世代的這次成功會同步呼叫 App root，寫入 `gofly.onboarding.complete`，接著顯示 stopped 地圖。一般檢查成功不會完成引導。
- 離頁或背景取消 probe、timer 及下一步授權；即使舊 probe 忽略取消並遲到成功，也不能更新 UI 或旗標。重新進入須等待舊操作返回後再探測。Network adapter 每次建新連線，以串行唯一終止 gate 處理 ready／failed／timeout／cancel，包含 continuation 安裝前取消，所有終止路徑關閉連線且僅 resume 一次。
- 「開啟 LocalDevVPN」使用 plain `localdevvpn://`，不開 enable／disable 路徑；開啟失敗才回退 App Store，再失敗顯示原因。2026-10-17 已核對官方 [scheme 註冊](https://github.com/jkcoxson/LocalDevVPN/blob/main/LocalDevVPN/Info.plist) 與 [URL handler](https://github.com/jkcoxson/LocalDevVPN/blob/main/LocalDevVPN/LocalDevVPNApp.swift)；已安裝版本的實際外部開啟仍需真機確認，不能將 URL completion 視為 VPN 成功。
- 已完成引導的地圖 UI 測試以明確 defaults fixture 進入地圖；首次失敗 UI 僅 Debug simulator 可選 real localhost:0 拒絕連線 fixture，不製造 VPN／native 成功。Release 沒有此入口。

Figma Console 既有本機讀回／截圖保留於 work/design-localgo-v2；本次重連顯示 Transport closed，未宣稱重新讀回成功或修改 Figma。畫面依已核可同輪線框內容及 DESIGN.md 的 Uber 語意樣式轉譯。

## 搜尋與單點瞬移（票 03）

`GeoCoordinate` 在建構時拒絕非有限或超界值；`MapPlace` 保留 MapKit／座標身分、單一 title 與精確座標。`TeleportCandidate` 每次選取產生獨立 ID，與地點身分分開。`CandidateController` 只依公開 `PlaceSearching` 取得資料，沒有裝置命令能力；實際 MapKit lookup 可取消，Core 同時以取消及 query 世代防止舊結果發布。名稱初次搜尋不預選，有效座標自動選取；無效格式／緯度／經度保留舊候選但鎖 Go，清空輸入不偷偷恢復舊 Go，明確有效選取才恢復。地圖選點不將顯示格式的小數截位寫回實際座標。

Go 捕捉整份候選與新操作 ID；`ServiceController` 將它與 Start／Stop／Restore／Reset 共用 FIFO、nativeBusy 與 watchdog。`PointDispatchGate` 的同步 claim 是最後派送門檻：同-session 身分確認後、native set 前才可跨過。Stop／watchdog 在此前作廢 gate 就不送點；跨過後不假裝取消 FFI，clear 必須等待其實際返回。點選／移動鏡頭不會進這條命令路徑。票 03 不自動重試，三次準備與任務交接由票 04 接入。

結果分為 not-sent、acknowledged、unconfirmed。準備失敗保留先前位置證據並可明確重試；set 一旦派送，只有經核對的同請求成功回覆能確認，其他錯誤／逾時皆 unconfirmed，保留候選、鎖所有 Go，直到明確 Stop 完成。新的有效 GPS 可更新畫面，但無法解除未知命令鎖。成功回報只可清除同一 candidate ID，新瀏覽而未提交的候選保留。

Native 原本 set／clear 只讀下一則 DTX message，現以獨立 location-reply.patch 補強兩者共用的 correlated void helper：核對保留的 ID、正規化 channel、conversation 1、無 reply-expected，接受空 OK 或 raw archive 證實的 null／NSNull；拒絕錯誤、非 null 物件與不明格式。整體 deadline 包含 send／flush／wait／validation，所有出口清除 pending ID；遲到 set 回覆不能冒充 clear。協定確認不等同接收 App 已觀察位置。Swift shim 增至 30 個宣告，來源、patch、header、archive 及 ABI 證據一起更新。

Native adapter 在既有 serial queue 保留同一 location session，acknowledged 與 unconfirmed set 後都不立即關閉；首次 Go 與 Start 都會先消費私有 setup handoff。既有 session 的下一次準備重用該 session，失敗不破壞舊位置。clear 只嘗試一次、真正返回後才關閉（包含失敗）；後續明確 Restore 可另開新 session。Reset 不關閉 active session、不宣告 clear。

派送門檻作廢目前 GPS／模擬位置與先前 clear 證據，只保留等待中的顯示快取；確認回覆後才發布模擬位置。Stop／Restore 保留最後箭頭為 50% 透明，新的有效 GPS 才更新並恢復實心。`PositionMarker` 含來源，不能以模擬座標捏造 `RealLocationObservation` 或把快取當路線起點。

地圖由獨立 MKMapView canvas 提供實際投影，以量測的頂部／底面板界線作 edgePadding；候選與成功位置、viewport 變更才發出 revisioned camera intent，保持非零 map rect 與現有縮放。拖圖只更新畫面，不反覆拉回或送點。候選 Pin、其上方 Go、詳情各自獨立；圖示下方無 caption，鍵盤已反映在面板位置時不重扣高度。Debug simulator 的投影量測僅在明確測試旗標下供實際 UI 驗證，不製造 native 成功。

鏡頭採最新明確選取優先：一般 GPS callback 不覆蓋仍存在的候選鏡頭。成功 ACK 清除原候選後置中確認模擬位置；若準備期間已瀏覽另一 candidate ID，保留新候選及其鏡頭，仍更新模擬箭頭。明確回中可切到目前位置。


## 準備與任務交接（票 04）

`PreparedOperationSnapshot` 將要求 ID、原來源／point intent、有效的 1–3 次嘗試與 preparing／failed／cancelled 狀態分開記錄。Core 在一個 watchdog round 內最多呼叫 adapter 三次，只接受 notSent 且 gate 仍 available 的重試；已 claim、unknown、取消、Stop 或過期世代都不重送。新 retry round 從保存的失敗來源建立新 ID／gate，不能改投目前正在瀏覽的另一候選。Start 仍只準備服務。

取消準備只撤回尚未派送的新要求，不清除位置、不重設健康舊任務。取消輸給最後 claim 時必須回報失敗；成功取消後仍等 native 實際返回才解開忙碌。失敗面板取消只移除該失敗要求。Stop 與取消不同：Stop 即時撤銷要求與目前任務權限，再按原 FIFO 要求 clear。

`MovementTaskAuthority` 以有版本的 snapshot 與 lease 作同步比較及替換；健康證據與 running／paused 狀態分開。新準備失敗不自行判定舊任務中斷；來自該 lease 的實際結果才能變更健康。最後的 gate claim 在 lock 內完成 authority 比較與新舊 lease 替換，authority 不反向呼叫 gate。交接後排隊舊 lease 不得寫入；新 lease 在 ACK 前為 unknown，不允許下一筆任務送點。只有仍有效的新要求之確認 ACK 能發布健康，遲到 ACK／Stop／clear 均不得復活舊 lease。06／11 排程每一筆命令必須使用此權限，不另建繞過路徑。

共用 SwiftUI 底面板呈現 O11／O12／O14／O16，沿用實際量測的地圖 viewport；返回未知結果的地圖仍保留 Core 鎖與 Pin 詳情。錯誤使用不透明語意底面，避免地圖內容透出而降低具體原因的可讀性。Debug simulator 的 `-gofly-ui-preparation-delay` 只延遲既有 deviceRequired 失敗，不 claim gate 或偽造成功；明確啟用的 operation metrics 只讀取實際 request／source 身分，供 UI 原來源與新 round 驗證，Release 不包含這些測試入口。

H06 的已停止／GPS 待確認仍可 Start，GPS／clear 不作為準備門檻；O16 未終結的位置命令未知維持原 Go 鎖，由明確 Stop 作廢舊要求後才建立新操作。兩種待確認不能混成同一服務狀態。


## 地點最愛與標籤（票 05）

`FavoritePlacesStore` 是 MainActor 上唯一收藏真相；所有搜尋卡片、Pin 詳情、清單及編輯頁共享同一 instance。`FavoritePlaceKey` 由來源身分與精確座標組成，名稱／地址／標籤不作識別。座標來源的 associated coordinate 必須與實際座標一致。MapPlace 新增可選 address，title 仍依名稱→地址→座標備援；直接輸入座標不反查換 title。自訂 label 與原名稱分開。

正式私有檔案是 Application Support/FavoritePlaces/favorites.json，獨立於 prototype 與配對資料。版本 1 的 DTO 保存 schemaVersion／favorites，以及各筆 identity(kind/value)、coordinate(latitude/longitude)、title、可選 address／label；解碼重新經過 GeoCoordinate 與完整筆數／字串／重複 key 驗證，不直接 synthesis runtime 模型。上限 100 筆、1 MiB、label 120／title 512／address 2048 characters、MapKit ID 2048 UTF-8 bytes。

星號／標籤先生成完整 proposed archive，再原子寫入成功，最後才發布 favorites。File adapter 以 no-follow FD 檢查一般檔案、限制讀取量，使用 0700 目錄／0600 檔案與 iOS completeUntilFirstUserAuthentication；保留正常備份資格。相同目錄 staging 完成權限、保護、寫入及 fsync 後，以單次 rename 作最後 commit，不在其後做可能拋錯的必要工作。precommit 失敗保留原 bytes 與 observer 狀態。損壞／未知版本／非一般檔案進 mutation-blocked；已載入後 target 變成非一般檔案也封鎖，不覆蓋原路徑。瞬時寫入失敗則保持舊值並允許明確再操作。

Label editor 保存被長按項目的不可變 key／place 與本地草稿；星號即時提交，remove/re-add 僅取最後成功保存的 label，草稿不進 cache。Save 僅在仍為 favorite 時更新 label；Cancel 只放棄草稿、不回滾星號。移除只依已保存 key，不要求保存新搜尋結果的顯示 metadata。列表短按選點、長按編輯、44pt 星號區各自獨立；一個根 sheet 協調清單與點擊時的 Pin 詳情，呈現 sheet 時底層地圖從 accessibility tree 隱藏，避免操作落到背景。O16 返回後仍保留 Core Go 鎖，收藏沒有裝置命令能力。

App factory 只建立一份 store；無法準備位置時也建立 blocked store，不能退回健康空資料。Debug simulator 可用有效 UUID 選獨立的真實檔案 namespace；明確的 unknown-point fault fixture 只令 Core 進 unconfirmed，不製造 native ACK、GPS 或接收 App 位置證據，Release 不含這些入口。

完整 suite 揭露百筆同步儲存驗證會干擾舊 20–40ms wall-clock 測試；經 Advisor 核准，ServiceController 注入 watchdogSleep（正式仍 Task.sleep），測試以每筆獨立可取消 waiter 在觀察 native 邊界後觸發，保留原 watchdog／nativeBusy／FIFO 語意，不提高正式 timeout 或提前解除忙碌。

## 兩點路線（票 06）

`RouteDraft` 與 `RouteExecutionIntent` 分離，兩個穩定 node ID 的地點 picker 使用獨立候選；Confirm 才回填同一節點。收藏直接寫共用 store，Cancel 只丟棄地點草稿。路線地點編輯依最新使用者要求顯示選點 Pin／共用詳情，但沒有 Go；搜尋、最愛及地圖選點均由明確確認寫入草稿。運作／暫停只留進度與取消／暫停／繼續，不提供模式切換或地點編輯。

`RoutePlanning` 純規劃；App 以可取消的 MapKit 步行 directions 提供路徑，失敗不替換直線。開始時凍結精確首尾與速度；目前位置只用確認模擬位置或當下仍有效的 GPS，等待箭頭快取不是座標來源。路徑限制與相鄰重複點驗證在 Core，第一筆送精確起點，第一 ACK 的進度為零，沒有接近起點的額外路段。

`ServiceController` 為唯一裝置命令 owner；每次 adapter call 進私有 FIFO pump，實際返回並完成 completion 後才取下一筆。準備重試重新排尾，舊健康任務的送點可在 attempts 間完成；每 lease 最多一筆 queued／in-flight tick。所有最後派送仍須通過 verified native gate。Stop 立即撤權，但 clear 等已 claim 呼叫真正返回，不能把 async 取消當 FFI 已停。

規劃前擷取 admission revision，較新的明確使用者動作會使遲到規劃失效；健康 ticks 不遞增。Retry 只略過原規劃 revision，不能略過身分、unknown lock 或 lifecycle guards。已派送未知停止排程並要求 Stop；未 claim 的一般失敗只在仍屬相同 running execution 時標 interrupted，不能蓋過 Pause／Cancel／Stop／handoff。

每筆 ACK 後重新等單調 500ms cadence，再前進一個 cadence 距離，不補 native latency、暫停或排隊期間漏掉的步數。ACK 才更新進度及模擬位置。Pause 保留同 lease／路徑／進度並等待已 claim 結果；最終端點 ACK 優先自然完成。Cancel 撤回精確 lease、等待實際返回，不 clear，保留草稿與最後確認位置；Stop／Cancel／新交接的遲到 ACK 不得發布或復活舊任務。

Debug simulator 的 route-planning-delay 只產生可取消的延遲規劃失敗，不提供路徑、不呼叫 native、不製造 ACK。Core injected command／clock 測試與模擬器 UI 證據不代替最後手機／接收 App 驗收。

票 06 共用搜尋複查補強：新非空名稱 query 必須重新明確選取才可 Go／Confirm，搜尋過程保留舊候選與其收藏。空 query 不刪除原地點，只解除名稱改查鎖；無效座標鎖仍須有效選取／修正。Route picker 的最愛入口依空 query 或無 options 顯示，與鍵盤焦點無關；每次開 picker 產生新的聚焦要求，確認按鈕固定於可見鍵盤上方，長內容可捲動。

路線端點先驗道路吸附：原始路徑首尾各在所選端點 50m 內才補入精確端點，保留所有原始道路頂點，最終仍最多 10,000 點。超限拒絕整條路線，不能任意改寫 raw 首尾而製造長直線；這與禁止目前位置到明確起點的 approach leg 分別驗證。取消後的 waitForRouteIdle 以 RouteIdleSettlement 明確回報 settled／requiresStop；未知命令不能因 Cancel 而解鎖，只有明確 Stop generation 接管後才忽略舊不確定結果，clear 仍等實際返回。

`PlaceResolving` 是可選的 map metadata 邊界，只有路線 active picker 傳入正式 MapKit reverse-geocoding adapter；原瞬移 map tap 預設不補查詢。Core 立即建立精確座標候選，再以 revision／UUID／exact coordinate 核對遲到結果，只接受名稱／地址並重建原座標身分。任何輸入或選取使待回覆失效；nil／error 保留可用座標，不冒充搜尋或 native 狀態。Confirm snapshot 與候選不同，後續 metadata 不改已提交草稿。Root camera 依候選 UUID 去重，因此補資料不打斷手動 pan。

搜尋面板在短 viewport 仍保留完整選項／星號：一般空間內清單捲動，不能容納最小選項時改整個面板捲動，不以 availableResultsHeight 判斷移除地點。輸入、星號及清除均可捲動抵達，面板仍受鍵盤調整後的可見高度限制。


相機只在已發布完成的 activeCandidate UUID onChange 時建立選點 intent，避免 @Published willSet 與舊值身分 guard 阻擋新選點；同 UUID metadata 補資料不搶鏡頭。地圖帶高度統一依實測 Pin／回中控制計算。瞬移短高度以正常狀態 card 的保留實測高度判斷是否精簡，不能依精簡後 topFrame 造成震盪；精簡只省略真實位置的重複標題，保留狀態、模擬來源、未知提示、44pt 控制及完整 VoiceOver 來源／狀態，空間恢復自動還原。


RouteExecutionController 擁有目前 picker candidates 的 objectWillChange 訂閱並轉發 aggregate 的公開通知，讓父層地圖與編輯子面板同步收到候選／metadata／搜尋變化。picker 關閉或替換即取消舊訂閱，舊 session 完成不再觸發 aggregate；候選 UUID 仍是相機選點更新依據，不因補名稱而重新置中。公開 observable 邊界測試覆蓋 Confirm／Cancel／替換後解除及新 session 接續通知。


搜尋面板的最小可見高度依實際 input 列與上下 padding 量測，不能以固定 76pt 截掉最大字級輸入。Route picker 保持 Confirm 獨立固定，焦點輸入必須完整位於上層可捲動 viewport，不能只因 AX content rect 尚存在而視為可見；Debug simulator 實際幾何量測只用既有明確測試旗標、不製造位置或命令成功。


## 多點路線（票 07）

Advisor 已核准有效節點0…27（最多25途經點）、穩定身分與依位置衍生角色。RouteNode 不保留空值；預設只有一個動態目前位置。零點／一點新增操作分別為新增起點／目的地；兩點以上新增途經點，滿27停用。Provisional ID 不先插草稿，確認才追加或插在目前終點前，取消無空列。起終點 accessors 可為 nil，少於兩點不可開始。

編輯 session 分開 role／allowsCurrent／isNew／明確清空狀態；清 query 仍只改搜尋，不能刪節點。清空地點專用動作取消搜尋與反查、清候選，確認才刪；新輸入或有效新選取不可沿用刪除狀態。Confirm 仍依穩定 ID 找現存節點；重排刷新角色與目前位置資格，已刪目標拒絕。全序列最多一個 .current，移到中間／終點仍只在 Start 解析一次確認模擬位置或新鮮 GPS；等待快取不能替代。

先凍結全部有序座標並拒絕相鄰相同，逐段順序規劃／驗證50m端點吸附限制，拼接只移除共用界點；全軌最多10,000點。每段後檢查取消與 admission revision，失敗不提交部分 intent。完整不可變路徑沿用06同一 scheduler／FIFO／ACK／未知鎖。

拖曳預覽只改 UI 暫存順序；左側44pt把手開始、整列浮起及等高佔位、長清單邊緣自動捲動，放開才原子套用完整 ID 順序，取消恢復原草稿。中間編輯與右側44pt刪除各自獨立，VoiceOver 排序／刪除走相同 ID mutation。公開Core與模擬器已驗證穩定ID／三命中區44pt／實際整列拖曳及27點邊緣捲動；實際VoiceOver動作、OS中斷手勢與手機位置效果仍待集中驗收。


07 的專用 clear 意圖綁定 Candidate reset 完成後的確切編輯 revision；後續輸入／選取／map tap／reset 永久作廢，回到空 query 不復活。Current 勾選 true 經 stagePickerCurrent(id:) 檢查資格並取消舊查詢／反查，保留候選、query 與驗證鎖但推進 revision；false 不作廢新 clear，Confirm 仍傳本地 useCurrent 並複驗資格。這防止舊 metadata 清掉新勾選，或 Current on/off 後誤刪節點。


## 來回走動（票08）

Advisor核准以同一不可變路徑、速度及lease執行；heading與來回選項是執行期控制。ACK才更新原起點0…終點total的位置軸；端點ACK後依當下選項折返或結束。首次啟用後鎖存位置軸，取消勾選保持方向到下一端點；新執行才重設forward／一般單次。暫停改向或取消勾選維持暫停，取消保留草稿／選項及最後確認位置。

Service以同execution／lease的同步control revision讀取及遞增，讓await callee-entry前計算的舊方向也無法建立派送；只在原子作廢available gate成功時標controlCancelled並抑制其watchdog。已claim命令等待實際結果，真實ACK後從該位置沿最新方向下一cadence；timeout先鎖存則沿用隔離，任意unconfirmed／claimednotSent／無claim卻ACK不能降為安全取消。未claim安全撤回不推進序號／位置，不清除、不換lease。既有FIFO／native最後gate／Stop generation不變。

App同列checkbox與單一無框icon-left改向控件，關閉收起改向但topbar保留實際方向／目標至結束。初始選項放細項，運作／暫停不提供編輯入口。正式實作已通過完整Swift150／UI25與unsigned build10，兩軸無剩餘finding。模擬器只驗真實編輯／規劃與可達介面，active往返與實際接收App效果仍待手機集中驗收。


## GPX完整來源與匯入清單（票09）

GPXDocument使用tracks（保留track→segments分組）／routes（每route一段）／ordered waypoints單一來源，所有原始點與重複點保留。嚴格GPX1.1 namespace/version／合法parent，拒絕混合種類、空分組、無效座標及不安全XML；原始檔先max+1 bounded regular-file read，2MiB／10,000點、depth64及100,000元素限制。UTF8/UTF16安全掃描配合entity／DTD拒絕，編碼保留可回讀同Double的非指數座標，不用displayText捨入。

RouteDraftSource明確分manual／gpx完整snapshot，GPX不製造節點；只有Load更新草稿，Start才進既有準備與ACK排程。PlannedRoute(imported:)是唯一可執行性判定，segment必須精確接合且全路徑正長度；gapped或零長度合法文件仍可保存、分段預覽／匯出，但Load停用並說明原因。GPX直接走原軌跡，不MapKit重算或套道路50m吸附。執行用去重不改保存資料；Load／Clear保留speed／roundtrip，刪除紀錄不改已載入snapshot。

ImportedRoutesStore與配對、FavoritePlaces分開；單一persistence actor序列管理immutable UUID payload、versioned manifest、quota／O_EXCL／private modes/protection／fsync-rename／deleteundo／cleanup。實際64MiB上限涵蓋staging／final／undo與orphan，最多100筆，manifest1MiB；commit時重讀最新資料，不跨await套舊proposal。manifest成功才publish，失敗保留observer／selection／undo token；manifest損壞／未知schema不cleanup或覆寫。來源檔永不改／刪，payload hash與filename/kind/count/start/end metadata在選取／Load／Export重驗。

App單一env store由root載入，UUID DEBUGsim namespace只隔離真實檔案。Import測試只用明確flag在按Import時選一個真實GPX來源檔，仍走相同security scope／regular-file／bounded read／codec／store；不是啟動預填、nativeACK或GPSfixture。選取preview逐segment畫線、singleton用sample annotation，不跨gap造線；main route只在明確Load成功後更新。GPXUTType以Info additions登錄，FileDocument只用輸出，不用其整檔reader匯入。正式實作與離線驗證完成：Swift188、unsigned build11、完整UI30case覆蓋（29通過＋唯一test浮點容差修正後AX三語單項重驗通過）、248key三語與native verifier，兩軸零finding；詳細run結果分列work驗證紀錄，不將test誤判run記30／30。Load即保留完整主地圖預覽，取消規劃／準備失敗回編輯仍保留；Clear才移除。手機位置及Files真實儲存／授權仍待集中驗收。


## 完整最愛路線（票10）

Advisor核准獨立FavoriteRoutes manifest／immutable payload，manual有序完整MapPlace、GPX中立GPXRouteSource完整文件及檔名；標籤只改manifest。每次Save獨立UUID，與ImportedRoutes及FavoritePlaces無刪除連動。只抽共用安全FD I/O primitives，不抽domain transaction／quota／undo，保留05/09既有commit與fault語意。

最愛Save純builder捕捉tap-time draft與service.currentRouteOrigin單一值，無效Current只在副本排除，≥2有效點才存；實際commit receipt攜帶omittedUnavailableCurrent，UI明確結果後Done，不能以過期eligibility假稱已保存Current或再讀service。Start仍拒絕未解析Current。FavoriteLoad用controller新發出的token，在async validation後同步檢查、消耗，編輯／picker／Start／Load／Clear或dismiss失效，遲到結果不能覆寫新草稿；speed／roundtrip保留最新值。

正式實作與離線驗證完成：完整Swift231、完整simulator UI35／35（1537.711s）、未簽署iPhoneOS build12、285key三語parser／native verifier／diffcheck及Standards／Spec零finding。完整GPX10k與27點重開讀回、精確標籤及三語最大字級皆通過；實際GPS／接收App／Files與VoiceOver仍集中手機驗收。沒有Figma回寫或手機操作。

## 手動搖桿（票11）

第三個mode沿用唯一ServiceController／native FIFO與PointDispatchGate。Core將畫面向量和實際map camera heading轉為世界方向，按速度、力度及500ms cadence計算球面位移；FIFO head在前序真實回覆後才讀最新有效origin，最後claim才交接owner。純prepare最多三次，成功只代表prepared，不安裝lease或宣稱位置已確認。ACK才更新座標與方向，不追補等待時間、不自動追蹤鏡頭。

放手／歸零撤銷未claim輸入；已claim則等真實結果，確認後保留最後位置及ready服務，不clear。Pause只對已安裝的健康搖桿任務開放，Resume回置中狀態，下次非零手勢建立新意圖。scene非active釋放輸入，回前景不重播；未知結果、watchdog及Stop generation沿既有隔離，遲到ACK不解除。路線與搖桿共用送點擁有權，不建立第二條native queue。

無起點沿02搜尋／最愛／地圖Pin及明確Go，僅對應實際ACK且沒有新候選時返回搖桿；新候選沿03保留。等待GPS的顯示快取不可當起點。現位置箭頭維持fill加outline、無圓底，等待時50%透明；方向相對地圖旋轉顯示。三個mode在空間足夠時用完整pills，不足時改44pt原生Menu；搖桿下方沒有說明文字。漫步擴充見下節（票12）。本節記錄App實作，整合測試、雙軸審查與最後手機驗收分開記錄。

票11正式實作與離線驗證完成：完整Swift269、完整simulator UI38／38（1713.531s）、unsigned iPhoneOS build13、304key三語parser／native verifier／diffcheck及Standards／Spec最後readback零finding。未claim的後續失敗回neutral保留錯誤／最後ACK，新手勢可重試；claimedunknown仍Stop。實際方向手感、接收App與VoiceOver仍集中手機驗收，未以UI fixture捏造GPS或native成功。


## 自動漫步（票12）

漫步為搖桿 checkbox 子功能，沿用同一 Controller／intent／lease／FIFO writer。手動舊 API 保持座標 outcome；新增 recipe overload 及獨立 receipt outcome，由同一 private executor 在真正佇列 head 讀取最新有效 origin、計算 target step 並捕獲 gate。receipt 的座標／方向／targetID／arrival 只在該步實際 ACK 後發布，不在 UI 或 Controller 重算已送出的點。

純 selector 最多32個均勻方向樣本，以目前速度十分鐘距離選球面目標，排除目前點、目標及本次 session 最近100個成功目的地1m內重複；不要求道路或 MapKit routing。target geometry 保留跨日界／極點與固定 antipodal 方向，最後一步 clamp 到精確目的地，零距離仍須 set/ACK。自動／手動共用500ms ACK後時脈及 intent-scope sequence；手動優先、放手取消未claim舊輸入，已claim等真實回覆後才自動前進，不另開 writer。

Go／隨機只改 target與input revision，保留速度、接管、暫停及 owner；舊target receipt仍更新實際位置，但不能宣告新target抵達。抵達無下一站則實際 pause installed healthy lease後保留本地 suspended continuation與重試，不留下 running owner空轉。票12交付時 scene 非 active 一律暫停；目前改依票15：僅相符、健康且有有效實際 grant 的 auto 可繼續，否則暫停或退休未安裝 owner，回前景不自動恢復。實際 Stop或新任務 claim的movementBoundary事件作廢所有舊continuation；admission／failed preparation不是claim證據。

App以獨立CandidateController處理漫步選點，與路線picker／瞬移分開；目前目標空心Pin無Go，候選黑點細線Pin的Go只明確換目標。各44pt詳情固定綁定點擊時place snapshot。選點／抵達／ACK不移鏡頭；明確回中仍可用。路線編輯優先使用自身picker、地圖Pin回填地名／地址／座標且沒有Go。正式實作與離線驗證完成：完整SwiftCore293／36suites＋Transport9／1suite，共302PASS；完整simulator UI39／39 PASS（1767.040s）；未簽署iPhoneOS build14、312key三語parser／native verifier／diffcheck通過，Standards及Spec最後readback零finding。三語AX／keyboard與路線地圖Pin回填無Go回歸通過。不能以source、Core controlled-device或simulator UI宣稱手機／接收App效果；實機驗收仍集中最後進行。


## 連線修復與冷啟動（票13，已實作；手機待驗）

核准v5將連線准入及冷啟動待確認分開：Service與MovementTaskAuthority共用原子派送門檻，連線失敗先封鎖新claim／撤回available，再暫停或退休Controller；已claim只結算實際回覆。TCP成功不改任務健康或自動恢復，Stop／clear／reset不受移動門檻封鎖。

SessionRecovery保存完整既有草稿及data-only歷史／顯示快取，App只有一份store和穩定Controller。冷資料不提供origin／lease／健康證據；native沒有可驗證舊任務的query，所以冷啟動不提供舊Resume。若存有active／uncertainty或既有檔案無法安全讀回，必須實際clear ACK後才可建立新任務；discard、GPS、TCP及reset不能解除hold。缺檔正常fresh defaults，損壞檔禁止自動覆寫。上述程式已整合；完整Swift344、未簽署iPhoneOS build15及兩軸最後readback通過。完整simulator回歸42／43（2017.930s，唯一失敗為舊RT預設值預期），test-only改成先明確設定live速度2／RT0再Load後，受影響單項1／1通過（210.374s）；其餘42項不重跑，合計43案例覆蓋，不將原run稱43／43。手機驗收仍集中最後進行。

持久化使用單一off-MainActor writer，一筆inflight與一筆最新pending；capture只是接受，flush依revision cutline等待實際寫入結果，取消waiter不取消原子寫入。損壞／unsafe／未知schema禁止自動覆寫；儲存失敗不顯示已保存。firstclaim-beforeACK與pending／failed clear分別保存不確定狀態，terminal active=nil；已ACK手動owner保留無方向摘要至實際settlement。Service first-route preparation的dispatch gate也是實際claim證據，不能只看後續tick。


## 背景工作候選（票14交付時未啟用；目前接線見票15）

採核准v5的BGContinuedProcessingTask候選：submission與matching實際launch分開，close-only grant可跨queue同步撤銷；atomic completion固定outcome並回傳有效finish結果，expiry與finite-arrival先贏者唯一完成。Core公共controller／driver seam不認識native writer；實際iOS adapter只編譯、不從App建立／register／submit，15才接入原子派送邊界。有限路線依真ACK距離與實際抵達，來回／漫步保留無期限產品目標、以total=-1實驗，不改有限圈數／時間、不自動renew。SDK／controlled tests不能證明真實scheduler／背景／接收端，全部手機留最後。

票14離線證據：完整SwiftCore355／41suites＋Transport9／1suite，共364PASS；final public focused20／20PASS；未簽署iPhoneOS／iPhoneSimulator SDK27.1 build16皆成功（simulator含arm64／x86_64）；native verifier／diffcheck通過，Standards0／Spec0。App初始化、plist、既有送點／生命週期及三語資源未變，本票未重跑UI；332key三語的13既有驗證仍適用。沒有手機／USB／簽署／安裝／實際scheduler或接收App測試。 literal-wildcard handler dispatch仍是未證實候選，15接線前改以官方完整ID註冊／提交及bounded一次註冊，另經15審查；不得由14建置或controlled callback當作已支援。


## 正式背景接線（票15，已實作／離線驗證；手機未驗）

[核准15v2與凍結介面](../../.scratch/gofly-ios/decisions/15-continuation.md) 將真實ACK／同步明確使用者意圖接入穩定MovementContinuationController；它協調既有Service、route、joystick及recovery，不增加native writer。scene與具體可撤銷grant由同一原子authority在最終claim檢查，expiry於任意queue關閉grant後才送MainActor通知。claimed命令只結算實際結果；回前景不把closed grant重新開啟。

實際App adapter改為process singleton，Info permitted使用wildcard、SDK register／submit使用相同完整UUID；固定256次註冊嘗試，只保留weak handler及identity，耗盡如實拒絕且不自動續租。此為App資源界線，非Apple限制。BGC不需要新增BGProcessing mode或AppDelegate期限接線。程式已整合；完整 Swift 395、未簽署 SDK27.1 device／simulator、352 key 三語及兩軸審查通過，完整 UI 45／45 PASS，審查修正後背景 UI 2／2 與最大字級／淺色單項通過，皆零 runtime warning，Root 完成深淺色及三語可捲動畫面核對。真實 iOS26／27 scheduler、鎖屏／無期限持續及接收 App 位置仍集中最後手機驗收。

票15 v2追加：實際整合bundle原預設多Scene，與process單一Service／driver及Map持有Controller衝突；第二輪Advisor核准明確單一Scene，實際兩 SDK bundle 已讀回 false。未擴充多視窗；App 在 SwiftUI observers 建立前一次建立 GoFlyMovementModel，StateObject 保留同一組 controller／facade；Map 只觀察，變更畫面不可建立第二個送點 owner。


## 偏好與共用設定（票16，已實作／離線驗證；手機未驗）

App 的 `GoFlyPreferences.shared` 保存 `gofly.preferences.v1` 單一 UserDefaults 字典，語言與外觀為同一份已選值；無效欄位個別回退 system，讀取不覆寫。App 用 State 保留同一 singleton，在穩定 root 注入 Locale／preferredColorScheme；語言變更只刷新同一背景工作的文字，服務／路線／搖桿／恢復 owner 不變。本地化查詢讀實際選定 lproj 並明確英文 fallback，Foundation 格式與預先格式化的數字／百分比均使用選定 Locale。座標／檔案資料維持原格式；Apple 地圖標籤及系統權限對話框由 OS 管理。

MKMapView 沿用既有實體、鏡頭與 annotation，實際 trait 使用公開 registerForTraitChanges 更新語意顏色，實際 locale 變更更新 annotation 輔助文字。除明確 DEBUG simulator 旗標下的唯讀實體／trait／鏡頭摘要外，不加入測試用成功狀態。原生 Picker 讀已保存值，明確 accessibilityValue 同步讀同一值，不合成選取狀態。

C01／C03／C04／C05／C06／C07 共用實際狀態與原生導覽。定位服務開關在背景工作讀取，初次未返回時為未知，不在主執行緒呼叫阻塞式查詢；授權／精確定位與背景重新整理讀 OS 實際值。首頁與子頁使用同一狀態投影。配對資料已保存僅代表本機完整性核對；簽名日期未知如實顯示，不開隱藏裝置 session。

Service 的 `TunnelResetState` 以真實 UUID 同步發布 running：准入先關閉實際連線 fence／開始 lifecycle，再發布 incoming 值，最後排入 native reset。Recovery 直接消費 incoming publisher，撤銷舊 probe generation，保留實體 Task 到真正返回；C01／C05 共用 reset 等舊探測排空後才送出。明確同意與實體 Task 身分分開，自身 running 不撤銷自身；直接 Service reset 則作廢等待中的舊同意。Restore／Stop／離開場景撤銷尚未送出的 reset。只有同一 revision、同一仍 running UUID 的實際完成能發布結果；watchdog／取消後遲到回覆只清理實體 bookkeeping。TCP 恢復不提高 native 健康、不解除 cold hold、不恢復 GPS 或自動 Resume。

目前完整 Swift406（Core397／46 suites＋Transport9）、雙 SDK27.1 未簽署 build18、414key三語／格式／實際bundle、native verifier及最後兩軸審查通過；新設定 focused UI、兩種實際系統外觀、三語最大字級巡覽及資料保留檢查已通過，完整UI依來源51b8fb8成功覆蓋60個不同case：原run24PASS／1helper競態FAIL／1取消；throwing單一快照helper修正後1PASS，其餘35／35PASS，零skip／runtime warning。Root讀回精確案例集合及source／binary雜湊，原run結果不改稱全通過，M1未編譯來源不混入。實際權限變更、外部 VPN 成功、背景與接收 App 以及 VoiceOver 留最後集中手機驗收。


## 正式首次安裝資料啟動（M1，軟體完成；手機未驗）

正式首次安裝使用獨立版本化交易，Mac 的實際安裝擁有權、App 的本機資料提交、實際同機支援狀態是三份不同證據。遺失的安裝成功結果保持不明；後來相同 Bundle／nonce 不能反推擁有權，也不能授權啟動、終止、重送或移除。原 protocol1 唯讀及 install 拒絕維持；protocol2 僅 preflight／apply／status／resume。正式產物、Team、裝置、選項及單次 v1 配對交易在私密 journal 綁定，所有寫入前持久化意圖，取消不宣稱回滾。

App 先保留單一 `GoFlySetupBootstrap`，以背景工作讀真實固定交接檔與當前 Bundle 摘要。沒有正式狀態時不讀不存在的描述檔，維持一般啟動；有 request／input／activation 時失敗就鎖在準備畫面。只有 ordinary／completed 決策後才一次建立並保留 `GoFlyRuntimeAssembly` 的服務、任務、商店與首次流程，偏好仍由穩定外層持有。真實輸入及全部支援檔先驗，現有 v1 importer 是唯一配對寫入者；匯入 closure 再綁定實際傳入 bytes／裝置以防檢查後替換。已完成重播不重新匯入或切回舊 generation。

AFC 傳輸權限與正式私密儲存分開：App 對固定 Mac 交接檔執行明確 descriptor 檢查與權限收緊，再交給嚴格 reader；不改 bytes、摘要或身份，不建立成功回報。只接受安全擁有者、regular／directory、單一檔案 link 與已知傳輸模式；symlink／特殊檔／其他權限不修復。App 自己的 activation／response 不走這條權限修復路徑。正常 reader 不因讀取而改權限。

active support pointer 與 bounded receipt history 位於同一份原子提交；rename 後同步錯誤是 commitUnknown，下次讀實際檔案。Native resolver 先驗正式 pointer，只有完全沒有 pointer 才可用舊 Documents/DDI；正式狀態損壞不可混用舊支援。C06 重用啟動時已核對、綁定當前 Bundle 的 Team／日期，不在畫面求值重算大檔。所有資料證據都不代表 VPN、GPS、native ACK 或冷啟動同意，既有 cold hold 不由安裝解除。

正式 pointer 存在時，NativeDeviceService 不再消耗舊 v1 輸入；本次 v1 在實際解碼後核對預期交易 ID。配對狀態採背景唯讀觀察快取，C01／C06 畫面求值不做檔案 IO。Python 在首次啟動前持久化完整 manifest／檔案摘要；只有已核實發布的 formalPublished 階段可讀 activation 或進入第二次啟動，每次重連與寫入仍重新核對裝置、OS、Developer Mode 與信任。

最終軟體檢查與已知限制見 [M1 票](../../.scratch/gofly-ios/issues/M1-first-install.md)。Core458、Mac37、LocalGo52、App聚焦6及受影響既有UI8均通過；build19未簽署裝置建置、三語428鍵、native verifier及雙軸審查已完成。開發未連接、列出、簽署、安裝或操作手機，硬體驗收保持未驗。

## 同機重新安裝與資料還原（M2／17，開發中）

M2 在獨立 protocol3 與同一操作鎖下，先原子提交引用已同步 cutline 的 preparing 紀錄並持續鎖住正常 runtime；複製失敗不解除鎖定，孤立未提交 cutline 沒有 seed／恢復權限。完整來源資料驗證後才轉 ready，由 Mac 完整驗證及同步備份後，才建立移除意圖。完整 owner 鎖定、實體工作排空、nonce／當前程序回報、移除前封存、未知安裝不可接管，以及每類別指標與收據原子提交，均是分段實作的必要條件。不可攜入位置、任務、clear／ACK／GPS 或背景資格。還原意圖與 M1 門檻共同阻擋正常 runtime，全部完成才可進地圖。詳見 [M2 決策](../../.scratch/gofly-ios/decisions/M2-reinstall.md)；目前未宣稱整體交付或裝置結果。
