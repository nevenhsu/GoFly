# 14: 背景持續定位的最小實機可行性驗證

**Status:** verification-pending

**Implementation:** complete

**Blocked by:** 無，可立即開始。

**What to build:** 交付可撤銷runtime／單次completion的候選生命週期、實際iOS adapter與離線驗證，並提供可重跑集中實機腳本；本票編譯但不在App啟用，15另完成正式移動整合。鎖屏與接收App的硬體結果留到全部實作完成後由使用者取得。

**Design reference:** 10、07 C04 的產品目標。

**Acceptance criteria:**

- [x] 交付實際SDK候選adapter、Core生命週期及可重跑離線驗證，清楚區分環境／機制／失敗條件；prototype、controlled driver與SDK編譯都不當作正式App／手機成功。
- [ ] 在 iOS 26／27 測切 App、鎖屏、背景重新整理開／關／受限及系統終止；分別記錄發送、服務接受與兩個接收 App 的位置。
- [x] 先完成候選背景方案、可用生命週期、中斷處理、可離線驗證的邊界與實機操作腳本，經設計審查後供 15 實作；一般 App Refresh 開關不等於持續能力。硬體效果記 deferred-by-user，不因未接手機阻擋 15 或後續開發；不能據此宣稱方案已在實機可行，也不把產品目標默改為背景暫停。最終實機失敗則記錄限制並修正方案。

**Verification:** 候選公開邊界測試／SDK建置、設計審查與集中實機腳本及證據欄位；真實iOS26／27背景／接收App仍待驗，本票不是正式背景支援完成宣告。


## Implementation record

2026-10-18：以1b6dcd6ddd40d55cc83c81c2134fabc7a753ac0d為基準，Root v5經configuredAdvisor第5／5輪PLAN_APPROVED，P14-01..03均INCORPORATED；精確公開API與正式ADR見decisions/14-continued-processing.md。build16開始，先Core public controller／driving／atomic completion，再實際SDK adapter；不改既有移動writer／App初始化／plist、不操作手機。有限路線依實際ACK與抵達；無期限來回／漫步只作indeterminate候選，不修改產品目標、不虛構百分比／續租或宣稱硬體支援。


離線交付完成：完整SwiftCore355／41suites＋Transport9／1suite，共364PASS；final public focused20／20PASS；未簽署iPhoneOS／iPhoneSimulator SDK27.1 build16皆成功（simulator含arm64／x86_64）；native verifier／diffcheck通過，Standards0／Spec0。App初始化、plist、既有送點／生命週期及三語資源未變，本票未重跑UI；332key三語的13既有驗證仍適用。沒有手機／USB／簽署／安裝／實際scheduler或接收App測試。 初版source先於10項行為執行，typecheck／sandbox錯誤不是行為RED；追加矩陣多數既有行為直接GREEN，如實記錄。literal-wildcard registration是未啟用實驗，官方完整ID註冊／提交證據已納ADR；15必須先經獨立核准處理具體ID／bounded一次註冊及native admission，才能啟用App。第14票不聲稱背景實機可行，開發依賴可解除並繼續15。
