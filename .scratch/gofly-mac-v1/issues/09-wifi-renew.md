# 09 · Wi‑Fi 延長簽名

**Status:** todo
**Blocked by:** 08
**Spec:** MAC-INSTALLER-SPEC §5.2；Figma D08–D11、D13。

**Figma:** 照 `FIGMA-NODES.md` 的 D08–D11、D13（淺色＋深色）製作，先截圖並讀畫面下方說明；完成後 App 截圖存 `work/gofly-mac/v1/screens/` 並與 Figma 並排比對，見 TRACKER「UI 準據：Figma」。

**Scope**
- renew 支援 `transport: wifi`：建置、簽名、透過網路覆蓋安裝（保留資料）、**只核對手機上現有配對**（不重新建立）、核對裝置支援、讀回 activation receipt。核對失敗時回穩定錯誤碼，UI 顯示「請改用 USB」。
- 先研究並記錄可行路徑（CoreDevice／`devicectl` 網路安裝、RSD over network、檔案讀回），寫在 `work/gofly-mac/v1/WIFI-RENEW-RESEARCH.md`，再實作。
- 進度與完成畫面與 USB 共用（D10 標題手動時為「正在延長簽名」、D11）。

**Acceptance**
- 離線測試覆蓋 Wi‑Fi 成功、找不到手機、配對核對失敗、中途斷線（→ D14）。實機驗收列入清單，不宣稱已驗。

**Stop if:** 需要改原生 patch／FFI；或 Wi‑Fi 上無法安全讀回 receipt（記錄研究結果，交使用者決定）。
