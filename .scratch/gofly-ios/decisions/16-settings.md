# 16：即時偏好與共用設定流程

狀態：approved-v2 / implementation-in-progress。基準 `c60608142afe678b9802e541eefd2bc1685f6c3e`；預定 build18。

Root 編寫方案；Advisor 第1輪要求補齊同步重置准入訊號 P16-01，第2輪核准 v2。P16-01 已納入，無未決項；最多五輪，尚餘三輪。實作細節與公開介面凍結另記 work/gofly-ios/research/16-api-frozen.md。

## 偏好及既有任務

App 只有一個 MainActor observable GoFlyPreferences，實際 UserDefaults 保存單一版本字典 gofly.preferences.v1，含語言 system／en／zh-Hant／zh-Hans 及外觀 system／light／dark。未知值獨立回退 system，讀取不覆寫；明確變更才保存。原生 Picker 顯示已保存選項，立即套用並關閉，取消不改。

選定 lproj 搭配明確英文 fallback，格式使用相同 Locale；使用者標籤／地名／檔名保持資料原值。穩定 root 注入 locale／colorScheme，不以 id 重建 Service、路線、搖桿或背景 owner。背景文字刷新只更新同一要求，不提交新工作或送點。

地圖沿用同一 MKMapView／camera／annotation，實際 trait 變更重新解析語意 marker／outline／polyline 顏色與輔助文字。等待 GPS 的半透明箭頭及路線編輯 Pin 回填、無 Go 規則不變。

## 六個設定頁

依既有 Figma Console 靜態讀回實作 C01／C03／C04／C05／C06／C07。首頁保留服務 card 與分組列；完整背景執行卡放 C04，與實際系統背景重新整理狀態分開。權限只讀實際 OS 狀態，明確操作才開系統設定／LocalDevVPN，返回重新檢查，不猜測成功。使用原生導覽與唯一返回，維持邊緣返回手勢。

裝置資訊顯示 UIDevice／Bundle 與已保存配對資料；資料已保存不表示裝置已驗證。簽名日期、Team、DDI 無介面可取得時如實顯示尚未取得。常駐 Mac 更新簽名說明，不在 C06 增加 VPN 按鈕或隱藏握手。

## 重置與探測的同步界線

Service 保留 resetTunnel()->Bool 相容性，新增唯讀 TunnelResetState：idle／running(id)／succeeded(id)／failed(id,failure)。實際准入先封閉連線門檻、開始 lifecycle、保存本次 UUID，再同步發布 running，最後才排入 native 工作；watchdog 封存失敗，遲到回覆不能覆寫。

Recovery 直接消費 incoming $tunnelResetState，不能延後讀 objectWillChange。同步撤銷舊 probe generation／結果，仍持有實體 Task 到真正返回。共用 C01／C05 reset 先等已取消但未返回的 probe 排空，再重查同一明確意圖並提交一次。直接 Service reset 至少同步作廢舊證據；不承諾替外部 probe 排空。分開 resetConsentID 與實體 resetTaskID，own-admission flag 防止自身 running 通知取消自身。

停止、恢復 GPS、場景離開會撤銷等待中的 reset 意圖；Restore 不發布 nil movement boundary，因此另直接消費 incoming phase.restoring／stopping。舊探測成功、取消工作排空或 TCP 成功不能提高 native 健康、解除 cold hold、恢復 GPS 或自動 Resume。

## 交付檢查

先以既有公開 API 重現直接 reset 的舊 probe 漏洞，並在新增偏好程式前執行實際 UI 缺列 RED，再逐步完成。不得用缺少 API 編譯失敗代替行為 RED。只使用公開邊界與真實 App 偏好儲存，不新增 @testable、私有建構子或假 ACK／GPS／背景資格。

完成後檢查完整 Swift、設定與既有 UI、雙 SDK27.1 未簽署建置、三語 key／格式／bundle、native verifier、diffcheck 及獨立 Standards／Spec 審查。SDK26 未安裝，不聲稱26編譯或真機通過。所有 iPhone／USB／簽署／安裝、真實權限／VPN／背景／接收端與 VoiceOver 留使用者最後集中驗收。


## 整合檢查記錄（尚未完成全部 UI）

完整 Swift406（Core397／46 suites＋Transport9）與 native verifier 通過。初次完整run有三項舊測試問題：reset 現在同時關閉 fence 與准入，舊測試過度假設 revision 恰好加一；另一測試在實際500ms sleep登記前推進 controlled clock。修正為驗證 revision 前進及等待真實 clock request 後，第二次完整run另發現同族 submission 測試缺少 cadence 同步；補齊並單項通過後，第三次完整run406全通過。未改動定位／ACK產品邏輯，未把初次run改稱通過。

Root另以實際行為RED補上 Service watchdog 後遲到 success 不可覆寫 typed failure 的回歸，修正要求 matching revision／仍 running UUID；共10個公開 reset 測試與33個既有 affected 回歸通過。正常 running reset 本身不開放 Stop；逾時 repairRequired 後可 Stop，保留FIFO clear與原封存失敗。新UI曾實際發現原生Picker輔助文字重複，已明確設定列名與實際已選值；不是合成選取勾記。

Standards ST16-001（重複 OS 狀態投影）已合併至 GoFlySystemStatus；Spec SP16-01 採明確 State 保留既有singleton，舊版本 root 是否漏更新屬審查推論，未稱已重現；SP16-02 補齊預格式化數字／百分比的選定 Locale。兩軸最後readback均無剩餘finding。核心資料、位置／native資料格式不變。App狀態查詢的實際main-thread警告另改為背景讀取，初次待回覆顯示未知；修正後實際 UI 及最終兩 SDK27.1 未簽署建置通過。


## 畫面與偏好檢查讀回

原生 menu Picker 最初只渲染窄選項，未呈現完整語言／外觀列；改用原生 Menu 包含 bound Picker，列名、已保存值與 chevron 完整呈現，仍由原生單選與勾記處理。實際選取覆蓋四種語言、三種外觀、關閉不變、無效值與不支援語言 fallback；較早的 AX 重複名稱另以明確 label／value 修正。

最大 Dynamic Type 的實際截圖曾顯示英文狀態在並排列內不自然斷字；共用 value row 在輔助字級改為上下排列，C05 操作同步改為直排。最新三語六頁巡覽通過，Root 核對 C01 三語及 C03–C07 英文截圖；深色系統下實際地圖 trait、設定列及原生選單通過且完成截圖核對。沒有用截圖或 AX 測試宣稱已完成真實 VoiceOver 操作。

目前 production source 已凍結，build18 雙 SDK27.1、三語414 key／格式／實際 bundle、native verifier、完整 Swift406 及最後兩軸審查皆通過。新增偏好／資料保留 focused UI 最後讀回與完整60項 UI 回歸仍進行中；未完成部分不能算通過。
