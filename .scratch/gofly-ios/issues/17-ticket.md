# 17: Mac 資料還原交接與 iOS 操作鎖定

**Status:** in-progress

**Implementation:** in-progress

**Device verification:** deferred-by-user（全部實作完成後，由使用者統一用 iPhone 驗收）。

**Development policy:** 依序持續開發至全部實作完成；開發期間不要求使用者連接 iPhone、不等待 USB、不安裝或操作實機。先完成本票實作、建置、自動化／模擬器驗證及必要審查，再繼續下一票；所有實機項目交由使用者最後依[集中手機驗收清單](../DEVICE-ACCEPTANCE.md)測試。前置票實作完成即可解除開發依賴，deferred-by-user 不阻擋後續實作；實機未驗不標 done。

**Blocked by:** 10、16 及必要 M1 軟體已完成；M2 與本票共同實作中，真機延後不阻擋開發。

**What to build:** Mac 重新安裝後自動還原資料，iPhone 顯示進度；全部完成才進正常地圖。

**Design reference:** 12 O10。

**Acceptance criteria:**

- [ ] 採 Mac 提供的版本化還原交易與裝置／資料身分；確認相容性與失敗語意，不能自行猜測 Mac 端完成狀態。
- [ ] 還原中不開已完成最愛、修改、Go 或任務入口；類別狀態由實際交易更新，完成後完整讀回地點、標籤、路線、GPX 與所選設定。
- [ ] 中斷保留已完成成果並由 Mac 繼續；重試不重複匯入、不覆寫其他裝置資料或復活任務，不增加 iOS 下載／U19。

**Verification:** 以契約 fixture 開發、故障注入驗資料完整性；真實 Mac 重裝／中斷／續傳端到端驗收後才完成。

**Implementation record:** M2／17 的 v4 資料、協定與 owner 鎖定分段已實作並通過回歸及審查；進度及資料／權限界線見 [M2 票](M2-reinstall.md)及[決策](../decisions/M2-reinstall.md)。第五輪 v5 未核准後，使用者授權修正並重新審查；新流程第3／5輪核准完整 v8，剩餘持久化、producer 及 App 整合依序開發中，不宣稱完整還原或實機成功。
