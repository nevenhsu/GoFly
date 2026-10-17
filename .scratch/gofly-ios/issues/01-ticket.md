# 01: 正式 App：地圖、服務啟停與 GPS／VPN 修復

**Status:** verification-pending

**Blocked by:** 無，可立即開始。

**What to build:** 打開正式 GoFly，看到真實服務狀態；可啟動服務待命及停止，整個過程不自動移動。

**Design reference:** 01 B06、07 C01、11 共用狀態。

**Acceptance criteria:**

- [x] 正式產品 target、資料空間及裝置 adapter 的邊界明確；prototype 僅作參考，擬沿用部分逐項審查、保留來源授權並重新驗證。
- [x] Uber 風格 token 首先套用可操作的地圖、頂部位置／狀態與設定服務 card；服務、任務、候選、實際結果分開表示。
- [ ] 啟動只準備服務；無任務時暫停停用；停止使舊準備／排程與遲到結果失效。裝置未就緒時首頁直接顯示可關閉的具體原因，不能只退回 Stopped 並把原因藏在設定。
- [ ] 停止送點、裝置 clear 確認、有效真實 GPS 分別記錄；clear 失敗顯示已停止・GPS 待確認。停止後可獨立恢復 GPS／重置 VPN，操作互斥；重置僅修復 GoFly 端連線、不清使用者資料、不控制 LocalDevVPN 開關、不等同 clear，GPS 未授權仍可要求清除。

**Verification:** 正式 target 建置；service adapter 的成功／失敗／取消測試；已備妥測試機驗證啟動不送點。

**Device design update:** 目前位置只顯示箭頭與輪廓邊線，移除圓形底。Stop 後等待有效 GPS 才顯示箭頭，不以 clear ACK 假定已取得真實位置。

## Implementation record

2026-10-17：正式 GoFly target、純 Swift core 與同 session 原生 adapter 已建立。最終 12 項核心測試、2 項 simulator UI 測試及實際深色／最大字級補驗通過；最新 unsigned iPhoneOS／iPhoneSimulator App 與 UI test target 均 build-for-testing 成功。真機觀察見下方最新紀錄；其餘裝置驗收未完成，未標完成。

審查修正：Restore 逾時後 Stop 的重複 clear、GPS 證據依賴與配對拒絕分類已修正。原生固定 idevice commit 加 verify-only patch，禁止 fallback pair-setup；4 項 Rust 回歸、5 項 Swift 6 錯誤契約、29 個 API／符號、C layout 與 plist enum ABI 檢查通過；新 archive 的 manifest／輸入輸出 hash 已由 root 核對。Standards／Spec 獨立審查皆無剩餘程式 finding。

使用者已連接 iOS 27.0.1 測試機，Developer Mode、Xcode DDI services 與 LocalDevVPN 已確認，並確認既有模擬定位已停止清除。使用者明確授權同 Team 的 Apple provisioning／正式 bundle 安裝驗收後，com.neven.gofly 0.1.0(1) 簽署、描述檔裝置清單／有效期與安裝均通過。依 Advisor 核准程序單次交付同機既有私有配對，實際 app decoder 核對 fresh transaction success receipt，未重新配對或改動 prototype；M1 正式 Mac 安裝器仍待開發。使用者已觀察 Service ready、Stop 後真實位置，以及延遲出現有效目前位置 marker。首頁錯誤提示（含新錯誤朗讀）與無圓底箭頭已完成 build 2 signed build、最新 simulator 定向回歸（1 項／0 失敗）及 Standards／Spec 複查，更新至手機並核對既有同一私有回報保持；exact clear ACK、Restore、Reset、拔 USB 與 VoiceOver 實際朗讀尚待驗證，不把目前觀察擴大成完整驗收。
