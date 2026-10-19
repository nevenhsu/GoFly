# Mac 裝置管理開發規格

只留已確認的產品需求與驗收條件。實機驗收由使用者最後集中執行，不以預覽、離線測試或既有唯讀結果代替。

## 首次安裝（USB）

- 使用者明確選取同一支 USB iPhone 與 10 碼 Team ID，先做唯讀檢查；按下開始後才建立私密交易與寫入權限。描述檔更新預設不勾選。
- Team ID 預設採用環境檢查的 `environment.teamID`，以唯讀文字顯示「Xcode 開發團隊：<Team ID>」；只有偵測不到時才顯示 10 碼輸入框，並提示「Xcode → Settings → Accounts 可以查看」。目前不做多 Team 選單。
- 交易固定正式 `com.neven.gofly`／`GoFly`、裝置、選項與本次配對，保存在單一私密 journal 與 `operation.lock`。每次可能修改前先持久化意圖。重開只接續原交易，不自動新建交易繞過未決結果。
- Mac 在同一交易中驗證產物、簽署、安裝、私密交付配對，並依實際 OS 準備必要裝置支援。已完成且仍有效的支援重用，不重複下載或掛載。
- 完成條件：App 部署、本次配對匯入、新觀察到的同機支援三者都確認，且取得 iOS 的 activation receipt，才顯示「Mac 安裝完成」（U18）。只看到 App 圖示、下載完成或檔案存在都不算完成。
- 結果不明就保持未知：不接管、不啟動、不終止、不重送，也不自動移除資料。取消仍等待實際程序返回。首次安裝不覆蓋既有 GoFly。
- 首次安裝 inspect 若確認這部 iPhone 已安裝 GoFly，顯示「此 iPhone 已安裝 GoFly，請到裝置管理重新簽名」，並提供前往該裝置頁的按鈕；不顯示通用安裝錯誤，也不因此自動開始 `renew`。
- setup 狀態查詢在沒有 journal 時回 `transaction-unknown`，必須視為「沒有待接續交易」，不得因此鎖住安裝頁或把首頁導向安裝頁。
- 狀態回報 `stage=complete`、`outcome=confirmed` 代表交易已完成，不得鎖住任何頁面或顯示續接；只有尚未完成的交易才顯示續接入口。舊 journal header 沒有 `mode` 時一律視為 `install`。
- 既有電腦上的 GoFly 執行中時回報 `app-running`，提示使用者關閉手機 App 後繼續原交易，不強制停止或重裝。
- 技術界線：Apple BuildManifest 讀取上限 4 MiB、支援檔總量 4 GiB、交易 JSON 256 KiB，分開計算。Cryptex 已安裝版本取自受雜湊保護的 `Image.dmg.cryptex_info` 的 `CFBundleVersion`，不以 BuildManifest 的 `Cryptex1,Version` 佔位值代替。
- iOS 在交接資料驗證並原子提交前不建立正常服務、任務或資料商店。提交不代表 VPN 已連線、GPS 已取得、clear 已完成或移動已授權。完成後可拔 USB；手機不另行下載支援資料，也不出現 U19 或 H12。


## 連線成功後自動重新簽名

在裝置管理明確選取裝置並成功完成 inspect、且確認已安裝 GoFly 時，自動開始一次 setup 的 `renew`。`renew` 以相同 Bundle ID 覆蓋安裝，保留 App 資料，不先移除 App。preflight 要求裝置上已有 GoFly，缺少時回 `app-not-installed`；GoFly 執行中沿用 `app-running` 提示。

- 同一次選取最多自動觸發一次；刷新裝置清單、重新 inspect、返回裝置頁都不再觸發。
- 一次只能有一筆 setup／renew；自動與手動入口共用同一個 `operation.lock` 與進度。
- 結果不明時保留 `install=unknown`，不重送、不推定成功；resume 由使用者明確接續。
- 完成後顯示可驗證的 `expiresAt`；讀不到 provisioning profile 的到期日時為 null，不自估。

## 保留手動重新簽名流程

裝置頁在已安裝 GoFly 時顯示「重新簽名」。按下後沿用 Setup 頁的表單、進度與結果元件，不新增頁面或 model；已有 renew 在執行時顯示同一筆進度，不另開交易。手動流程與自動觸發走同一個 `mode: "renew"` 路徑，只更新簽章與安裝結果，不重做配對、支援或 handoff，也不清除 App 資料。

## 環境錯誤與導覽

- 首頁與環境頁顯示實際失敗原因，至少區分「Bundle 驗證失敗（請重新執行 `build-app.sh`）」與「Python 環境無法使用」；不得只顯示「尚未就緒」。
- 環境未就緒或 setup journal 阻塞時，「首頁」「查看 Mac 環境」「返回裝置清單」等純導覽入口仍可使用；只有會執行檢查、安裝或 renew 的操作才受 readiness 與操作鎖限制。
- 首次安裝遇到已安裝 GoFly 時，前往裝置頁只是導覽，不會自動 inspect、apply 或 resume。

## DMG 發行

正式交付入口是下載 Mac DMG → 開啟 GoFly → USB 連接 iPhone → 由 Mac 安裝 iPhone App。DMG 內 App 不得依賴開發者工作目錄絕對路徑；所需 runtime／工具須隨包提供或由 App 明確引導設定。

發行資料須提供下載入口、版本、Mac 架構、最低系統、校驗碼與簽署／notarization 狀態。驗收須在未使用本工作目錄的 Mac，從下載 DMG 開始，完成環境檢查、Apple 帳號確認、USB 裝置核對、首次安裝、配對與必要裝置準備，再到 iPhone VPN 通道可用。

授權方向為自有內容 0BSD；既有 AGPL／GPL／OFL 及其他依賴授權保留，發行前須完成精確依賴與權利範圍確認，不得宣稱整包免署名。文件見[三語 README](../../README.md)、[AI 操作說明](../../docs/AI-INSTALL.md)、[授權範圍](../../docs/LICENSING.md)。

## 開發驗收條件

| 情境 | 預期結果 |
| --- | --- |
| 首次安裝完成 | App 部署、配對匯入、同機支援與 activation receipt 均確認；拔 USB 後手機可正常開啟 GoFly |
| 首次安裝中斷 | 原交易保留；結果不明不重送、不接管；重開可查詢或接續 |
| 既有 GoFly 已安裝 | 首次安裝顯示「請到裝置管理重新簽名」與前往該裝置頁的按鈕；不接管或移除既有 App |
| 環境／bridge 無法使用 | 首頁與環境頁顯示 Bundle 或 Python 原因；首頁與返回裝置清單導覽仍可用 |
| 沒有 setup journal | `transaction-unknown` 視為無待接續交易，首頁不被導向安裝頁 |
| 已完成 setup journal | `complete`＋`confirmed` 不鎖任何頁面；header 無 `mode` 視為 `install` |
| 已就緒的裝置支援 | 重用，不重複下載或掛載；下載成功但裝置驗證失敗仍不算完成 |
| 模擬器／預覽 | 只驗介面，不產生裝置寫入或完成證據 |
