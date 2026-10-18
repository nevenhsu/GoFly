# 18: 正式 App 跨流程與裝置驗收

**Status:** ready-for-agent

**Implementation:** not-started

**Device verification:** deferred-by-user（全部實作完成後，由使用者統一用 iPhone 驗收）。

**Development policy:** 依序持續開發至全部實作完成；開發期間不要求使用者連接 iPhone、不等待 USB、不安裝或操作實機。先完成本票實作、建置、自動化／模擬器驗證及必要審查，再繼續下一票；所有實機項目交由使用者最後依[集中手機驗收清單](../DEVICE-ACCEPTANCE.md)測試。前置票實作完成即可解除開發依賴，deferred-by-user 不阻擋後續實作；實機未驗不標 done。

**Blocked by:** 15、17 的實作／自動驗證；M1 的實機結果只阻擋最終驗收，不阻擋整合回歸與驗收包準備（其餘功能由傳遞依賴涵蓋）。

**What to build:** 開發階段完成跨流程整合、自動化回歸、最終建置與集中驗收包（逐項步驟、預期結果、build、證據欄位及已知限制）。全部實作完成後一次交由使用者在 iPhone 測試，再記錄 UI、服務與接收端結果；不得在本票準備階段要求先接手機。

**Design reference:** 01–12 全部現行 iOS 流程（05 已撤下）。

**Acceptance criteria:**

- [ ] iOS 26／27：首次安裝準備、拔 USB／停止 Mac、兩個獨立接收 App、瞬移／路線／來回／搖桿／漫步、鎖屏、重啟與 VPN 切換。
- [ ] 停止本機送點、clear 確認、有效 GPS 及接收 App 恢復分開驗證；失敗／未知、重試、交接、舊回覆、還原及資料損壞都無資料遺失／舊任務復活。
- [ ] 各流程核對 Uber 風格一致性、三語、最大 Dynamic Type、VoiceOver、深淺色對比、44 pt 操作目標、多尺寸安全區及鍵盤。每項結果標已通過／失敗／未驗，prototype 或 ACK 不充當通過。

**Verification:** 正式建置與相關自動化檢查；目標裝置、接收 App 與完整驗收矩陣，未通過項明列。
