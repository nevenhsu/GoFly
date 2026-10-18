# M2／17：資料快照、重新安裝與還原鎖定

狀態：approved-v8／implementation-complete／device-deferred。使用者明確允許修正並重新審查後，新審查流程第3／5輪核准完整 v8 與精確儲存／producer 介面；原 v5 未核准紀錄保留。M1 軟體依賴於 a116a3c 完成。持久化、producer 與正式 App 接收整合已完成離線檢查。進度見 [M2 票](../issues/M2-reinstall.md)。

重新安裝是同機、明確選取資料的獨立權限，不是首次安裝的未知結果接管。Mac 在私密單一操作鎖下維持不同的 setup／reinstall 交易紀錄；未解決的首次安裝阻擋重裝。已完成前置交易先核實並封存；新目標的 setup 子狀態位於同一份重裝紀錄，不以第二個鎖或公開 bypass 旗標避開擁有權。

iOS 必須先完成所有實際 owner 的同步鎖定，再捕捉目前已接受的草稿／選項；取得全組之前不發布成功。取消了但實際仍在返回的解析、檔案或 native 工作仍阻擋匯出。來源讀取不清理檔案、不改權限、不正規化原始內容；只把已驗證的原始封閉清單及引用內容複製到不可變快照。可攜內容排除位置、任務、背景資格、ACK／clear／GPS、VPN、首次流程與配對憑證。

Mac 完整驗證並同步備份後，先提交移除意圖，再取得 iOS 同筆封存回報及當前程序身分，才有終止／移除權限。明確放棄只限移除意圖前，需實際解鎖回報；之後不能解鎖或猜測重試。URL 只有固定匯出／封存／釋放路徑及交易 nonce，本身沒有資料或移除權限。程序識別以目前 App 實際 Bundle／PID／命令回報及終止前再觀察為準，不採舊 PID 或 devicectl 成功文字。

新安裝在首次啟動前已有還原意圖，與 M1 準備門檻共同阻擋正常 owner／地圖，避免中途露出可操作畫面。每類別指標與收據同次原子提交；原始輸入與可編輯資料 namespace 分開。完成重播保留後續使用者修改，不重新套用舊偏好或舊 seed。恢復設定的語言／外觀／內部交易 marker 在同一份真實偏好 dictionary，marker 缺失才從持久的已驗 canonical 設定補回；不宣稱 UserDefaults 已 fsync。

新本機復原記錄只有所選資料與 `.unverifiedPreviousMovement`，沒有位置／活動任務；即使全部不選仍需建立。只有後續正常明確 clear 流程可以解除冷啟動待確認，資料收據、GPS 或安裝不解除。該 seed 不得在每次啟動覆寫後來合法記錄。

設計參考：2026-10-18 透過 Figma Console MCP Desktop Bridge 唯讀核對 [O10](https://www.figma.com/design/RtPV8PXCQJ2WXK3jk3kPrq/?node-id=38-65401)，畫面 393×852、標題26、內文14，只有實際類別狀態與 Mac 繼續提示；沒有查看已完成最愛或提早進地圖。此輪不增加 Figma prototype 接線或狀態組合畫面。O10 已實作；裝置驗證仍未完成。

2026-10-18 第五輪完整 v5 審查未核准，finding F-Q7-PartialCutlineOverwrite 指出失敗備份遺留的 cutline 可能在後續取消時覆寫較新的合法資料。當時停止剩餘重裝／還原實作，歷史修正及後續選項見[未核准報告](../../../work/gofly-ios/research/m2-17-v5-nonapproval.md)。使用者其後明確授權新流程，完整 v8 已核准；v5 本身仍未核准。來源先提交持久化 preparing 鎖，失敗後維持鎖定；沒有 authoritative root 的孤立 cutline 不得重寫 Session。這些核准設計已接入程式並完成離線檢查，不代表實機結果。

分段最終離線讀回：Root 的完整 Core／Transport486項、Mac47項、Python協定25項通過；M1 Python57項回歸通過。A1資料安全／容量與資源釋放、A2實際生命週期與快照、B1跨語言格式問題均已獨立審查關閉；Unicode格式字元的誤報以實際完整字元列舉與公開 decoder 測試排除。分段仍為未整合工作樹，未新增 M2 App 建置或任何手機操作。

最新整合證據：M2／17 軟體完成，build20未簽署device／simulator、首次流程UI4項、Mac67、M1 Python57、M2 Python51與跨語言完整收據核對通過。Core XCTest77項通過，Swift Testing首次併發有等待時限失敗，序列412項通過；最新儲存修正12項重驗通過。最後Standards／Spec具體finding均關閉。手機及接收端仍集中驗收，完整Mac目標另有續簽、修復、Wi-Fi與可攜包待完成。
