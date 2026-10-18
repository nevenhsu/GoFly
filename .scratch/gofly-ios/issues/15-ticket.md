# 15: 正式路線／漫步背景持續運作

**Status:** verification-pending

**Implementation:** complete

**Device verification:** deferred-by-user（全部實作完成後，由使用者統一用 iPhone 驗收）。

**Development policy:** 依序持續開發至全部實作完成；開發期間不要求使用者連接 iPhone、不等待 USB、不安裝或操作實機。先完成本票實作、建置、自動化／模擬器驗證及必要審查，再繼續下一票；所有實機項目交由使用者最後依[集中手機驗收清單](../DEVICE-ACCEPTANCE.md)測試。前置票實作完成即可解除開發依賴，deferred-by-user 不阻擋後續實作；實機未驗不標 done。

**Blocked by:** 13 的實作／自動驗證、14 的方案／設計審查與離線驗證交付；14 的延後實機驗收不阻擋本票開發。

**What to build:** 正式 App 取得實際執行資格時，讓健康路線、來回與自動漫步在背景持續；受限時安全暫停，保留同一任務及進度，回前景明確繼續。

**Design reference:** 10、07 C04、06 漫步背景規則。

**Acceptance criteria:**

- [x] 2026-10-18 使用者確認：保留現有無期限來回／漫步；背景受限或未取得／失去資格時暫停，回前景明確繼續。不新增可設定時長／距離或到量結束，也不自動續租。

- [ ] 採 14 經設計審查的候選背景方案實作，先以自動化／模擬器驗證排程、路線進度、來回方向與漫步抵達換點邏輯；系統開關與真實背景能力分開呈現。背景持續效果待最後實機驗收，未驗不得標示已支援或已通過。
- [ ] 手動搖桿進背景釋放輸入；背景任務仍受暫停／停止／清除及單一送點控制，通道中斷如實暫停，不追補歷史。
- [ ] 回前景核對實際任務／位置；能力未就緒共用 N08／C04。須在正式 App 重新取得裝置證據，不能沿用 14 或 prototype 作通過。

**Verification:** 正式 target 在 iOS 26／27 鎖屏、切 App、系統限制與斷復線；核對服務及接收 App。


**Implementation record（離線交付完成）：** 基準 `703309e`，build 17；[核准 v2 與公開介面](../decisions/15-continuation.md) 已經 Advisor 兩輪核准。正式 App 接入實際 BackgroundTasks adapter、同步真實 ACK／明確操作需求及原子 scene／grant 派送門檻。完整 Swift 395 項、iPhoneOS／Simulator SDK 27.1 未簽署建置、352 key 三語 parser／格式與實際 bundle 讀回、native verifier 皆通過；Standards／Spec 修正後皆無剩餘 finding。完整 simulator UI 45／45 PASS（runner 2105.041s；xcresult wall 2127.022s），審查修正後 current-source 背景 UI 2／2 PASS，另三語最大字級及淺色畫面各單項通過，皆零 runtime warning。Root 已核對深／淺色與三語可捲動畫面；手機與接收端效果仍未驗。
