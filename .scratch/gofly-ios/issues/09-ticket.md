# 09: GPX 匯入、完整軌跡預覽與執行／匯出

**Status:** verification-pending

**Implementation:** complete

**Device verification:** deferred-by-user（全部實作完成後，由使用者統一用 iPhone 驗收）。

**Development policy:** 依序持續開發至全部實作完成；開發期間不要求使用者連接 iPhone、不等待 USB、不安裝或操作實機。先完成本票實作、建置、自動化／模擬器驗證及必要審查，再繼續下一票；所有實機項目交由使用者最後依[集中手機驗收清單](../DEVICE-ACCEPTANCE.md)測試。前置票實作完成即可解除開發依賴，deferred-by-user 不阻擋後續實作；實機未驗不標 done。

**Blocked by:** 06（9057718）、07（d98f8c7）、08（1e5835d）實作／自動驗證完成；手機集中驗收。

**What to build:** 匯入 GPX、看摘要與完整軌跡，開始路線並可匯出。

**Design reference:** 03 R07／R08／路線細項。

**Acceptance criteria:**

- [ ] 正式解析器及檔案處理重新驗證，維持 GPX 1.1、2 MiB／10,000 點及原有不安全 XML／無效座標拒絕限制。
- [ ] GPX 以檔名、點數摘要與完整軌跡顯示，不展開逐點 input，不套用手動節點過濾而悄悄刪除無效取樣點。
- [ ] 匯入清單支援重載、刪除及該筆復原；不傷來源檔、其他紀錄或草稿。匯出後重匯可保留路徑。

**Verification:** 邊界／不安全輸入／編解碼 round-trip 測試；10,000 點顯示與執行檢查。


## Implementation record

2026-10-17：實作／審查基準1e5835d。Advisor核准decisions/09-gpx.md（含完整track分組／route／ordered waypoints、gap不可Load、單一persistence actor完整transaction／undo失敗保留token與actual quota），先凍結共用模型／snapshot／receipt API，再分codec/store與route-source兩片公開TDD。手機全部延後，沒有安裝或操作。


已完成正式Core／App實作：GPX1.1三種來源、完整group/segment/點序與精確座標、bounded安全匯入／canonical匯出、單一actor的不可變UUID payload／manifest／hash／actualquota／deleteundo及重開讀回。GPX載入即在主地圖預覽完整軌跡；Start才進既有準備／ACK排程，不MapKit、不產生逐點inputs；gapped／zero合法文件可保存／預覽／匯出但不可Load。兩軸發現的載入預覽缺口經公開red→green修正，Standards／Spec最終零finding。

完整Swift Core179／20＋Transport9共188通過；真實host App reader規則／source-preservation probe、248key三語parser、native verifier／diffcheck及unsigned iPhoneOS build11通過。完整UI執行30案例，29通過，唯一失敗是44pt被AX浮點座標讀為43.99999999999994pt的測試誤判；僅修測試1e-6pt容差，受影響AX三語單項重跑通過（/private/tmp/gofly-ui-final09-axprecision.xcresult）。產品來源未變，不重跑其餘29已綠案例，亦不把前一run誤寫成30／30。全30case覆蓋完成，含10,000點actual主地圖overlay／viewport、OS export presentation／Cancel、重複紀錄與deleteundo／relaunch、原有Pin無Go與27節點回歸。

手機位置／接收App／Files真實儲存與授權仍deferred-by-user，維持verification-pending，不標done；沒有安裝、操作手機或Figma回寫。依安排繼續票10。
