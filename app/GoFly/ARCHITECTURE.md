# 正式 GoFly：服務與首次流程邊界

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
- `realLocation` 僅保存目前接受的 GPS 證據；Stop／Restore 或拒絕讀值仍將其設為 nil。最後一次有效座標另外保存在 controller 私有記憶體，僅透過唯讀 `locationMarker` 投影供地圖顯示：等待時 50% 透明、有效時 100%，無圓底；未曾取得有效位置時不畫箭頭。快取不持久化、不供路線起點或 clear 判斷，鏡頭只追蹤新接受的 `realLocation`。Reset 本身不清除位置；clear 前有效位置可顯示，但只有 clear 後的有效觀察才證明恢復序列。
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
