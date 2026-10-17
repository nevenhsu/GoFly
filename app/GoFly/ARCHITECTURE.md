# 正式 GoFly：票 01 邊界

2026-10-17。範圍為正式 App 的地圖、裝置服務啟停與恢復 GPS／VPN 修復。既有 iOS 專案維持 prototype，不把它的完成紀錄繼承為正式驗收。

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
- Stop 立即作廢舊結果的發布權，但它排定的安全 clear 必須執行。準備工作先返回，再執行 clear；新 Start／Restore／Reset 不越過尚未返回的清理。
- 原生全域網路 timeout 在任何 FFI 前設為 10 秒；controller 另有 watchdog。watchdog 逾時只回報未知，**不算原生完成**，不釋放還在使用的 handle、不平行另開操作，也不解除 `nativeBusy`。
- repairRequired 且底層未返回時，只能冪等 Stop，確保恰一筆 clear 排隊；其他副作用命令拒絕。真正返回且安全清理已執行後才解鎖。遲到成功不能覆寫逾時／Stop 的未知結果。
- 任一世代最多一個服務操作；controller 與 native queue 都維持 FIFO。GPS 不作為 prepare／clear 的前置條件。

## 審查與證據

在執行前由獨立 reviewer 作 Advisor 審查，要求同 session 身分、不可取消的 clear、真正完成與 watchdog 分開、target 分離及來源 allowlist；以上已納入。測試界線沿用票 01 的 service public interface 及 device 系統邊界，不測私有欄位。

自動化測試只證明 host 狀態／故障注入。device build、simulator build、模擬器畫面與實機定位效果分開記錄；沒有裝置結果不結票。沿用 setup 來源見 `NativeSources.json`；正式 native 來源固定 idevice commit `3854a5df4a5a6dee71ffce4d8befc2ea356a8065` 加窄幅安全 patch，重建證據另記 commit／lockfile／patch／header／archive hash。Swift 只匯入 allowlist shim，不匯入完整 generated header。舊 archive 的通過建置不能代替這份安全修正版的重新建置或裝置驗收。
