# 10: 完整最愛路線與標籤持久化

**Status:** verification-pending

**Implementation:** complete

**Device verification:** deferred-by-user（全部實作完成後，由使用者統一用 iPhone 驗收）。

**Development policy:** 依序持續開發至全部實作完成；開發期間不要求使用者連接 iPhone、不等待 USB、不安裝或操作實機。先完成本票實作、建置、自動化／模擬器驗證及必要審查，再繼續下一票；所有實機項目交由使用者最後依[集中手機驗收清單](../DEVICE-ACCEPTANCE.md)測試。前置票實作完成即可解除開發依賴，deferred-by-user 不阻擋後續實作；實機未驗不標 done。

**Blocked by:** 07（d98f8c7）、09（dcf670e）實作／離線驗證完成，手機集中驗收。

**What to build:** 將手動或 GPX 路線命名保存，重開載入完整路徑，可改標籤及刪除復原。

**Design reference:** 03 R02／R03／R06。

**Acceptance criteria:**

- [x] 路線星號開新增彈窗，儲存才新增；允許相同名稱／內容的獨立紀錄，不查重、不顯示地點最愛式實心／空心。
- [x] 手動起終點與有序途經點、GPX 完整軌跡與類型均保留；目前位置存確切座標快照，重載不變動，速度及來回另管。
- [x] 短按載入、長按更新原標籤；刪除可復原該筆完整資料及身分，不連帶刪相同內容其他筆，不破壞當前草稿；損壞／舊資料版本有保護。

**Verification:** 兩類路線重開讀回、重複紀錄隔離、刪除復原及持久化失敗測試。


## Implementation record

2026-10-17：以dcf670e為實作／審查基準。Advisor核准decisions/10-favorite-routes.md，API凍結中立GPX來源、tap-time immutable Save candidate／omittedCurrent實際成功提示、Controller issued／consumed favoriteLoad admission token及安全file primitives抽取gate。A模型／store／file、Bsource／controller公開TDD並行，UI在模型可編譯後整合；Root負責App注入及最終驗證。build12開發中，無手機操作。

2026-10-18：production source held，完整Swift Core222＋Transport9＝231通過，最終未簽署iPhoneOS build12成功，285key三語parser／native verifier／diffcheck通過。新UI已驗無效Current只在收藏副本排除並有實際成功提示、27手選地點完整重開載入、GPX10k在原匯入紀錄刪除後仍能完整重開載入。最後兩項精確標籤／三語最大字級focused2／2通過（453.465s），修正Cancel換行及native TextField實際44pt；測試須先確認原生整欄清空、精確值與鍵盤／按鈕位置穩定，不用診斷狀態或假ACK。Standards／Spec最後source與test-only readback各0finding。完整35UI正執行，尚未據此結票；手機仍deferred-by-user。

2026-10-18：完整Swift231、完整simulator UI35／35（1537.711s）、未簽署iPhoneOS build12、285key三語parser／native verifier／diffcheck及Standards／Spec零finding。完整run來源與binary保持固定，沒有後續產品變更或剩餘finding；Implementation complete，Device verification deferred-by-user。最愛手動／GPX完整保存、lazy manifest與immutable payload、manifest-only標籤、獨立duplicate／delete undo及token防遲到Load均完成。未連接／簽署／安裝／操作手機，實際GPS／接收App／Files與VoiceOver仍最後集中驗收。
