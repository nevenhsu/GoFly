# GoFly for Mac V1 實機與乾淨 Mac 驗收

狀態：待使用者操作。這份清單記錄實際 Mac／iPhone 行為，與離線測試及 UI capture fixture 分開。乾淨 Mac／其他帳號的本地 DMG 步驟見 `work/gofly-mac/v1/DMG-VERIFY.md`；執行前記錄 Mac 型號／macOS、Xcode 版本、GoFly Mac 版本、iPhone 機型／iOS、Team 類型、連線方式及操作日期。不要把配對資料、憑證、完整 UDID 或原始裝置日誌貼入聊天或版本控制。

## A. 乾淨 Mac／DMG 安裝

- [ ] 在乾淨 Mac 或另一個 macOS 使用者帳號取得 DMG 與同一版本的 `.sha256`，依 `work/gofly-mac/v1/DMG-VERIFY.md` 確認 `shasum -a 256 -c` 顯示 `OK`，並執行安裝與首次開啟驗收。
- [ ] 依 README 的 Terminal 步驟執行 DMG 內 `install.sh`；確認只安裝 `/Applications/GoFly.app`，替換既有 App 前會先詢問，並且不改 GoFly state 或手機資料。
- [ ] 確認移除隔離屬性後 App 可開啟，內建 arm64 Python、`cffi`／`cryptography` 原生擴充及 Bridge 可執行；本機隔離模擬結果不能代替此乾淨帳號／Mac 測試。
- [ ] 完成 E00–E09 環境檢查；確認全新 Mac 會導向第一個未完成步驟、未知觀察不會顯示通過，並判定 E06 iOS platform 是否確實需要。

## B. USB 首次安裝

- [ ] 由使用者在 iPhone 完成解鎖、信任這部 Mac、Developer Mode 及系統提示；Mac 只明確選取測試手機與 Xcode Team。
- [ ] 透過 USB 執行首次安裝。分別核對 Team-scoped Bundle ID、iPhone App 部署、本次 pairing 匯入、必要裝置支援與 iPhone activation receipt。
- [ ] 只有以上證據都讀回後才顯示完成；記錄完成頁實際顯示的簽名期限。另行驗證 iPhone 的 LocalDevVPN／GoFly 流程，不把安裝成功當作 VPN 或定位驗收。

## C. Wi-Fi 延長簽名

- [ ] 使用已透過 USB 配對的測試 iPhone；讓 Mac 與手機在同一網路並解鎖手機，確認 GoFly 選中 Wi-Fi transport。
- [ ] 執行 renew，觀察 Bridge 只核對既有 pairing、不產生新的 pairing；分別核對覆蓋安裝（保留資料）、裝置支援與 activation receipt。
- [ ] 驗證手機找不到、既有 pairing 不符或網路中斷時不顯示成功，並提供改用 USB 或 D14 重新開始入口。

## D. 自動延長簽名

- [ ] 在簽名剩不到 4 天（含已過期）、裝置已安裝、網路可用、沒有其他操作且該裝置自動開關開啟時，確認 App 啟動檢查可開始 D10；USB 與 Wi-Fi 同時可用時優先 USB。
- [ ] 確認 macOS 通知、D10 連線／睡眠警告與執行期間防睡眠行為；只有 activation receipt 回報後才顯示 D11 新期限與資料保留狀態。
- [ ] 驗證失敗後不立即重試，下一次 24 小時檢查才重新嘗試；關閉該裝置開關或剩餘時間達 4 天時不觸發。
- [ ] 記錄 macOS 通知授權狀態、電源／睡眠觀察與實際時間；單元測試的可注入時鐘不算 macOS scheduler 驗收。

## E. 中斷後重新開始

- [ ] 在核准的測試裝置與安全時機觀察一次取消或中斷後的 D14；不要為了測試移除 App、刪 pairing、receipt、GoFly state 或其他使用者資料。
- [ ] 從 D14 選「重新開始」，確認產生新 setupID、先重新觀察手機，再從唯讀 preflight 開始；沒有 resume／continue 入口。
- [ ] USB 重新開始使用新產生的 pairing；Wi-Fi 重新開始只驗證既有 pairing。舊交易與活動配對資料應按規格保留，狀態不明時 fail closed。

## F. 過期 renew 與資料保留

- [ ] 使用有既有測試資料的 iPhone App，在簽名到期後確認 GoFly 暫時不能開啟但資料仍在；由 Mac renew 同一 Team-scoped App。
- [ ] renew 完成後再次開啟 iPhone App，逐項核對偏好、最愛與路線仍保留；記錄實際 receipt 與新期限。不要卸載或清除 App 資料。

## G. 免費 Personal Team capability

- [ ] 使用使用者自己的免費 Personal Team 執行 Xcode 簽名，確認 V1 所需 capability／背景處理設定可以建立與啟動；記錄 Xcode 實際錯誤或成功結果。
- [ ] 實際觀察免費簽名到期、七天 renew 與該 Team 可用的 App ID／裝置限制。這些限制不得以文件推測代替測試結果。

## 結果紀錄

每項回報：通過／失敗／未執行、裝置與軟體版本（敏感識別碼遮蔽）、連線方式、實際可見狀態、可安全分享的截圖位置，以及未驗證事項。取消或結果未知時保留手機與交易資料，先依 app 畫面核對同一裝置與交易再決定後續操作。
