# GoFly 本機票單

2026-10-17 使用者指示「用 implement 依序開發」，以已討論的 18 張票為執行來源，先用本機票單追蹤。每票一檔，Blocking edges 指票號；ready-for-agent 表示可依前置依賴領取，不代表真機已驗收。狀態分 ready-for-agent／in-progress／verification-pending／done；未有真機證據不得標完成。M1／M2 為計畫列出的 Mac 交接依賴。

本輪審查基準：c661d44fe55620e02514f4e9f83ba9d3780afbd7。既有未提交文件變更不納入實作提交；每張實作完成後作定向檢查與 standards／spec 雙軸審查。

測試界線沿用票 01 的正式服務 public interface 與 device-adapter 系統邊界，觀察啟停／clear／reset 可見結果、錯誤與取消／遲到結果；不測私有欄位。原生握手／同機身分／檔案保護另在 native 邊界驗證，不以 fake adapter 當真機證據。
