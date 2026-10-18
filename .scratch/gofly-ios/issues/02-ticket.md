# 02: 首次開啟、選用定位與必要 VPN 確認

**Status:** verification-pending

**Implementation:** complete

**2026-10-18 歡迎頁 loading 更新驗證：** 初次啟動共用歡迎頁已實作；啟動 UI 6／6（含 loading 停用／完成可前進／失敗鎖定）、既有 onboarding UI 4／4、Swift 514 項及 unsigned iPhone build 通過。完整 `check.sh` 在既有 `NativeBridge/tests/check-error-mapping.sh` 漏列 continuation 來源檔時失敗，不宣稱整體檢查全通過。初次 UI run 的 loading 元件類型查詢與測試延遲已修正並重跑，保留原失敗紀錄。證據見 `work/gofly-ios/welcome-loading-verification.md`；尚未安裝到手機。

**Device verification:** deferred-by-user（全部實作完成後，由使用者統一用 iPhone 驗收）。

**Development policy:** 依序持續開發至全部實作完成；開發期間不要求使用者連接 iPhone、不等待 USB、不安裝或操作實機。先完成本票實作、建置、自動化／模擬器驗證及必要審查，再繼續下一票；所有實機項目交由使用者最後依[集中手機驗收清單](../DEVICE-ACCEPTANCE.md)測試。前置票實作完成即可解除開發依賴，deferred-by-user 不阻擋後續實作；實機未驗不標 done。

**Blocked by:** 01（已完成）。

**What to build:** 完成歡迎、選用定位與 VPN 確認後進入地圖；拒絕定位仍能繼續。

**Design reference:** 01 A01／A02／B01／B06、02 F07、07 C03／C05。

**Acceptance criteria:**

- [ ] 初次啟動直接顯示歡迎頁，無獨立檢查畫面；底部 loading 期間下一步停用，檢查通過後才可手動前進；失敗仍顯示設定提示。此為 2026-10-18 已實作更新，新版手機驗收待執行。
- [ ] 定位允許、拒絕、略過皆可前進；缺少真實 GPS 只出現可關閉小提示，不捏造位置或反覆打斷。
- [ ] VPN 必須實際可達才可下一步；前景立即與每 5 秒探測、單次 2 秒逾時，離開取消，避免探測重疊與舊結果覆寫。
- [ ] 手動檢查與外部返回重查共用結果；按下一步再次核對，成功或返回外部 App 均不自動啟動／送點。
- [ ] 暫時 waiting 後 ready 可在同一 probe 成功；持續 waiting 仍依原兩秒期限失敗並關閉，不能提前判失敗或延長期限。
- [ ] 說明頁以三張編號步驟卡呈現，區分 LocalDevVPN Connected 與 GoFly 可達；三語提供本機網路權限與重連提示。返回並檢查不跨過必要 VPN／fresh Next 確認。

**Verification:** 首次流程 UI 驗收；探測逾時／取消／成功後失效測試；實機切換 LocalDevVPN。

## Implementation record

2026-10-18：使用者在外拔掉 USB 測試 build 22，回報 LocalDevVPN Connected、GoFly onboarding 不可達；系統設定頁無本機網路選項，不能推定權限遭拒。已對照成功 prototype，重現 build 22 把暫時 waiting 直接當終止失敗的差異，三項回歸測試先 red 後 green；修正保留既有兩秒期限。說明頁改為三張步驟卡、正確的 GoFly 可達狀態、缺少設定開關時直接返回的提示及首次流程可用的系統設定入口。12 項 transport 與 32 項首次流程／復原測試、unsigned simulator／device build、獨立審查通過。真機故障確已觀察；修正版尚未安裝，不能標示真機修復成功。詳細離線證據：`work/gofly-ios/vpn-regression-20261018/RESULT.md`。

2026-10-17：以票 01 結案後 `e1b6c5c` 為本票比對基準。沿用已核可的 public controller／probe／permission／UI 測試界線，依序 red → green 驗證略過、允許／拒絕定位、不自動跨頁、fresh Next、背景／遲到結果、五秒節奏及返回前頁。Core 不含裝置啟動能力；completion flag 只由目前世代的 fresh Next 成功 callback 同步提交。

新增 GoFlyTransport（Advisor 補充核准），與 native reset 共用固定端點／兩秒 timeout；實際 loopback 與可控網路終止測試分開驗證。SwiftUI 三語首次流程與實際 permission-only adapter、已完成地圖測試 fixture、Debug simulator 實際拒絕端點已建立；最終完整 Swift 測試分別為 Core 23 項／3 suites、Transport 9 項／1 suite，全數通過；simulator 4 項 UI 驗證通過，包含實際系統拒絕定位仍到 VPN、實際拒絕端點停用下一步、返回與繁中深色最大字級，以及既有地圖 fixture。build 4 已簽署建置。Standards／Spec 雙軸獨立審查皆無 finding。真機 LocalDevVPN 切換／完成後重啟持久化仍待驗；依使用者最新指示延後至所有實作完成後集中驗收，不阻擋票 03。
