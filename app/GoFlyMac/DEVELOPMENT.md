# Mac 裝置管理開發規格

只留已確認的產品需求與驗收條件。實機驗收由使用者最後集中執行，不以離線測試或既有唯讀結果代替。App 不提供介面預覽。

> **2026-10-26 設計更新（尚未實作）**：流程與驗收改以 [`docs/MAC-INSTALLER-SPEC.md`](../../docs/MAC-INSTALLER-SPEC.md) 為準，實作票在 `.scratch/gofly-mac-v1/`。第一版不做備份、還原、重置；中斷只「重新開始」不接續；延長簽名可用 USB 或 Wi‑Fi，剩不到 4 天自動執行。下方 2026-10-20 段落與接續規則待票 08、12 實作後改寫。

> **2026-10-20 已確認的新需求（已被 2026-10-26 取代）**：USB 中途斷線一律從頭重新安裝，不做接續；本文件中「重開只接續原交易」「resume 由使用者明確接續」「重開可查詢或接續」等規則待 Phase 0 實作後取代。首次安裝、更新、重置、備份、還原只限 USB，只有更新簽名支援 Wi‑Fi。另新增備份（最多 5 份、不分裝置）、還原、重置，以及「更新簽名」：版本一致時版本不變，不一致時先顯示確認步驟再覆蓋成 Mac 上的版本（仍走 renew）。計畫見 `work/gofly-planning/MAC-RESET-BACKUP-PLAN.md`，設計見 `docs/MAC-UI-DESIGN.md` 新版章節。

## Mac 環境引導

- 啟動順序：顯示「正在檢查 Mac 環境」→ 全部通過才進首頁；未通過時停在第一個失敗步驟，一次只顯示一個步驟。
- 步驟依序為：Xcode 安裝 → Xcode 元件／初次啟動 → Apple 開發者帳號 → Team 選擇 → Python、專案、裝置清單等開發檢查。
- Xcode 未安裝時提供「在 App Store 取得 Xcode」；Xcode 初次啟動未完成時提供「開啟 Xcode 安裝元件」。GoFly 不使用 sudo、不代替使用者執行 `-runFirstLaunch`、也不自動接受授權條款。
- 沒有 Apple 開發者帳號時顯示「請在 Xcode → Settings → Apple Accounts 按 + 登入」與「開啟 Xcode」。GoFly 不顯示 Apple ID 或密碼輸入框。
- Team 從 `com.apple.dt.Xcode` 的 `IDEProvisioningTeamByIdentifier` 讀取 `teamID`、`teamName`、`isFreeProvisioningTeam`。只有 1 個 Team 時自動選取；多個時顯示選單，標示「個人（免費，簽名 7 天）」或「團隊」。使用者明確選擇會存在 Mac App 本機設定，之後安裝與 renew 都使用同一個 Team。
- 每個步驟都有「重新檢查」；App 回到前景時自動重新檢查一次。
- 首頁顯示「Mac 環境」標籤，內含 Xcode 版本、Apple 帳號狀態、目前 Team 名稱與類型；點開可查看完整檢查並更換 Team。

## 首次安裝（USB）

- 安裝只從本機 GoFly 專案建置；不提供已簽署 App 匯入來源，也不顯示介面預覽。
- 首次安裝只保留 4 步：選擇 iPhone → 確認 → 安裝進度 → 完成。
- 使用者明確選取同一支 USB iPhone，確認頁使用 Mac 環境已選的 Team；按下開始後才建立私密交易與寫入權限。描述檔更新預設不勾選。
- 確認頁不顯示 Team ID 欄位或安裝來源，只顯示裝置名稱、iOS 版本、目前 Team 與「開始安裝」。進入確認頁時自動執行 preflight，不提供「唯讀檢查」按鈕。
- 有尚未完成的安裝交易時，確認頁顯示「繼續上次安裝」；查詢不會重新安裝。
- 完成頁顯示簽名到期日與手機上的下一步：開啟 LocalDevVPN，再開啟 GoFly。
- 交易固定正式 `com.neven.gofly`／`GoFly`、裝置、選項與本次配對，保存在單一私密 journal 與 `operation.lock`。每次可能修改前先持久化意圖。重開只接續原交易，不自動新建交易繞過未決結果。
- Mac 在同一交易中驗證產物、簽署、安裝、私密交付配對，並依實際 OS 準備必要裝置支援。已完成且仍有效的支援重用，不重複下載或掛載。
- 完成條件：App 部署、本次配對匯入、新觀察到的同機支援三者都確認，且取得 iOS 的 activation receipt，才顯示「Mac 安裝完成」（U18）。只看到 App 圖示、下載完成或檔案存在都不算完成。
- 結果不明就保持未知：不接管、不啟動、不終止、不重送，也不自動移除資料。取消仍等待實際程序返回。首次安裝不覆蓋既有 GoFly。
- 首次安裝 inspect 若確認這部 iPhone 已安裝 GoFly，顯示「此 iPhone 已安裝 GoFly，請到裝置管理重新簽名」，並提供前往該裝置頁的按鈕；不顯示通用安裝錯誤，也不因此自動開始 `renew`。
- setup 狀態查詢在沒有 journal 時回 `transaction-unknown`，必須視為「沒有待接續交易」，不得因此鎖住安裝頁或把首頁導向安裝頁。
- 狀態回報 `stage=complete`、`outcome=confirmed` 代表交易已完成，不得鎖住任何頁面或顯示續接；只有尚未完成的交易才顯示續接入口。舊 journal header 沒有 `mode` 時一律視為 `install`。
- 既有電腦上的 GoFly 執行中時回報 `app-running`，提示使用者關閉手機 App 後繼續上次安裝，不強制停止或重裝。
- 技術界線：Apple BuildManifest 讀取上限 4 MiB、支援檔總量 4 GiB、交易 JSON 256 KiB，分開計算。Cryptex 已安裝版本取自受雜湊保護的 `Image.dmg.cryptex_info` 的 `CFBundleVersion`，不以 BuildManifest 的 `Cryptex1,Version` 佔位值代替。
- iOS 在交接資料驗證並原子提交前不建立正常服務、任務或資料商店。提交不代表 VPN 已連線、GPS 已取得、clear 已完成或移動已授權。完成後可拔 USB；手機不另行下載支援資料，也不出現 U19 或 H12。


## 裝置管理重新簽名與更新

- 選取裝置只執行 inspect；不得因為選取或 inspect 就自動開始 renew。只有使用者在裝置頁按下按鈕才建立寫入交易。
- 裝置頁顯示手機上 GoFly 的版本與 build、Mac 專案從 `GoFly.xcconfig` 讀到的 `MARKETING_VERSION`／`CURRENT_PROJECT_VERSION`、簽名到期日與剩餘天數。
- 手機與專案的版本、build 都相同時，按鈕為「延長簽名期限」；Mac 專案較新時為「更新 GoFly」。兩者都走既有 `renew`（建置、簽名、覆蓋安裝、保留資料），不新增另一條只重新簽名的流程。
- `renew` 沿用 install 的同一個交易與 `operation.lock`；一次只能有一筆，結果不明時保留 `install=unknown`，不重送，resume 由使用者明確接續。
- 到期日必須讀取已簽署 App 的 `embedded.mobileprovision` `ExpirationDate`，不是 Developer Certificate 的 `NotAfter`。實際天數以 profile 為準，不假設免費 Team 一定 7 天；讀不到時為 null。
- 完成後顯示新的 `expiresAt`，並明確顯示「手機上的資料和設定已保留」。

## 環境錯誤與導覽

- 首頁與環境頁顯示實際失敗原因，至少區分「App 資源設定失敗（請重新執行 `build-app.sh`）」與「Python 環境無法使用」；不得只顯示「尚未就緒」。
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
| Xcode 未安裝／元件未完成 | 停在對應步驟，提供 App Store 或「開啟 Xcode 安裝元件」；不代跑 sudo、`-runFirstLaunch` 或接受授權 |
| 沒有 Apple 帳號 | 顯示 Xcode → Settings → Apple Accounts 登入說明與開啟 Xcode；不顯示 Apple ID／密碼欄位 |
| Team 選擇 | 1 個自動選取；多個顯示「個人（免費，簽名 7 天）」／「團隊」選單並保存本機設定 |
| App 回到前景 | 自動重新檢查 Mac 環境 |
| 沒有 setup journal | `transaction-unknown` 視為無待接續交易，首頁不被導向安裝頁 |
| 已完成 setup journal | `complete`＋`confirmed` 不鎖任何頁面；header 無 `mode` 視為 `install` |
| 選取裝置 | 只執行 inspect，不自動 renew、不寫入手機 |
| 裝置版本相同 | 顯示「延長簽名期限」，走既有 renew |
| Mac 專案較新 | 顯示「更新 GoFly」，走既有 renew 並保留資料 |
| 簽名到期日 | 取自 `embedded.mobileprovision` `ExpirationDate`；顯示剩餘天數，不以憑證到期日代替 |
| 已就緒的裝置支援 | 重用，不重複下載或掛載；下載成功但裝置驗證失敗仍不算完成 |
| 離線／測試 | 只驗程式與介面；不產生裝置寫入或完成證據 |
