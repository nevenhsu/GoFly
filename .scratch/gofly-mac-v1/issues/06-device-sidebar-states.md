# 06 · 以裝置為中心的側欄與裝置頁狀態

**Status:** todo
**Blocked by:** 04
**Spec:** MAC-INSTALLER-SPEC §5 表格；Figma D01–D04、D08、D09、D12、D13。

**Figma:** 照 `FIGMA-NODES.md` 的 D01–D04、D08、D09、D12、D13（淺色＋深色）製作，先截圖並讀畫面下方說明；完成後 App 截圖存 `work/gofly-mac/v1/screens/` 並與 Figma 並排比對，見 TRACKER「UI 準據：Figma」。

**Scope**
- 側欄裝置列：名稱、USB／Wi‑Fi、剩餘天數（剩不到 4 天橘色、過期紅色）；同機 USB／Wi‑Fi 只列一次、預設 USB。
- 裝置頁依 `inspect` 結果決定唯一主要按鈕：D01 沒手機、D02 未信任、D03 未開開發者模式、D04 可以安裝、D08 已安裝（延長簽名）、D09 有新版（更新並延長簽名＋build 差異提示）、D12 Wi‑Fi 沒 GoFly（需要 USB）、D13 找不到 Wi‑Fi 手機；簽名過期時 D08 加說明「過期只是暫時無法開啟，資料還在」。
- D02／D03 準備清單自動前進；iPhone 重新開機時 USB 暫時斷線不視為錯誤。D03 可用既有唯讀能力讓開發者模式選項出現時才做，否則只寫說明。
- 選取裝置只做 inspect，不寫入手機。沒有另外的確認頁。
- D08／D09 的「自動延長簽名」開關先做 UI 與本機設定（預設開），行為在 10 實作。

**Delete:** 舊裝置清單頁、舊裝置頁與「重新檢查狀態」等舊按鈕。直接 `git rm`／刪除，不留相容入口或舊副本；見 TRACKER「舊代碼與舊 UI：該刪就刪」。

**Acceptance**
- 狀態機有 model 測試（每種 inspect 結果 → 正確頁面與按鈕）；截圖對照 Figma。
