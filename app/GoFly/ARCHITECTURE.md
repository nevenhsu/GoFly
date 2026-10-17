# 正式 GoFly：服務、首次流程與單點瞬移

2026-10-17。票 01 為正式 App 的地圖、裝置服務啟停與恢復 GPS／VPN 修復；票 02 加入首次開啟、選用定位與必要 VPN 確認。既有 iOS 專案維持 prototype，不把它的完成紀錄繼承為正式驗收。

## Target 與資料

- `GoFlyCore`：Swift 6 純 Swift 服務 protocol、狀態及驗證邊界，可在 macOS 執行測試，不連結原生 archive。
- `GoFly`：iOS 26+ SwiftUI App，獨立 `com.neven.gofly` sandbox。App／Device／Resources 為正式來源；只明列沿用配對 store、setup codec、handoff 三個來源，不編入 prototype UI、JIT、診斷或 DDI 下載服務。
- `iphoneos` 才匯入／連結 arm64 device FFI；模擬器使用明確失敗的 device-required adapter，不用假成功掩蓋原生能力限制。
- 首次配對交付沿用既有版本化的私密 Mac handoff，位於新 App 自己的 Application Support。Mac 的目標 bundle profile 必須改為正式 App；M1 尚待實作／裝置驗證，不能讀取另一 App 的 sandbox 當作資料移轉。

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

自動化測試只證明 host 狀態／故障注入。device build、simulator build、模擬器畫面與實機定位效果分開記錄；沒有裝置結果不結票。沿用 setup 來源見 `NativeSources.json`；正式 native 來源固定 idevice commit `3854a5df4a5a6dee71ffce4d8befc2ea356a8065` 加窄幅安全 patch，重建證據另記 commit／lockfile／patch／header／archive hash。Swift 只匯入 allowlist shim，不匯入完整 generated header。舊 archive 的通過建置不能代替這份安全修正版的重新建置或裝置驗收。

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
