# 09 · Wi‑Fi 延長簽名

**Status:** implemented; software-verified; visual-design-verified
**Blocked by:** 08
**Spec:** MAC-INSTALLER-SPEC §5.2；Figma D08–D11、D13。

**Figma:** 照 `FIGMA-NODES.md` 的 D08–D11、D13（淺色＋深色）製作，先截圖並讀畫面下方說明；完成後 App 截圖存 `work/gofly-mac/v1/screens/` 並與 Figma 並排比對，見 TRACKER「UI 準據：Figma」。

**Scope**
- renew 支援 `transport: wifi`：建置、簽名、透過網路覆蓋安裝（保留資料）、**只核對手機上現有配對**（不重新建立）、核對裝置支援、讀回 activation receipt。核對失敗時回穩定錯誤碼，UI 顯示「請改用 USB」。
- 先研究並記錄可行路徑（CoreDevice／`devicectl` 網路安裝、RSD over network、檔案讀回），寫在 `work/gofly-mac/v1/WIFI-RENEW-RESEARCH.md`，再實作。
- 進度與完成畫面與 USB 共用（D10 標題手動時為「正在延長簽名」、D11）。

**Acceptance**
- 離線測試覆蓋 Wi‑Fi 成功、找不到手機、配對核對失敗、中途斷線（→ D14）。實機驗收列入清單，不宣稱已驗。

**Evidence**
- `work/gofly-mac/v1/WIFI-RENEW-RESEARCH.md` 記錄固定版 `pymobiledevice3` Network usbmux 路徑與限制；實作只核對已保存 pairing（`autopair=False`），依 UDID 明確選 Network，覆蓋安裝後讀回並核對 activation receipt；Wi‑Fi 不建立或匯入 pairing，失敗要求改用 USB。
- `app/GoFlyMac/Bridge/Setup/Tests/test_setup_wifi_renew.py` 覆蓋 Wi‑Fi 成功、裝置不存在、配對驗證失敗與連線中斷。整套 Bridge 離線測試 94 passed（2 skipped）；GoFlyMac Swift 測試 65 passed，含 Wi‑Fi transport 路由測試。
- D08–D11、D13、D14 淺／深色 App 截圖位於 `work/gofly-mac/v1/screens/`，並已與對應 Figma V1 畫面並排核對；D10／D11 本輪重新擷取與核對。

**Not verified**
- 未在真實同一 Wi‑Fi 網路的已配對 iPhone 上執行覆蓋安裝、保留資料、裝置支援與 receipt 讀回驗收；未連接或寫入實體 iPhone。

**Stop if:** 需要改原生 patch／FFI；或 Wi‑Fi 上無法安全讀回 receipt（記錄研究結果，交使用者決定）。
