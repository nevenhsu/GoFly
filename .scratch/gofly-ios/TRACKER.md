# GoFly 本機票單

2026-10-17 使用者指示「用 implement 依序開發」，以已討論的 18 張票為執行來源，先用本機票單追蹤。每票一檔，Blocking edges 指票號；ready-for-agent 表示可依前置依賴領取，不代表真機已驗收。狀態分 ready-for-agent／in-progress／verification-pending／done；done 表示該票完整驗收通過，實作完成另以 Implementation 記錄。M1／M2 為計畫列出的 Mac 交接依賴。

最新執行安排（2026-10-17）：使用者要求「依序開發，先不做實機測試，做完之後統一用手機驗收」。每票先完成正式實作、適當自動化驗證、雙軸審查與提交，再標 Implementation: complete；真機欄另記 deferred-by-user，票狀態保留 verification-pending。前置票的實作完成即可開始下一票，延後的真機驗收不阻擋依序開發。不再安裝／操作手機或等待 USB；最後提供集中驗收清單。不得將模擬器／注入測試寫成真機已通過。

此安排適用所有剩餘 tickets（含 14 背景可行性、15 背景實作、17 跨端還原與 18 整合驗收準備）：不得在逐票結尾暫停要求接 iPhone，也不得因前置票尚待實機驗收阻擋下一票。14 先交付候選方案、設計審查與離線驗證，15 依此完成實作並保留硬體未知；18 先完成自動化回歸、最終建置與驗收包。全部實作及可離線驗證工作完成後，再一次交由使用者測試手機。實際程式失敗或契約未決仍須修正／釐清，不能以延後驗收跳過。

各票審查基準記於該票 Implementation record：票 03 為 16d8f3f，票 04 為 0379d10，票 05 為 91d0188，票 06 為 bcf9d0d，票 07 為 9057718，票 08 為 d98f8c7，票09為1e5835d，票10為dcf670e，票11為f039a95，票12為57565c7，票13為4a0d9b3，票14為1b6dcd6。既有未提交且不屬當票的文件變更不納入實作提交；每張實作完成後作適當驗證與 standards／spec 雙軸審查。

測試界線沿用票 01 的正式服務 public interface 與 device-adapter 系統邊界，觀察啟停／clear／reset 可見結果、錯誤與取消／遲到結果；不測私有欄位。原生握手／同機身分／檔案保護另在 native 邊界驗證，不以 fake adapter 當真機證據。

票 06 實作／離線驗證完成：完整 Swift 112 項、完整 simulator UI 19／19、未簽署 iPhoneOS build 8、三語與 native verifier 通過，雙軸無剩餘 finding；路線編輯依最新使用者規則可用地圖 Pin、無 Go。手機維持集中驗收，可開始票 07。


票07實作／離線驗證完成：完整Swift134項、完整simulator UI23／23、未簽署iPhoneOS build9、真實host MapKit多段join、177key三語parser及native verifier通過，雙軸零finding。多點有效節點、穩定ID、確認刪除、拖曳／27點自動捲動與全路線規劃已完成；手機及實際VoiceOver／OS中斷取消保留集中驗收，可開始票08。


票08實作／離線驗證完成：完整Swift150、完整simulator UI25／25、unsigned iPhoneOS build10、198key三語parser／native verifier／diffcheck及雙軸零finding。ACK固定位置軸、同lease即時改向、端點折返、關閉後原方向至下一端點、暫停控制與控制修訂競態已實作。手機實際往返及active方向控件手感仍集中驗收，可繼續票09。


票09實作／離線驗證完成：Swift188、unsigned iPhoneOS build11、248key三語parser／native verifier／diffcheck、Standards及Spec零finding。完整UI30case已覆蓋，full run29通過／唯一test浮點43.99999999999994誤判，test-only1e-6pt容差修正後受影響AX三語單項重驗通過；產品未變，不重跑其餘29且不宣稱該run30／30。GPX三kind完整資料／安全匯入匯出、10kactual主地圖預覽、獨立紀錄與deleteundo／relaunch皆已實作；手機deferred-by-user。可繼續票10。


票10實作／離線驗證完成：完整Swift231、完整simulator UI35／35（1537.711s）、未簽署iPhoneOS build12、285key三語parser／native verifier／diffcheck及Standards／Spec零finding。手動全節點及完整GPX獨立保存，按下Save才解析有效Current並明示實際排除結果，標籤只改原筆，duplicate／deleteundo／relaunch及stale Load隔離皆驗證；新增與既有最愛、GPX、路線、瞬移與服務流程在同一held run通過。手機deferred-by-user，可繼續票11。


票11實作／離線驗證完成：完整Swift269、完整simulator UI38／38（1713.531s）、未簽署iPhoneOS build13、304key三語parser／native verifier／diffcheck及Standards／Spec最後readback零finding。第三mode搖桿、實際地圖方向、可選起點、500ms ACK-only單一writer、放手／暫停／Resume neutral／背景退休及可安全重試均實作；路線地圖Pin回填無Go仍在完整run通過。手機deferred-by-user，可繼續票12。


票12實作／離線驗證完成：完整SwiftCore293／36suites＋Transport9／1suite，共302PASS；完整simulator UI39／39 PASS（1767.040s）；未簽署iPhoneOS build14、312key三語parser／native verifier／diffcheck通過，Standards及Spec最後readback零finding。自動漫步與手動共用唯一送點流程；目前目標無Go、候選Go只換目標不瞬移；路線編輯地圖Pin回填無Go亦在同held run通過。手機deferred-by-user，可繼續票13。

票13實作／離線驗證完成：Root v5／精確API經Advisor第5輪PLAN_APPROVED；執行基準4a0d9b3，build15。最新完整SwiftCore335／40suites＋Transport9／1suite，共344PASS；完整simulator回歸42／43（2017.930s，唯一失敗為舊RT預設值預期），test-only改成先明確設定live速度2／RT0再Load後，受影響單項1／1通過（210.374s）；其餘42項不重跑，合計43案例覆蓋，不將原run稱43／43。未簽署iPhoneOS build15、332key三語parser／格式／plutil、native mapper及personalized branch等3項邊界檢查、native verifier與diffcheck通過，Standards／Spec最後readback均0finding。實際裝置、接收位置與VoiceOver仍deferred-by-user；沒有連接／安裝／操作手機。 可依序繼續票14。


票14候選／離線交付完成：基準1b6dcd6／build16，Root v5第5輪核准且API凍結。完整SwiftCore355／41suites＋Transport9／1suite，共364PASS；final public focused20／20PASS；未簽署iPhoneOS／iPhoneSimulator SDK27.1 build16皆成功（simulator含arm64／x86_64）；native verifier／diffcheck通過，Standards0／Spec0。App初始化、plist、既有送點／生命週期及三語資源未變，本票未重跑UI；332key三語的13既有驗證仍適用。沒有手機／USB／簽署／安裝／實際scheduler或接收App測試。 literal-wildcard dispatch未證實，15先核准完整ID一次註冊及原子native admission再啟用；實際iOS26／27背景／接收位置仍deferred-by-user，可依序開始15。
