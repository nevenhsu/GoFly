# LocalGo

自用 iOS 定位 App 開發版，目標 iPhone 15／iOS 27，部署目標 iOS 26。地圖介面與功能以 SwiftUI／MapKit 實作，裝置通道採 StikDebug／idevice 開源引擎並保留 AGPL-3.0 授權。

**不接入 AnyGo／iToolab 的登入、授權、配對下載或其他服務，也不使用其程式碼、素材、憑證或嵌入金鑰。** 研究樣本留在專案 `work/`，不納入 App。Apple 地圖／搜尋，以及使用者開始準備時下載的上游 DDI 仍需網路。

## 已實作

- 目前位置使用方向箭頭；已套用位置優先於手機讀取的位置，搖桿與路線方向會配合地圖旋轉顯示。
- 地圖選點、地址／經緯度搜尋，區分預覽選點與服務接受的位置；點圖保留縮放，上方顯示已接受的位置名稱或 GPS 座標。
- 原生霧白／墨綠介面，含深色模式、44 pt 圖示操作與簡潔設定；LocalDevVPN 按鈕可直接開啟 App，開啟失敗時轉到 App Store。
- 可收合的控制面板；未啟動時提供啟動及「恢復真實定位」。啟動後，模式列固定在面板最上方，只有瞬移顯示搜尋與儲存地點。頂端圖示控制啟動／停止；清除命令完成後回到啟動狀態，真實定位須由使用者在其他 App 確認。
- 單點瞬移；多點直線路線或 Apple 步行道路規劃。道路失敗時顯示失敗，由使用者明確選擇直線。
- 路線開始、暫停、手動繼續、往返；速度 2–100 km/h、步進 1，預設 20 km/h，快捷 5／20／60。
- 搖桿方向與速度；放開停止送點，按停止要求清除模擬位置。
- GPX 1.1 匯入／匯出；上限 2 MiB／10,000 點，驗證座標、拒絕 DTD／外部實體。
- 本機收藏與歷史各最多 100 筆、個別刪除；私有儲存、原子替換與檔案保護。
- 真實裝置命令 adapter、UDID 綁定、DDI 準備；單一命令排程與過期回覆防護。正式 App 不使用假定位引擎。

切到背景時暫停路線、停止搖桿送點，保留最後送出的位置；返回後需手動繼續。停止會取消排程並要求清除。清除失敗維持「未知」，不能把關閉 App、刪配對或停 VPN 當作定位已恢復。

更新或重新開啟 App 後仍可按「恢復真實定位」，不必先啟動或設定新位置。清除要求已完成但位置仍未恢復時，可再次送出清除；正在進行中的要求只執行一次。開發者服務回傳成功不代表實際座標已恢復，介面不再顯示「已確認清除」。本次使用者回報多個 App 仍是錯誤位置，實際恢復尚未驗收。

裝置身分驗證使用定位專用通道，平常重用，傳輸失敗時重建一次；啟動的開發映像檢查也改用獨立通道，避免舊通道阻擋停止與重新啟動。本機端點無法連通時，即使 LocalDevVPN 顯示 Connected，仍可在該 App Disconnect 再 Connect，回來重試停止；確認清除後才重新啟動。使用者回報本次切回 4G 後自行恢復；這不代表新版本已驗證。此修正已補上模擬通道失效的回歸測試，更新後的鎖屏及 Wi-Fi／4G 切換仍待實機驗收。

## 尚未完成的驗收

已在使用者的 iPhone／iOS 27.0.1 完成自有 RP 配對、Personal Team 簽署安裝與私密 USB 交付；App 已回報本次交易匯入成功。使用者也確認手機端裝置身分與 DDI 核對成功。使用者已確認斷開 USB 後，兩個其他 App 都收到選定位置。使用者也已確認停止清除後恢復真實位置；iOS 26 尚未實測。

[Mac 首次設定工具](MacSetup/README.md) 已實作自動選擇唯一 USB iPhone／Personal Team、簽署、建立及驗證自有 RP、安裝、私密交付與手機回報。使用者已接受另裝 LocalDevVPN，手機透過它運作；不再要求自行搬配對檔。前景會檢查本機通道，通道不可達時顯示開啟 LocalDevVPN 的提示，恢復連通後自動收起。這項檢查不代表能讀取另一個 App 的 VPN 開關，啟動仍會驗證配對及裝置身分。背景持續移動、重啟後恢復、所有 App 相容性、遊戲助手與雲端同步仍未交付。簽署及配對有效期依 Apple／裝置狀態，需要時可重跑設定工具，不承諾永久免續簽。

完整能力對照見 [PRODUCT-SPEC.md](PRODUCT-SPEC.md)。AnyGo 靜態研究見專案 `work/anygo-installed-ios/SPEC.md` 與 `work/anygo-mac-installer/FLOW.md`；不能將研究線索當作自用 App 的實機成功證據。

## 建置與測試

需已接受條款的 Xcode 27；首次解析套件需網路。從研究專案根目錄執行：

```sh
env DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -project app/LocalGo/StikDebug.xcodeproj -scheme StikDebug \
  -configuration Debug -destination 'generic/platform=iOS' -sdk iphoneos \
  -derivedDataPath work/localgo-derived \
  -clonedSourcePackagesDirPath work/localgo-packages \
  -onlyUsePackageVersionsFromResolvedFile \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY= \
  ARCHS=arm64 build
```

產物：`work/localgo-derived/Build/Products/Debug-iphoneos/StikDebug.app`，顯示名稱 LocalGo。這條命令產生未簽署產物，不能直接安裝。實際首次安裝請使用 [MacSetup](MacSetup/README.md) 的 `setup --execute` 流程；本次已用使用者的 Personal Team 完成開發簽署與指定裝置安裝，未發布。

```sh
env DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  swift test --package-path app/LocalGo --scratch-path work/localgo-swift-tests

bash app/LocalGo/Tests/NativeRecovery/run.sh
```

受限 SwiftPM 環境可另設模組快取；最新首次設定驗證在 `work/mac-first-setup/`：48 項 Swift 核心測試、26 項 Mac 測試，以及實機安裝／匯入紀錄。測試假引擎僅用於宿主的命令與排程驗證，不代表實機通道已成功。

## 裝置設定與待驗收情境

1. 開發者模式已啟用；在 Mac 執行 [首次設定工具](MacSetup/README.md)，由自己的 USB 裝置產生自有 RP。
2. 目前通道需另裝並啟用 [LocalDevVPN](https://apps.apple.com/us/app/localdevvpn/id6755608044)，使用預設本機位址 `10.7.0.1`。
3. Mac 自動簽署、安裝並交付配對，收到匯入回報後，在 LocalGo 按「啟動」。手動匯入保留作為進階修復選項。
4. 斷開 USB、停止 Mac 連線工具，從 LocalGo 套用位置；在 Apple 地圖與另一個 App 重新取得位置。服務 ACK 只代表接受命令。
5. 分別驗證瞬移、路線、搖桿、切換 App 後保留最後位置，以及停止後恢復真實定位。
6. 在 iOS 26、27 各自測試鎖屏、VPN／網路中斷、重啟及重新準備。未通過前不能宣稱相容或持續有效。

配對存於私有 Application Support/Pairing，目錄 0700、檔案 0600、首次解鎖後可讀、排除備份，含 1 MiB 上限與內容／身分檢查。無配對分享、Documents 鏡像或識別碼診斷。開啟 App 不會自動開始模擬定位或下載開發元件；前景只檢查本機通道。按「回到目前位置」時才詢問使用期間定位權限，已允許時前景顯示手機位置；不要求背景定位或背景音訊權限，也不儲存或記錄手機定位。

來源及限制見 [UPSTREAM.md](UPSTREAM.md)，授權見 [LICENSE](LICENSE)。
