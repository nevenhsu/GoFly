# M1：首次安裝的實際證據與資料啟用

狀態：approved-v5／implementation-complete／device-verification-pending。基準 51b8fb83a05691d6f6a3545d481241374b721930。Root 編寫方案，設定的 Advisor 第5／5輪核准，M1P-01／02／03／04 均已納入，審查輪數已用完。完整介面與審查紀錄保留在 work/gofly-ios/research/m1-api-freeze.md、m1-advisor-ledger.md。

本輪只完成正式 App 的必要首次安裝依賴與最小 Mac 介面，不包含自動續簽、任意既有 App 更新、整套備份管理或重裝；M2／17 另有已核准方案，仍待 M1 完成才實作。開發不連接或列出手機，不簽署、安裝、下載、掛載或操作 Apple 帳號。

Mac 保留原 protocol1 唯讀邊界，正式首次安裝使用獨立 protocol2，固定 com.neven.gofly／GoFly。預檢只讀；明確開始才有寫入權限，描述檔更新預設不勾選。簽署產物綁定實際 Bundle、可執行檔及描述檔摘要、Team、裝置及有效期。既有正式 App 不由首次安裝覆寫。

單一私密 journal.json 同時保存目前交易與階段，operation.lock 序列化寫入；每次可能修改前先持久化意圖，檔案與父目錄同步。不以另一份 UI 指標或 UserDefaults 當交易權威。Mac 再開啟先讀本機交易身分，再由明確繼續核對原裝置；不自動新建交易繞過未決結果。

沒有持久化的「實際安裝成功」結果就保持不明。後來發現相同 App、摘要或 nonce 不能反推這次交易擁有它，不得啟動、終止、交付或重送安裝。配對候選在意圖提交後保留，未知時只核對原候選，不重新 pair-setup。既有配對 v1 仍是一筆獨立單次匯入；重送會把原成功回報改成拒絕，因此採固定完整續傳表，核對實際已保存的同機原始資料摘要來處理匯入／清理／回報間的中斷，不送第二份 input。

裝置準備按實際 OS 採 personalized 或 cryptex，先查實際掛載／安裝狀態，再依需要處理並重查；快取與檔案完整性不是準備成功。RSD 固定同一 USB 裝置、不自動配對或切換連線。必要支援檔由 Mac 放入不可混寫的 generation，bounded streaming hash；iOS 不下載，也不新增 FFI。

iOS 先建立資料 bootstrap，正常 Service／movement／stores／onboarding 延後一次建立並持有。沒有任何正式交接狀態時維持舊安裝及未簽署模擬器相容，不讀不存在的描述檔造摘要；有正式 request／input／activation 就必須核對真實當前 Bundle。nonce readback、實際配對資料及全部支援檔驗證完成，才原子提交同一份 active pointer＋receipt history。rename 後同步失敗是 commitUnknown，下次讀真實檔案；不宣稱回滾。舊完成交易重播不覆寫較新的 active generation。

Native resolver 只有「沒有正式 pointer」時能走舊 Documents/DDI；正式 pointer 損壞或不符就失敗，不混用舊資料。C06 只用當前 Bundle 綁定的實際提交資料顯示 Team／日期，未知如實呈現；不在每次畫面求值重算大檔摘要。資料提交不代表通道、native 健康、有效 GPS 或接收 App 成功，也不解除既有 cold hold。

Mac 必須同時取得正確已安裝 App readback、App 本地提交 receipt 及再次觀察到的同機支援狀態，才顯示 U18。首次流程不增加 LocalDevVPN 中間頁；手機仍走自己的必要 VPN 流程，沒有自動送點。

v3 僅調整開發順序：16 已凍結、已提交且已有完整 Core／重點 UI／雙 SDK／資源／雙軸審查證據，完整 60 項 UI 繼續對原 build18 執行。先並行開發不碰該產物的獨立 Core／Python／Mac；C 的 App／native 與新模擬器工作須等 16 完整回歸讀回，真實失敗優先修正。16 完整軟體驗證尚未標完成，不把部分 run 改稱全通過。

v5 延續相同完成門檻，另明確區分兩個提交：51b8fb8 是凍結的來源基準；尚待建立的 16 結案提交必須包含修正後測試、全部 60 個不同案例的完整證據與文件。16 回歸目前對獨立封存來源執行，因此已審查的 A 核心交回後，Root 可明確放行 C 的限定正式來源／資源修改。這不允許修改測試、專案、建置設定、封存來源或 DerivedData，也不允許 C 建置、執行 App、使用模擬器或宣稱完成；須等結案提交、完整讀回及明確交回模擬器後才另行放行。第一段只抽出既有正常 runtime，保持行為；新 bootstrap 行為仍待公開邊界失敗測試後實作。既有 UI 真實失敗由 Root 優先修正及協調整合。


2026-10-18 結案門檻讀回：16 的獨立結案提交 c44ab42 已完成，60 個不同 UI 案例成功覆蓋及原始失敗／修正來源由 Root 核對；Root 明確交回模擬器並放行 C 測試／建置。上文「尚待建立」保留原排程決策背景，不再是目前阻擋。M1 已完成軟體整合與雙軸審查；權限收緊、strict JSON 深度限制及跨端交接修正均有回歸驗證。完整結果與硬體限制見首次安裝票，手機仍未驗。

最終續接區分：完整原始 manifest、檔案清單及摘要在首次啟動前與 intent 同次持久化；formalPublished 只在遠端原檔核實後提交，未知 v1 交付僅查詢。OS wire 使用兩至三段數字版本，26.0–26.3 為 personalized，26.4 起及27為 cryptex。每次回報讀取、啟動與其他可能修改的邊界，仍需重新核對同機／OS／Developer Mode／信任；本地 journal 與舊觀察不替代這次核對。
