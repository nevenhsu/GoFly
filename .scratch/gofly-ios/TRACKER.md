# GoFly 本機票單

2026-10-17 使用者指示「用 implement 依序開發」，以已討論的 18 張票為執行來源，先用本機票單追蹤。每票一檔，Blocking edges 指票號；ready-for-agent 表示可依前置依賴領取，不代表真機已驗收。狀態分 ready-for-agent／in-progress／verification-pending／done；done 表示該票完整驗收通過，實作完成另以 Implementation 記錄。M1／M2 為計畫列出的 Mac 交接依賴。

最新執行安排（2026-10-17）：使用者要求「依序開發，先不做實機測試，做完之後統一用手機驗收」。每票先完成正式實作、適當自動化驗證、雙軸審查與提交，再標 Implementation: complete；真機欄另記 deferred-by-user，票狀態保留 verification-pending。前置票的實作完成即可開始下一票，延後的真機驗收不阻擋依序開發。不再安裝／操作手機或等待 USB；最後提供集中驗收清單。不得將模擬器／注入測試寫成真機已通過。

此安排適用所有剩餘 tickets（含 14 背景可行性、15 背景實作、17 跨端還原與 18 整合驗收準備）：不得在逐票結尾暫停要求接 iPhone，也不得因前置票尚待實機驗收阻擋下一票。14 先交付候選方案、設計審查與離線驗證，15 依此完成實作並保留硬體未知；18 先完成自動化回歸、最終建置與驗收包。全部實作及可離線驗證工作完成後，再一次交由使用者測試手機。實際程式失敗或契約未決仍須修正／釐清，不能以延後驗收跳過。

各票審查基準記於該票 Implementation record：票 03 為 16d8f3f，票 04 為 0379d10，票 05 為 91d0188，票 06 為 bcf9d0d。既有未提交且不屬當票的文件變更不納入實作提交；每張實作完成後作適當驗證與 standards／spec 雙軸審查。

測試界線沿用票 01 的正式服務 public interface 與 device-adapter 系統邊界，觀察啟停／clear／reset 可見結果、錯誤與取消／遲到結果；不測私有欄位。原生握手／同機身分／檔案保護另在 native 邊界驗證，不以 fake adapter 當真機證據。

票 06 實作／離線驗證完成：完整 Swift 112 項、完整 simulator UI 19／19、未簽署 iPhoneOS build 8、三語與 native verifier 通過，雙軸無剩餘 finding；路線編輯依最新使用者規則可用地圖 Pin、無 Go。手機維持集中驗收，可開始票 07。
