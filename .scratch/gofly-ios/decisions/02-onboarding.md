# 票 02：首次流程與 VPN 檢查架構

2026-10-17，獨立 Advisor 已核准以下界線。前置設計核准後，票 01 已完成必要真機功能驗收（含拔 USB），票 02 現開始依此界線實作。

## 對外行為

歡迎 → 選用定位權限 → 必要 VPN 確認 → 地圖。允許、拒絕及略過定位都可前進；允許只要求權限，不等待或要求 GPS 座標。VPN 必須實際可達；只有使用者按下一步後的新檢查成功才進地圖。首次啟動、外部返回、VPN 成功與完成 onboarding 都不啟動服務或送點。

完成旗標由 App root 在有效的下一步結果回來時同步寫入，再顯示地圖。已有旗標時直接顯示地圖，服務仍為 stopped。

## 探測與生命週期

- Core 的 TunnelProbing 不知道生產端點；iOS 層只定義一份 10.7.0.1:49152，供 onboarding、native session 與 reset 使用。
- Onboarding 直接呼叫專用 probe，不能呼叫 DeviceService.resetClientConnection；reset 保留自己的服務命令語意。
- Network.framework 實作單次兩秒逾時；ready、failed、timeout、cancel 共用只能完成一次的終止 gate。waiting 是等待路徑變動，必須保留同一條連線直到 ready、failed、cancel 或原期限，不可立即判失敗，也不可因反覆 waiting 延長期限。每個終止路徑都關閉連線；continuation 安裝前取消也必須完成且不得 double resume。
- B01 可見且 scene active 時立即檢查，之後按五秒起始節奏檢查；注入 clock/sleep seam，測試不等待實際五秒。
- 定時、手動、scene-return、下一步共用同一串行 pipeline，永不重疊。手動／外部返回可合併當前檢查；下一步不能接受點擊前已開始的檢查，必須排入新的 probe，或取消並等待當前檢查返回後再開始。
- 離頁／進背景使 generation 失效並取消，不把取消顯示成 unreachable 或 timeout。遲到結果不能更新狀態或完成旗標。
- 定時成功只更新 VPN 狀態；只有目前 generation 的 fresh Next 成功回傳 advanced。
- 定位權限 adapter 與 GPS fix 分離；離開 A02 後的權限 callback 不改變已離開的 generation。

## 驗證界線

2026-10-18 使用者手機回報與說明頁更新：LocalDevVPN 顯示 Connected 並不代表 GoFly 的 TCP 檢查已通過。B01 未檢查顯示「尚未檢查」，失敗顯示「無法連線」，不據此斷言 VPN 未開啟。B06 改成三張編號步驟卡（開啟 LocalDevVPN、連接並允許 VPN 設定、回到 GoFly 檢查）、成功條件說明、本機網路權限與重連提示，以及開啟 LocalDevVPN／開啟 iPhone 系統設定／返回並檢查的動作。使用者回傳系統設定頁並無本機網路選項，因此文案必須說明沒有此選項時直接返回檢查，不推定使用者拒絕權限，也不要求尋找不存在的開關。內容使用可捲動版面、語意字級與深淺色表面；返回說明頁只重新啟用原本串行 probe，不能完成 onboarding 或啟動服務／送點。本次是程式 UI 更新，未修改 Figma 線框。

Public controller/probe seam 驗證單飛、fresh Next、舊結果、取消、節奏及允許／拒絕／略過三種定位結果。既有地圖 UI 測試可明確載入已完成 onboarding 的持久化 fixture，不製造 native 或 VPN 成功。B01 失敗 UI 測試需確定關閉的測試端點，或記錄隔離 simulator 前置，不能假設每台 Mac 都無法連到生產端點。

成功主線仍須實機 LocalDevVPN 驗證；依使用者最新指示，延後至全部實作完成後集中驗收，不阻擋後續實作。M1、背景能力與後續任務票的驗收不因本次架構核准而完成。

## 實作包裝補充核准

Advisor 已核准 Network adapter 放在 `GoFlyTransport` Swift package product（依賴 Core），供 iOS 與 macOS host probe 測試共用；Core 不引入 Network。正式 init 僅固定 endpoint，internal 任意端點／timeout 僅供 @testable；原生 reset 保留同步 Darwin 生命週期，共用唯一 host／port 與兩秒 timeout。
