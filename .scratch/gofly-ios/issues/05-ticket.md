# 05: 地點最愛、長按標籤與共用 Pin 詳情

**Status:** verification-pending

**Implementation:** complete

**Device verification:** deferred-by-user（全部實作完成後，由使用者統一用 iPhone 驗收）。

**Development policy:** 依序持續開發至全部實作完成；開發期間不要求使用者連接 iPhone、不等待 USB、不安裝或操作實機。先完成本票實作、建置、自動化／模擬器驗證及必要審查，再繼續下一票；所有實機項目交由使用者最後依[集中手機驗收清單](../DEVICE-ACCEPTANCE.md)測試。前置票實作完成即可解除開發依賴，deferred-by-user 不阻擋後續實作；實機未驗不標 done。

**Blocked by:** 03（實作完成，0379d10；04 亦已完成實作，91d0188；手機集中驗收）。

**What to build:** 搜尋或點 Pin 查看地點並即時收藏；從最愛重選或長按改標籤，重開仍保存。

**Design reference:** 02 K01／K02／K04／D18、06 J06。

**Acceptance criteria:**

- [x] 星號與選取各有獨立命中區；收藏依地點身分與座標，星號立即持久化且跨畫面同步，不改候選、位置或任務。
- [x] 最愛短按選取、長按編輯；儲存／取消只處理標籤草稿並回原清單，星號的即時變更不因取消標籤而回滾；未收藏停用標籤儲存。
- [x] 任一已顯示 Pin 開同款名稱／地址／座標 card；最多一張，關閉回原面板。card 綁點擊時的地點，不因目標更新把收藏套到另一點；持久化失敗不假稱已保存。

**Verification:** 原子儲存與損壞資料保護測試；選取／長按／星號不冒泡 UI 驗收；重開讀回。

## Implementation record

2026-10-17：以 91d0188 為實作／審查基準。Advisor 已核准正式 versioned favorites schema、來源＋精確座標身分、write-before-publish、損壞資料保護與不可變標籤編輯邊界（decisions/05-favorites.md）。本票接入共用星號／詳情／長按標籤及實際檔案持久化，並補票 04 的 O16 收藏整合；所有手機測試延後。

實作與離線驗證完成：正式獨立 version 1 schema，以來源身分＋精確座標作 key；安全原子檔案先寫後發布，損壞／不支援資料保留且停用修改。最愛跨搜尋、詳情、清單與標籤編輯共用，短按選取、長按編輯與星號不互相冒泡；標籤 Cancel 不撤回即時收藏。

驗證：完整 Swift Core 61＋Transport 9，共 70 項通過；完整模擬器 UI 15／15 通過（包含真實檔案重開、候選 UUID 不變、最大字級／深色／鍵盤與 O16 返回後收藏可用而 Go 仍鎖）。build 7 未簽署 iPhoneOS build-for-testing 成功，三語 121 keys 一致、parser／native verifier／git diff --check 通過；Standards／Spec 兩軸零 finding。測試揭露舊短時 watchdog 與同步 JSON 負載競爭，已改可注入手動等待 seam，正式仍用 Task.sleep，原取消／FIFO／遲到斷言保留。

沒有安裝、連接或操作手機；UI 的 unconfirmed 錯誤注入不當成 native ACK 或接收端位置證據。手機項目保留 deferred-by-user，軟體實作完成可繼續票 06。
