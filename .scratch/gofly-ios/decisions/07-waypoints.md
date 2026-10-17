# 票 07：多點穩定身分與完整規劃

2026-10-17 Advisor 已核准；06 完成實作、驗證及提交後才開始 Executor。真機全部延後。

RouteDraft 只保存已確認有效節點，支援 0…27 個（最多 25 途經點）；首尾角色由順序計算，少於兩點不開始／儲存，不補空值或假座標。所有節點保留穩定 ID、地點身分及精確座標。

新增 session 是暫存 node ID，不先插空節點；有效 Confirm 才插在原目的地前（少於兩點則追加），當下再驗容量。Cancel 不留空列。既有 picker Confirm 找原 ID，重排仍更新該筆、刪除則拒絕；明確「清空地點」後 Confirm 刪除原 ID，清 query 本身不刪除。非空無效輸入不可覆寫。

所有節點可用左側獨立 44pt 把手排序，中間開 picker，右 44pt 垃圾桶刪該 ID；拖動浮起列、等高佔位與插入提示，長清單邊緣自動捲動，放開才提交，取消恢復原順序。VoiceOver 移動／刪除走同一 ID mutation 並重算角色。運作／暫停仍沒有編輯入口。

最多一個 .current；重排時隨原穩定 ID 移動，不隱式改值。Start 當下只解析一次（確認模擬位置優先、其次新鮮有效 GPS），將確切座標凍結進 execution snapshot；移到中間／末點也指這次 Start 的位置，不是行經該點時的動態位置。等待 marker 快取不是來源。Use Current 只提供給首列，且其他節點沒有 .current 時才可設定，避免建立多個佔位點。

Start 先驗所有已解析順序座標，明確拒絕相鄰相同座標。逐 leg 順序呼叫 RoutePlanning，每段依 06 的 50m 端點吸附上限驗證並保留原始道路頂點，再加入精確首尾；拼接只移除兩段共用的重複界點，全路徑最多 10,000 點。任一段失敗、取消、全域超限或 admission revision 過期，整份失敗且沒有部分 intent／native admission。全部段落成功後才建立同一不可變 execution，沿用06單 owner／FIFO／ACK 進度及暫停取消。

必要測試：穩定 ID 增刪重排／picker 遲到、query vs 明確清空、27 節點確認時上限、移動 .current 的 Start 凍結／缺 GPS 拒絕、各段失敗／全域點數／無 native admission、完整有序路徑、拖曳取消／邊緣捲動與 VoiceOver 排序刪除。07 不加入來回、GPX、最愛路線或背景執行。


Advisor 補充核准初始少點狀態：不建立假空列；新增操作依有效節點數顯示 0「新增起點」、1「新增目的地」、2…26「＋新增途經點」，27 停用。仍用同一 provisional stable ID picker；Confirm 在 0／1 筆時追加，兩筆以上插在目前目的地前，Cancel 不插入。角色只依確認／重排後位置衍生；.current 隨原 ID 移動。


Advisor 已核准編輯 Current 的窄 seam：stagePickerCurrent(id:) 先核對 session 與目前位置資格，再由 Candidate 內部 cancelPendingLookups 取消名稱／反查、推進編輯 revision，保留 query／候選／結果與 canGo 驗證鎖。不另存 Core Current 勾選狀態；Confirm 仍明確接收 useCurrent 並重新驗資格。App 只在勾選轉 true 呼叫，false 不作廢新 clear（專用清空先取消本地勾選，延後的 false callback 不能撤銷剛建立的 clear）。這同時防止 clear→Current on/off 復活刪除意圖，以及舊反查改 query 導致已選 Current 被取消。

專用清空意圖只對 reset 完成當下的 Candidate editing revision 有效。任何後續 query／選取／map tap／reset 永久作廢該次 clear，普通清除 query 不能讓舊刪除意圖復活；只有再次專用清空可重新取得有效 clear revision。metadata 只補資料而不推進 revision。
