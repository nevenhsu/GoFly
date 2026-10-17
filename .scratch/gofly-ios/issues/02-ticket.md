# 02: 首次開啟、選用定位與必要 VPN 確認

**Status:** ready-for-agent

**Blocked by:** 01。

**What to build:** 完成歡迎、選用定位與 VPN 確認後進入地圖；拒絕定位仍能繼續。

**Design reference:** 01 A01／A02／B01／B06、02 F07、07 C03／C05。

**Acceptance criteria:**

- [ ] 定位允許、拒絕、略過皆可前進；缺少真實 GPS 只出現可關閉小提示，不捏造位置或反覆打斷。
- [ ] VPN 必須實際可達才可下一步；前景立即與每 5 秒探測、單次 2 秒逾時，離開取消，避免探測重疊與舊結果覆寫。
- [ ] 手動檢查與外部返回重查共用結果；按下一步再次核對，成功或返回外部 App 均不自動啟動／送點。

**Verification:** 首次流程 UI 驗收；探測逾時／取消／成功後失效測試；實機切換 LocalDevVPN。
