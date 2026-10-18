# 12: 自動漫步、手動接管與 Go 更換目標

**Status:** verification-pending

**Implementation:** complete

**Device verification:** deferred-by-user（全部實作完成後，由使用者統一用 iPhone 驗收）。

**Development policy:** 依序持續開發至全部實作完成；開發期間不要求使用者連接 iPhone、不等待 USB、不安裝或操作實機。先完成本票實作、建置、自動化／模擬器驗證及必要審查，再繼續下一票；所有實機項目交由使用者最後依[集中手機驗收清單](../DEVICE-ACCEPTANCE.md)測試。前置票實作完成即可解除開發依賴，deferred-by-user 不阻擋後續實作；實機未驗不標 done。

**Blocked by:** 05、11（57565c7）實作及離線驗證完成；依序開始。

**What to build:** 勾選漫步自動前進並抵達換下一站，可拖搖桿暫時接管，或選候選後用 Go 換目的地。

**Design reference:** 06 D06／J03–J07。

**Acceptance criteria:**

- [x] 漫步是搖桿子功能；以有效當前位置開始，抵達隨機下一個不同有效目標，也可用同列隨機目的地立即換點，鏡頭不自動追目標。
- [x] 自動方向連動滑塊／箭頭；拖動只暫時接管，保留速度、勾選及目標，健康有效且未暫停時放開才恢復自動；不建立第二個送點來源。
- [x] 當前目標無 Go、候選有 Go；按 Go 才替換目標，從當下位置前進而不瞬移／重啟任務。保持暫停／接管，取消勾選結束自動並清候選，保留最後位置。

**Verification:** 確定性隨機目的地、抵達換點、接管／放開、候選更新與遲到結果測試；實機驗收兩種 Pin。

## Implementation record

2026-10-18：以57565c7為基準，Root方案v2經configured Advisor第2輪PLAN_APPROVED，P12-01保持manual公有outcome相容、P12-02明定noCandidate實際paused lease生命週期；精確A/B API已凍結，見decisions/12-wander.md。依models→geometry/selector→同一Service recipe executor→Controller／App／UI波次逐條publicseam TDD；build14實作及離線驗證完成，無手機操作。

正式結果：完整SwiftCore293／36suites＋Transport9／1suite，共302PASS；完整simulator UI39／39 PASS（1767.040s）；未簽署iPhoneOS build14、312key三語parser／native verifier／diffcheck通過，Standards及Spec最後readback零finding。涵蓋selector32／history100、球面target clamp、同lease／ACKsequence、手動接管及noCandidate實際paused／Retry、Go同步換目標、Stop／另一任務actualclaim作廢舊continuation。App三語AX／keyboard、無origin停用與實際失敗保候選／star、路線map選點回填與Pin無Go均在同一held fullrun通過；正向移動由public controlled-device seam驗證，沒有App假ACK／GPS。首focused測試將原生Switch誤當Button，test-only locator修正後4／4重驗通過，最終39／39亦通過；不隱去首run失敗。實際接收位置、手感、VoiceOver與背景效果仍deferred-by-user，集中清單另列。Figma Console前次Transport closed，無新讀回或回寫。
