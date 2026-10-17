# 03: 搜尋、選點到單點瞬移

**Status:** verification-pending

**Implementation:** complete

**Device verification:** deferred-by-user（全部實作完成後，由使用者統一用 iPhone 驗收）。

**Development policy:** 依序持續開發至全部實作完成；開發期間不要求使用者連接 iPhone、不等待 USB、不安裝或操作實機。先完成本票實作、建置、自動化／模擬器驗證及必要審查，再繼續下一票；所有實機項目交由使用者最後依[集中手機驗收清單](../DEVICE-ACCEPTANCE.md)測試。前置票實作完成即可解除開發依賴，deferred-by-user 不阻擋後續實作；實機未驗不標 done。

**Blocked by:** 02（實作／自動驗證已完成；真機集中驗收）。

**What to build:** 用名稱、座標或地圖選候選，按 Go 才前往同一地點。

**Design reference:** 02 D01／D07–D13／G02／G03／G05。

**Acceptance criteria:**

- [x] 共用單 title 地點卡；首次名稱搜尋不預選；有效座標自選，錯誤輸入保留上次有效候選但停用 Go；過期搜尋不覆寫新候選。
- [x] 候選 Pin 置中於可見地圖範圍，鍵盤／面板變化重新計算；選點與鏡頭移動不改裝置位置，所有地圖 icon 下方無文字。
- [x] Go 準備後執行原候選，連點不重送；成功移除 Pin／Go 並置中目前模擬位置。送點失敗／結果未知先停止後續送點並鎖原 Go，不自動重送。

**Verification:** 座標／候選與送點身分測試；鍵盤及可見地圖驗收；兩個接收 App 核對實際位置。

## Implementation record

2026-10-17：以 `16d8f3f` 為本票實作基準，Advisor 已核准候選、同步派送 gate、共用 FIFO、持續 session、協定回覆與可見地圖計畫（decisions/03-teleport.md）。Core 已通過座標、名稱不預選、無效保留、遲到搜尋、候選 ID 及精確座標、Go 防連點／原快照、Stop 前後／watchdog、unknown 鎖定、GPS 不解鎖命令、模擬位置優先／等待箭頭等定向驗證。舊 GPS marker 介面已替換成同時帶來源的 PositionMarker；既有服務測試改從實際地圖使用的公開投影檢查。

Native 原始錯誤回覆誤成功已先紅後綠，新增 bounded correlated set／clear，10 項 Rust（含既有 verify-only）通過；30 宣告 ABI、重新建置 archive／manifest 與 root 完整 verifier 通過。獨立 Native review 發現首次 Go 未消費 setup handoff，已以直接首操作的 exact-service Swift 6 harness 重現後修正，原生與 iOS typecheck 通過，Rust來源未再變更。最終 Core 36 項／6 suites＋Transport 9 項／1 suite（45 項）通過；完整模擬器 UI 8／8，最後僅相機優先順序修正後補跑受影響搜尋／viewport 2／2 通過。build 5 最終未簽署 iPhoneOS build-for-testing 成功，三語 parser、完整 native verifier 與 git diff --check 通過。Standards／Spec 獨立審查皆零剩餘 finding；已目視深色大字級／鍵盤與 failed Go 保留候選截圖。GPS 與較新候選／舊 ACK 的鏡頭競合分支為來源審查，未冒充可執行硬體 ACK。所有真機與接收 App 效果依使用者指示集中延後。

以上勾選記錄實作與自動驗證完成；不代表手機或接收 App 已驗收。集中清單保留本票手動效果及新 clear patch 的停止／恢復回歸；不再等待 USB，解除後續實作依賴。
