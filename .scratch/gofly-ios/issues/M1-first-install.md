# M1：正式 GoFly 首次安裝與 Mac 交接

**Status:** verification-pending

**Implementation:** complete

**Device verification:** 單機 producer／首次啟動已確認（2026-10-18，iPhone 15 Pro／iOS 27.0.1，build 22）；完整 Mac GUI、其他版本及負向實機矩陣仍待驗。

**2026-10-18 實機補記：** 使用者要求先行安裝並同意保留備份後替換舊測試包。最終正式 producer 回覆 `complete/confirmed`，安裝、本次配對匯入及支援觀察三項均為真，且取得 App-owned activation receipt；正常 Welcome 畫面已核對。使用者已接手拔 USB 測試，之後不再操作手機。過程中的 USB 序號、配對欄位型別、檔案／交易大小限制、RSD、空 transfer namespace 及 Cryptex 實際版本核對問題均已修正、審查及回歸驗證。失敗交易與備份私密保留；本次人工核准的替換不宣稱為自動復原功能。手機產物為 `b2179d2` 快照加空 namespace 修正；實機與打包證據位於 `work/gofly-ios/device-test`。

**Blocked by:** 無。16 已於 c44ab42 完成軟體結案提交；Root 已讀回完整 60 個不同 UI 案例的成功覆蓋，並明確交回模擬器、放行 C 的測試與建置。真機驗收仍延後，不作為開發阻擋。

**What to build:** Mac 對明確選取的同一支 USB 裝置，完成正式 GoFly 部署、本次私密配對匯入及必要裝置準備，取得各項真實回報後才顯示完成。手機不下載支援資料、不新增 U19 或自動啟動移動。

- [x] 唯讀預檢不建立配對或安裝；使用者明確開始後才執行，沿用固定正式 App／Team／裝置與交易。
- [x] 先驗簽章、描述檔、裝置與檔案；實際支援準備、App 資料提交及 Mac 完成證據分開，不以快取或程序結束當成功。
- [x] 重新開啟保留原交易；中斷結果不明不重送安裝／配對，不接管任意既有 App、不自動移除資料。
- [x] iOS 在交接完成前不建立正常服務與任務，資料驗證及原子提交後才進原流程；資料回報不代表 VPN／GPS／移動已可用。
- [x] Mac 首次流程結束於 U18；續簽、重裝與備份尚未實作時不顯示模擬成功，預覽獨立標示。

**Implementation record:** 基準 51b8fb8；票 16 以 c44ab42 完成軟體結案；[核准決策](../decisions/M1-first-install.md)。v5 經設定的 Advisor 第5／5輪核准，M1P-01／02／03／04 均已納入。Core 458 項（52 setup、397 既有 Core、9 Transport）、Mac 37 項、共享 LocalGo 52 項通過。Python 最終 57 項交易／支援／跨語言整合檢查通過（44 交易、10 支援、3 整合）。最終 App 聚焦 6 個模擬器案例通過、零 skip／runtime warning；另外 8 個受影響既有 UI 案例通過。三語最大字級畫面人工核對沿用同版面較早產物，不能稱為最終 binary 的重新巡覽。SDK 27.1 未簽署裝置 build 19、Mac 本機開發 bundle、428 鍵三語與實際 bundle 資源、native verifier 通過。Spec／Standards 審查修正已逐項讀回。沒有連接、列出或操作手機，沒有簽署、安裝、下載或掛載。

**Verification:** 新行為使用公開生產邊界的失敗斷言、受控系統介面、實際暫存檔與 IO 故障驗證。保留初期 setup／測試修正的來源與先後，不將全部測試稱為 test-first。Mac bundle 內 11 份 Python 來源與工作目錄摘要一致；固定 python -I 入口的唯讀 status 回覆有效，stderr 空、狀態目錄未改變。安裝結果不明仍不可接管；一次性交付不明只查詢；錯誤已掛載支援不自動卸載／替換；資料收據不代表硬體準備、VPN、clear 或有效 GPS。手機驗收仍為 deferred-by-user，不標 done。
