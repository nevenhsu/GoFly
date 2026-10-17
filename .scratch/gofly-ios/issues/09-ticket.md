# 09: GPX 匯入、完整軌跡預覽與執行／匯出

**Status:** ready-for-agent

**Blocked by:** 06。

**What to build:** 匯入 GPX、看摘要與完整軌跡，開始路線並可匯出。

**Design reference:** 03 R07／R08／路線細項。

**Acceptance criteria:**

- [ ] 正式解析器及檔案處理重新驗證，維持 GPX 1.1、2 MiB／10,000 點及原有不安全 XML／無效座標拒絕限制。
- [ ] GPX 以檔名、點數摘要與完整軌跡顯示，不展開逐點 input，不套用手動節點過濾而悄悄刪除無效取樣點。
- [ ] 匯入清單支援重載、刪除及該筆復原；不傷來源檔、其他紀錄或草稿。匯出後重匯可保留路徑。

**Verification:** 邊界／不安全輸入／編解碼 round-trip 測試；10,000 點顯示與執行檢查。
