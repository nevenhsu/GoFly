# 07: 多點路線編輯、排序與任意節點刪除

**Status:** verification-pending

**Implementation:** complete

**Blocked by:** 05、06（實作／自動驗證完成：bcf9d0d／9057718；手機集中驗收）。

**What to build:** 在同一張清單增刪及拖曳起點、途經點與目的地，從搜尋／最愛確認回填後執行整條路線。

**Design reference:** 03 D02／O24／R04／R05。

**Acceptance criteria:**

- [ ] 左把手排序、中間角色／地點開搜尋、右垃圾桶刪該筆，互不干擾；各節點以穩定身分識別，重排後重算首尾及途經編號。
- [ ] 已確認地點明確清空再確認等同刪除；清空 query 不刪原節點，無效非空輸入不覆寫，取消新增不留空節點；遲到搜尋不寫入已刪／換位節點。
- [ ] 只保留有效已確認節點，少於兩點停用開始／儲存；不補假座標。完整有序路線可執行，VoiceOver 可排序及刪除。

**Verification:** 節點編輯／刪除／重排／遲到回覆測試；長清單與輔助操作 UI 驗收。


## Implementation record

2026-10-17：實作／審查基準 9057718。Advisor 已核准 decisions/07-waypoints.md：有效節點0…27、穩定身分與位置角色、暫存新增 session、確認刪除、整列拖曳／輔助排序、單一目前位置快照與完整有序分段規劃。先以公開邊界紅綠測試實作；手機全部延後，不操作或安裝。


最終公開邊界測試 Core125／14 suites＋Transport9共134項通過；完整模擬器UI23／23通過（656.740s，/private/tmp/gofly-ui-final07.xcresult），含真實handle-only整列排序、27點edge-autoscroll及44pt分離命中區。Root目視Pin無Go與地址回填、移動Current後角色及長清單；三語177keys、parser、native verifier、未簽署iPhoneOS build9與diffcheck通過，Standards／Spec均零finding。主機真實MapKit兩段join保留23點與精確途經點，不是手機移動證據。

有效節點與可開始條件已實作；「儲存路線」入口及資料保存屬後續票10，本票未宣告交付。實際VoiceOver自訂手勢、OS中斷拖曳取消與接收App路線位置仍依集中清單待最後手機驗收，維持verification-pending而不標done。沒有連接、安裝或操作手機。
