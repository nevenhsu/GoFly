# 01: 正式 App：地圖、服務啟停與 GPS／VPN 修復

**Status:** in-progress

**Blocked by:** 無，可立即開始。

**What to build:** 打開正式 GoFly，看到真實服務狀態；可啟動服務待命及停止，整個過程不自動移動。

**Design reference:** 01 B06、07 C01、11 共用狀態。

**Acceptance criteria:**

- [ ] 正式產品 target、資料空間及裝置 adapter 的邊界明確；prototype 僅作參考，擬沿用部分逐項審查、保留來源授權並重新驗證。
- [ ] Uber 風格 token 首先套用可操作的地圖、頂部位置／狀態與設定服務 card；服務、任務、候選、實際結果分開表示。
- [ ] 啟動只準備服務；無任務時暫停停用；停止使舊準備／排程與遲到結果失效。裝置未就緒顯示具體原因，不能假正常。
- [ ] 停止送點、裝置 clear 確認、有效真實 GPS 分別記錄；clear 失敗顯示已停止・GPS 待確認。停止後可獨立恢復 GPS／重置 VPN，操作互斥；重置僅修復 GoFly 端連線、不清使用者資料、不控制 LocalDevVPN 開關、不等同 clear，GPS 未授權仍可要求清除。

**Verification:** 正式 target 建置；service adapter 的成功／失敗／取消測試；已備妥測試機驗證啟動不送點。

## Implementation record

2026-10-17：正式 GoFly target、純 Swift core 與同 session 原生 adapter 已建立。10 項核心測試通過，unsigned iPhoneOS／iPhoneSimulator 建置通過；介面測試與雙軸審查進行中。真機服務及拔 USB 驗收未執行，未標完成。
