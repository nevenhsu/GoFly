# 01: 建立三模式共用狀態投影與刷新基準

**Status:** implemented; software-verified

**Blocked by:** None (can start immediately).

**What to build:** 三模式的地圖與設定頁從同一快照取得 session pill 與箭頭狀態。先完成必要的行為保持重構及可重現基準，再進行後續語意修正。

- [ ] 三模式與其子模式都經過同一輸入正規化及狀態投影，無 mode 專用的 pill／箭頭刷新補丁。
- [ ] 將現有診斷提升為直接覆蓋正式共用投影與 UI 接線的測試，避免只測複製 getter。
- [ ] 保存健康探測、每類送點 pending/ACK、暫停及故障的狀態序列基準；明確標記原有錯誤行為，後續票負責轉綠。
- [ ] 三模式分別記錄地圖容器建立、update、路線 overlay 更換、renderer 重繪及鏡頭操作基準；量測限診斷用途。
- [ ] 不改變任務 authority、按鈕 admission、ACK、timeout 或背景行為；不得引入重複 domain state。

實作及測試證據：`work/gofly-ios/flicker-optimization/RESULT.md`。最終文案／泛用錯誤定義依目前 `docs/IOS-UI-DESIGN.md` 與 `docs/IOS-STATUS-ERRORS.md`，取代票內較早連線專用用詞。手機／Figma待同步項不宣稱完成。
