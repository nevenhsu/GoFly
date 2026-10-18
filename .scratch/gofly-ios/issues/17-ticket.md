# 17: Mac 資料還原交接與 iOS 操作鎖定

**Status:** verification-pending

**Implementation:** complete（軟體／離線檢查；手機待驗）

**Device verification:** deferred-by-user（全部實作完成後，由使用者統一用 iPhone 驗收）。

**Development policy:** 依序持續開發至全部實作完成；開發期間不要求使用者連接 iPhone、不等待 USB、不安裝或操作實機。先完成本票實作、建置、自動化／模擬器驗證及必要審查，再繼續下一票；所有實機項目交由使用者最後依[集中手機驗收清單](../DEVICE-ACCEPTANCE.md)測試。前置票實作完成即可解除開發依賴，deferred-by-user 不阻擋後續實作；實機未驗不標 done。

**Blocked by:** 10、16 及必要 M1 軟體已完成；M2 與本票的軟體整合已完成，真機延後不阻擋開發。

**What to build:** Mac 重新安裝後自動還原資料，iPhone 顯示進度；全部完成才進正常地圖。

**Design reference:** 12 O10。

**Acceptance criteria:**

- [ ] 採 Mac 提供的版本化還原交易與裝置／資料身分；確認相容性與失敗語意，不能自行猜測 Mac 端完成狀態。
- [ ] 還原中不開已完成最愛、修改、Go 或任務入口；類別狀態由實際交易更新，完成後完整讀回地點、標籤、路線、GPX 與所選設定。
- [ ] 中斷保留已完成成果並由 Mac 繼續；重試不重複匯入、不覆寫其他裝置資料或復活任務，不增加 iOS 下載／U19。

**Verification:** 以契約 fixture 開發、故障注入驗資料完整性；真實 Mac 重裝／中斷／續傳端到端驗收後才完成。

**Implementation record:** 完整 v8 已於使用者授權的新審查第3／5輪核准；M2／17 的持久化、producer 與正式 App 匯出／O10／還原已整合，具體審查問題均複查關閉。來源 checkpoint `cdc2203`，build20 未簽署雙 SDK 建置、既有首次流程模擬器4項、Core與Mac及Python主要流程檢查通過；精確數量與首次序列重驗說明見 [M2票](M2-reinstall.md)。完整還原收據已跨 Swift／Python實際資料核對，重播保留目前可編輯投影與後續Session／偏好，不重套舊seed。未操作手機，不宣稱真實移除、安裝、匯入或接收App已通過。
