# 票 05：正式地點最愛與標籤交易

狀態：2026-10-17 Advisor 已核准下列設計；票 04 已完成並提交 91d0188，05 Executor 進行中。手機驗收集中延後。

- MapPlace 加可選正規化 address；原單一 title、精確 GeoCoordinate 不因自訂標籤而改寫。FavoritePlaceKey 使用來源身分＋精確座標，名稱、地址、標籤不參與等值。FavoritePlace 保存 key、不可變 place 快照及可選 label。
- FavoritePlacesPersistence 提供 read() throws -> Data?、replaceAtomically(with:) throws；replace 拋錯必須保證權威 bytes 未改。MainActor FavoritePlacesStore 是唯一可觀察真相，toggle／saveLabel 都先編碼、原子持久化完整候選 archive 成功後才發布；失敗保留原磁碟與原 observers 狀態。
- Persistence DTO 與 runtime 模型分開，不靠 Codable synthesis 繞過 GeoCoordinate 驗證。正式 schemaVersion 1、favorites 陣列；identity 的 kind 為 mapKit（含非空 value）或 coordinate，coordinate 含 latitude／longitude，另存 title／address／label。完整驗證有限與範圍、identity、重複 key、檔案／筆數／字串上限及版本，不丟棄壞筆後宣稱成功。
- 損壞、未知版本或非 regular file 進 mutation-blocked 狀態，原 path 原 bytes 不改，不發布健康空清單；拒絕新增／星號／標籤直到未來明確修復或匯入成功。05 不新增破壞性重置控制。
- 正式私有 Application Support/FavoritePlaces/favorites.json，目錄 0700、檔案 0600、completeUntilFirstUserAuthentication，保留正常備份資格。相同目錄 staging、設定權限與保護、flush 後，最後一步單次原子 rename；commit 後不做可能拋錯工作。
- Label editor 綁不可變 key／place 與最後已保存標籤。星號即時持久化，移除再加入使用最後保存標籤，不套用草稿；只有仍在最愛時 Save 才持久化新草稿。Cancel 只丟棄草稿，不復原即時星號。列表可用 label ?? place.title，詳情保留原名稱／地址／座標。
- 搜尋／座標／候選／詳情／最愛列表共享星號真相；選取、星號與長按命中分開，不改位置或任務。長按只在最愛列表開標籤；共用 Pin 詳情最多一張，綁開啟時的地點，不隨其他目標更新漂移。
- 不重用 prototype places.json v1（SavedPlace 的 UUID/name/GeoPoint/createdAt 與正式來源身分／地址／label 不相容）。17/M2 用獨立版本 restore 交易包裝正式 favorites payload，再由 iOS 驗證／stage／原子提交；交易進度與 credential 不放 favorites 檔。05 不提前寫模糊 name 的 prototype converter。

公開驗證：exact key／同名異地、validated decode 與上限／duplicate、壞 bytes 保護與 mutation lock、各 precommit 失敗的磁碟及 observers 不變、重開讀回、共享星號、移除／重加／Cancel／Save／寫入失敗、詳情不可變快照，以及選取／星號／長按不冒泡。僅離線及模擬器驗證，不冒充手機效果。

實作界線：最多 100 筆、檔案 1 MiB、標籤 120 characters、原 title 512 characters、address 2048 characters、MapKit identity 2048 UTF-8 bytes。Debug simulator 以有效 UUID 明確指定獨立真實檔案 namespace；O16 只用明確錯誤注入回傳 unconfirmed 驗 UI 與收藏，不製造 native ACK、GPS 或接收 App 證據，Release 無此入口。

整合驗證補強（Advisor 已核准）：ServiceController 新增可注入 watchdogSleep，正式預設仍 Task.sleep；測試使用每筆獨立、可取消 waiter 的手動時鐘，在已觀察準備／派送邊界後才觸發，不增加正式 timeout、不提前釋放 nativeBusy。原因為完整 suite 的百筆主執行緒資料驗證揭露原 20–40 ms 真實時鐘測試會在派送前被排程壓力觸發；不是將此輪失敗寫成通過。
