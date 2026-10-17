# 06: 兩點路線：開始、暫停、取消與自然完成

**Status:** verification-pending

**Implementation:** complete

**Device verification:** deferred-by-user（全部實作完成後，由使用者統一用 iPhone 驗收）。

**Development policy:** 依序持續開發至全部實作完成；開發期間不要求使用者連接 iPhone、不等待 USB、不安裝或操作實機。先完成本票實作、建置、自動化／模擬器驗證及必要審查，再繼續下一票；所有實機項目交由使用者最後依[集中手機驗收清單](../DEVICE-ACCEPTANCE.md)測試。前置票實作完成即可解除開發依賴，deferred-by-user 不阻擋後續實作；實機未驗不標 done。

**Blocked by:** 04。

**What to build:** 確認起終點後開始移動，能暫停繼續、取消回編輯或自然到達。

**Design reference:** 03 D02／D03／D04／D04a、REF03。

**Acceptance criteria:**

- [x] 正式路線草稿與任務分開；起終點透過共用 search mode／最愛／地圖 Pin 確認回填，取消不改值；編輯 Pin 不顯示 Go，地圖精確座標立即帶入，地名／地址僅補資料且遲到不能覆蓋新輸入；起點使用明確指定位置或已確認模擬位置／有效 GPS，無位置可手選。
- [x] 明確開始才先移至指定起點再走，規劃不動、不偷偷增加接近起點路段；暫停／繼續保留同一任務進度。
- [x] 運作／暫停只有精簡控制、沒有模式及編輯入口；暫停取消先確認。取消保留草稿及最後模擬位置、不 clear；自然完成回初始並保留端點與服務。

**Verification:** 排程／精確起點／50m 道路端點吸附上限及原始頂點保留／ACK 進度與取消後未知鎖測試；最後由手機驗證路徑及接收端位置。

## Implementation record

2026-10-17：實作／審查基準 bcf9d0d。Advisor 核准 decisions/06-route.md：兩點穩定草稿、明確 Confirm picker、MapKit 步行規劃、凍結路線、ACK 進度、單一 ServiceController FIFO pump 與精確 lease 暫停／取消；另核准規劃 admission revision 及競態優先順序。手機全部延後。


本票正式實作已接入：獨立兩點草稿與穩定 picker、地圖 Pin／搜尋／最愛確認回填、可取消 MapKit 步行規劃、50m 道路端點吸附限制及完整原始頂點保留、不可變 execution、單一 owner 有界 FIFO 與 ACK-only 500ms 排程。暫停等已 claim 工作真正返回，Resume 同 lease；取消保留位置／草稿且不 clear，取消後未知結果仍需 Stop；自然端點 ACK 才完成。

最新使用者地圖 Pin 規則已取代編輯情境 No Pin：立即精確座標、反查僅補名稱／地址、保留同 UUID 及來源座標，遲到 query／select／新 tap 不覆寫；編輯 Pin 可開共用詳情且沒有 Go。active picker 公開 observable 更新會通知父層地圖，關閉／替換解除舊訂閱。候選 UUID 改變才更新相機，補 metadata 不搶使用者移動鏡頭。短高度保留可捲動選項／星號及固定 Confirm，使用實測輸入高度與實際 viewport 驗證完整可見。

已驗證：完整 Swift Core 103／13 suites＋Transport 9／1 suite，共 112 項通過；最新未簽署 iPhoneOS build 8 成功。真實主機 MapKit 原公開起點偏差 68.822m 依 50m 規則正確拒絕；另一組明確道路端點偏差 0／0.011m、26 點約 811m、精確首尾通過，正式 reverse geocoding 亦取得名稱／地址並保留精確點。App 沒有自動改使用者端點或改直線。

最終完整模擬器 UI 19／19 通過（458.285s，06d）；涵蓋實際 MapKit 地圖 Pin 回填、Confirm／Cancel、無 Go、公開通知後即時置中、最大字級／深色／鍵盤下完整 input／44pt clear／固定 Confirm，以及 01–05 回歸。三語 165 keys 一致、parser／native verifier／git diff --check 通過，Standards／Spec 兩軸無剩餘 finding。已中止的06／06b／06c不當通過。沒有連接、安裝或操作手機；模擬器沒有 native ACK／有效 GPS 成功 fixture，實際執行畫面及接收 App 位置仍由使用者最後集中驗證。


軟體實作與可離線驗證完成，可接續票 07；真機保留 verification-pending／deferred-by-user。執行畫面中的 running／paused／收尾與接收 App 位置沒有在模擬器偽造成功，仍依集中手機清單驗證。
