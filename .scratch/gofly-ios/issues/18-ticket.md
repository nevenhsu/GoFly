# 18: 正式 App 跨流程與裝置驗收

**Status:** ready-for-agent

**Blocked by:** 15、17、M1（其餘功能已由這兩票的傳遞依賴涵蓋）。

**What to build:** 在目標 iPhone 上完成正式 GoFly 全流程，留下可追溯的 UI、服務與接收端結果。

**Design reference:** 01–12 全部現行 iOS 流程（05 已撤下）。

**Acceptance criteria:**

- [ ] iOS 26／27：首次安裝準備、拔 USB／停止 Mac、兩個獨立接收 App、瞬移／路線／來回／搖桿／漫步、鎖屏、重啟與 VPN 切換。
- [ ] 停止本機送點、clear 確認、有效 GPS 及接收 App 恢復分開驗證；失敗／未知、重試、交接、舊回覆、還原及資料損壞都無資料遺失／舊任務復活。
- [ ] 各流程核對 Uber 風格一致性、三語、最大 Dynamic Type、VoiceOver、深淺色對比、44 pt 操作目標、多尺寸安全區及鍵盤。每項結果標已通過／失敗／未驗，prototype 或 ACK 不充當通過。

**Verification:** 正式建置與相關自動化檢查；目標裝置、接收 App 與完整驗收矩陣，未通過項明列。
