# 票 03：搜尋、候選與單點命令邊界

狀態：Advisor 審查中，尚未開始 executable Executor。使用者已明確要求依序完成所有實作與自動驗證，真機測試延至最後集中驗收；本票不安裝或操作手機。

## 候選與搜尋

- Core 使用已驗證有限／範圍合法的 `GeoCoordinate`，地點身分與單一 title 另由 `MapPlace` 保存。每次選取建立有獨立 ID 的 `TeleportCandidate`，保留來源地點身分；Go 捕捉不可變候選快照。
- `PlaceSearching` 是名稱／地址查詢邊界；`CandidateController` 管理 query、結果、候選、輸入錯誤及搜尋世代。MapKit adapter 只搜尋，不接觸裝置命令。
- 首次名稱結果不預選，選定後保留列表；有效座標立即成為候選，無效格式／緯度／經度分別回報，保留上一候選但停用 Go。只有有效座標修正或明確選取有效地點才解除該輸入錯誤。空白或新名稱 query 不捏造候選。
- 新 query／明確地圖選點作廢舊搜尋的發布權並取消；底層忽略取消時，遲到結果不能覆寫新狀態。查詢或鏡頭動作沒有 DeviceService 能力。

## 單點與安全清理

- `ServiceController` 延用既有 FIFO／revision／watchdog，是 Start／Stop／Restore／Reset 與單點命令共用的排程邊界。Go 必要時只準備一次；三次準備重試及舊任務交接留票 04。
- Go 傳入 `TeleportCandidate`；controller 建立新操作 ID，準備成功後仍執行原快照，防連點、不同操作不得交錯。Stop 若發生於準備完成前，作廢送點發布／執行權並排入必要 clear；若已進入 native set，等待其真正返回後才 clear，不假取消 FFI。
- `DeviceService` 新增單點結果契約：尚未呼叫 native set 的失敗可確定 not-sent；一旦進入 set，除非收到同一請求的已驗證成功協定回覆，任何錯誤／逾時都是 unknown，不自動重送。unknown 鎖住 Go，只有明確 Stop 終結後可建立新操作；不新增不存在的位置查詢能力。
- 成功才發布已確認模擬座標並移除原候選 Pin／Go；若使用者準備期間已瀏覽新候選，只清除與原快照 candidate ID 相同者，保留未提交的新選取。
- `VerifiedDeviceSession` 在同一 owned session 的 set 前立即重驗綁定身分。Native adapter 在既有 serial queue 擁有並保留 location session，成功／unknown set 後均不按次關閉；clear 使用 owned verified session，該次 clear 真正返回後才釋放。clear 失敗不自動重送；下一次明確 Restore 可建立新 session。Reset 仍僅 stopped 時修復 GoFly 連線，不當作 clear 證據。

## 回覆與原生來源補強（待最後核准）

Pinned archive 已有 location_simulation_set symbol，但目前 shim 未匯出。上游 set／clear 只接收下一個 channel message，未核對請求／錯誤；新增 checked void reply helper，核對請求 ID、channel、conversation 及合法成功 payload，設有整體逾時。set／clear 共用，避免遲到 point reply 被當成 clear ACK。

成功 void profile 需依 primary 實作確認，不能只假定空 OK：已發現 pymobiledevice3 支援 OK 空回覆與 OBJECT null／NSNull。Pinned ns-keyed-archive decoder 把 `$null` 解成空 dictionary，不能只用 decoded empty dictionary 判斷 null；須檢查原 archive root／class 身分。詳細 patch 與可接受 payload 以 Advisor 最後核准及 scripted Rust 測試為準，不宣稱真機已驗。

## 顯示位置與鏡頭

- 泛用 `PositionMarker` 分開記錄 GPS／模擬來源及 fresh／waiting，只供地圖顯示；不捏造 `RealLocationObservation`。
- 目前 GPS 證據、已確認模擬位置及最後顯示快取分開。Stop／Restore／未知送點作廢目前位置證據，但保留最後箭頭，以 50% 透明表示等待；有效新 GPS 才更新並恢復 100%。模擬任務有效時，GPS callback 不覆寫已確認模擬箭頭。
- 使用 SwiftUI 面板與獨立 MKMapView canvas。量測頂部實際狀態／提示底緣、底面板頂緣及安全區；面板已跟隨鍵盤時不重扣鍵盤。用 setVisibleMapRect(_:edgePadding:animated:) 置中可見區域。
- 候選／成功位置或 viewport 尺寸變更才建立鏡頭意圖；使用者拖圖不觸發送點或無限拉回。Pin 與 Go 各自至少 44 pt，所有地圖 icon 下方不加文字；詳情與選項單 title。最愛功能與模式切換由後續票接入，不放無作用按鈕。

## 已核可票單的公開驗證界線

票 03 Verification 的座標／候選／送點身分對應 Core 公開 controller／protocol，沿用票 01 的服務 FIFO 與同-session device seam。驗證輸入分類、無效保留、首結果不自選、遲到搜尋、快照不串位、防連點、Stop 前後、unknown 鎖定、顯示快取不作為 GPS／clear 證據。Rust scripted peer 驗證 reply correlation／error／EOF／timeout 與遲到 set 不冒充 clear；shim／ABI／manifest hash 一併檢查。

模擬器驗證實際座標候選、Pin 詳情不執行 Go、鍵盤／面板／Dynamic Type 下的可見置中；不以假 native 成功當硬體證據。兩個接收 App 與最終手機效果列入集中驗收表。
