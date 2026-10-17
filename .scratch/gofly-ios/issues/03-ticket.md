# 03: 搜尋、選點到單點瞬移

**Status:** in-progress

**Implementation:** in-progress

**Device verification:** deferred-by-user（全部實作完成後，由使用者統一用 iPhone 驗收）。

**Development policy:** 依序持續開發至全部實作完成；開發期間不要求使用者連接 iPhone、不等待 USB、不安裝或操作實機。先完成本票實作、建置、自動化／模擬器驗證及必要審查，再繼續下一票；所有實機項目交由使用者最後依[集中手機驗收清單](../DEVICE-ACCEPTANCE.md)測試。前置票實作完成即可解除開發依賴，deferred-by-user 不阻擋後續實作；實機未驗不標 done。

**Blocked by:** 02（實作／自動驗證已完成；真機集中驗收）。

**What to build:** 用名稱、座標或地圖選候選，按 Go 才前往同一地點。

**Design reference:** 02 D01／D07–D13／G02／G03／G05。

**Acceptance criteria:**

- [ ] 共用單 title 地點卡；首次名稱搜尋不預選；有效座標自選，錯誤輸入保留上次有效候選但停用 Go；過期搜尋不覆寫新候選。
- [ ] 候選 Pin 置中於可見地圖範圍，鍵盤／面板變化重新計算；選點與鏡頭移動不改裝置位置，所有地圖 icon 下方無文字。
- [ ] Go 準備後執行原候選，連點不重送；成功移除 Pin／Go 並置中目前模擬位置。送點失敗／結果未知先停止後續送點並鎖原 Go，不自動重送。

**Verification:** 座標／候選與送點身分測試；鍵盤及可見地圖驗收；兩個接收 App 核對實際位置。
