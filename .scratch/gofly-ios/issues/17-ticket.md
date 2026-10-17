# 17: Mac 資料還原交接與 iOS 操作鎖定

**Status:** ready-for-agent

**Blocked by:** 10、16、M2。

**What to build:** Mac 重新安裝後自動還原資料，iPhone 顯示進度；全部完成才進正常地圖。

**Design reference:** 12 O10。

**Acceptance criteria:**

- [ ] 採 Mac 提供的版本化還原交易與裝置／資料身分；確認相容性與失敗語意，不能自行猜測 Mac 端完成狀態。
- [ ] 還原中不開已完成最愛、修改、Go 或任務入口；類別狀態由實際交易更新，完成後完整讀回地點、標籤、路線、GPX 與所選設定。
- [ ] 中斷保留已完成成果並由 Mac 繼續；重試不重複匯入、不覆寫其他裝置資料或復活任務，不增加 iOS 下載／U19。

**Verification:** 以契約 fixture 開發、故障注入驗資料完整性；真實 Mac 重裝／中斷／續傳端到端驗收後才完成。
