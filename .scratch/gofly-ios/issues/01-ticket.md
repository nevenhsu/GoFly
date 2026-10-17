# 01: 正式 App：地圖、服務啟停與 GPS／VPN 修復

**Status:** verification-pending

**Blocked by:** 無，可立即開始。

**What to build:** 打開正式 GoFly，看到真實服務狀態；可啟動服務待命及停止，整個過程不自動移動。

**Design reference:** 01 B06、07 C01、11 共用狀態。

**Acceptance criteria:**

- [x] 正式產品 target、資料空間及裝置 adapter 的邊界明確；prototype 僅作參考，擬沿用部分逐項審查、保留來源授權並重新驗證。
- [x] Uber 風格 token 首先套用可操作的地圖、頂部位置／狀態與設定服務 card；服務、任務、候選、實際結果分開表示。
- [ ] 啟動只準備服務；無任務時暫停停用；停止使舊準備／排程與遲到結果失效。裝置未就緒顯示具體原因，不能假正常。
- [ ] 停止送點、裝置 clear 確認、有效真實 GPS 分別記錄；clear 失敗顯示已停止・GPS 待確認。停止後可獨立恢復 GPS／重置 VPN，操作互斥；重置僅修復 GoFly 端連線、不清使用者資料、不控制 LocalDevVPN 開關、不等同 clear，GPS 未授權仍可要求清除。

**Verification:** 正式 target 建置；service adapter 的成功／失敗／取消測試；已備妥測試機驗證啟動不送點。

## Implementation record

2026-10-17：正式 GoFly target、純 Swift core 與同 session 原生 adapter 已建立。最終 12 項核心測試、2 項 simulator UI 測試及實際深色／最大字級補驗通過；最新 unsigned iPhoneOS／iPhoneSimulator App 與 UI test target 均 build-for-testing 成功。真機服務及拔 USB 驗收未執行，未標完成。

審查修正：Restore 逾時後 Stop 的重複 clear、GPS 證據依賴與配對拒絕分類已修正。原生固定 idevice commit 加 verify-only patch，禁止 fallback pair-setup；4 項 Rust 回歸、5 項 Swift 6 錯誤契約、29 個 API／符號、C layout 與 plist enum ABI 檢查通過；新 archive 的 manifest／輸入輸出 hash 已由 root 核對。Standards／Spec 獨立審查皆無剩餘程式 finding。

使用者已連接 iOS 27.0.1 測試機，Developer Mode、Xcode DDI services 與 LocalDevVPN 安裝已確認。獨立 bundle 尚未安裝；簽署預檢明確回報缺少 com.neven.gofly 描述檔，未開啟 Apple provisioning updates。後續仍需正式 bundle 開發簽署、配對／必要準備交付及真機啟停、clear／有效 GPS 與拔 USB 驗收。既有 prototype 及其成功紀錄不代替本票驗收。
