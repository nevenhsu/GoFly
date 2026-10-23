# GoFly for Mac

**2026-10-18 手機測試交付：** 正式安裝 producer 已在 iPhone 15 Pro／iOS 27.0.1 完成 GoFly build 22 安裝、本次配對匯入、裝置支援精確核對及 activation receipt；已開啟並確認正常 Welcome 畫面，使用者接手拔除 USB 測試。這是本機開發包的實機交付，不代表完整 Mac GUI、iOS 26 或定位效果已驗收。本機開發 bundle 不是發行用 DMG；私密證據保留於 `work/gofly-ios/device-test`。

使用者入口：[English](../../README.md) · [繁體中文](../../README.zh-Hant.md) · [简体中文](../../README.zh-Hans.md)。本文保留 Mac 開發現況與驗證說明；預定 DMG 發行／手機安裝流程及 [AI 操作說明](../../docs/AI-INSTALL.md) 均區分待實作與目前能力。授權範圍見 [LICENSING.md](../../docs/LICENSING.md)。

原生 SwiftUI macOS App，依 GoFly 的 Mac 線框製作。目前只保留正式 `com.neven.gofly` 的 USB 首次安裝、唯讀裝置檢查與環境檢查；可攜 DMG 仍在開發。

## 正式首次安裝

選取同一支 USB iPhone、10 碼 Team ID，以及本機固定 GoFly 專案或已簽署的 `GoFly.app`，先做唯讀檢查，再明確開始安裝。專案來源的「允許 Xcode 連線 Apple 更新開發簽署資料」預設關閉；勾選只授權本次操作。預檢不建立配對、不安裝 App、不下載支援資料。

開始後會將選項與裝置綁定在私密交易：驗證並固定 App、準備本次配對、安裝、按實際 OS 準備必要裝置支援，最後取得 iOS 的精確資料提交回報。只有安裝、本次配對匯入與新觀察的裝置支援均已確認，才顯示「Mac 安裝完成」並於 U18 結束。沒有 H12／U19 額外下載或中途 VPN 成功畫面，手機不自行下載支援檔案。VPN、GPS 與移動仍依 iPhone 內的正常流程確認。

最後的產品交接另以原 USB iPhone 的實際 App 查詢核對 LocalDevVPN 已安裝，再開放前往裝置管理；缺少或無法確認時保留核對入口，不重做已完成的安裝。正式 bundle ID `com.jkcoxson.LocalDevVPN` 已由 [Apple 公開 metadata](https://itunes.apple.com/lookup?id=6755608044&country=us) 核對，並非以名稱猜測。這個唯讀查詢不控制 VPN，也不代表 VPN 已連線。

重開 Mac App 會讀取原交易；「查詢原交易」不寫入裝置，「繼續原交易」保留同一裝置與選項。取消仍等待實際程序返回。交易建立前的預檢失敗可保留選項重試；一次性配對交付結果不明時僅顯示查詢，不能重送。若安裝結果遺失，即使後來看到同名 App，也維持待確認，不接管、不重送、不自動移除資料。首次安裝遇到既有 GoFly 會拒絕覆蓋。詳見 [M1 票](../../.scratch/gofly-ios/issues/M1-first-install.md)及 [bridge 契約](Bridge/PROTOCOL.md)。

本次實機修正已進入共用安裝來源：USB 連線保留裝置實際序號大小寫；配對檔保留依賴回傳的文字或二進位 remote unlock 欄位；iOS 26／27 程序控制走已核對身分的 RSD。Apple BuildManifest 的 4 MiB 上限、支援檔案總量的 4 GiB 上限與 256 KiB 交易 JSON 上限分開。Cryptex 優先使用本機 Xcode 支援資料，缺少才下載；實際版本取自受雜湊保護的 `Image.dmg.cryptex_info`，不拿 BuildManifest 的佔位版本比較。已執行中的 GoFly 回報 `app-running`，介面提示關閉手機 App 後繼續原交易，不強制停止或重裝。

## 重新簽名與實機測試更新（2026-10-22）

重新簽名／更新現在也走完整的配對核對、交付與必要裝置準備，手機精確回報後才完成；保留同一 App 的偏好、最愛及路線，不卸載。配對綁定選定 USB iPhone，身分不符或結果不明即停止。這條實作流程目前限 USB；VPN 及外部地圖定位分開驗收。

AI 實機測試一律使用 `bash scripts/install-ios-test.sh --device <UDID> --team <TEAM> --action preflight`，取得安裝授權後改 `--action apply`。已有 App 預設 renew；首次加 `--mode install`。未知寫入沿用輸出的 setupID 查詢／明確續行，不單獨用 devicectl 補裝。完整範例見 [AI 安裝說明](../../docs/AI-INSTALL.md)，可直接貼上的任務文字見 [iPhone 覆蓋安裝 prompt](../../docs/AI-INSTALL.md#ios-device-test-prompt)。

## 開啟

在專案根目錄執行：

```sh
bash app/GoFlyMac/build-app.sh
open work/gofly-mac/GoFly.app
```

需要 Xcode 與 macOS 15 以上。本機開發產物放在 `work/gofly-mac/GoFly.app`，未做發行簽署或 notarization。這個開發版綁定目前工作目錄與現有 `work/mac-setup-env/bin/python`，不是可攜式安裝包。缺少檢查環境時會顯示實際原因與處理入口，不會自行安裝依賴。

## 真實流程

真實環境檢查沿用唯讀 bridge 裝置邊界，僅利用既有信任。同機只列一次並預設 USB；同時觀察到 USB／Wi-Fi 時可明確選通道，檢查不偷偷改線。正式 `com.neven.gofly` 的安裝使用同一個 bridge 的 setup action，仍只限 USB；唯讀 action 不接受安裝。未讀到的簽名有效期或 VPN 資訊維持「待確認」，不以固定日期或按鈕點擊當成證據。

Mac App 不提供介面預覽，也不匯入已簽署的 GoFly.app；安裝只從本機 GoFly 專案建置。啟動時會逐步引導 Xcode、首次啟動、Apple 帳號與 Team 設定；Team 清單來自 Xcode，選擇後保存在本機。裝置管理只在使用者按下按鈕時 renew；選取裝置不會寫入。

建置腳本產生固定 `LocalConfiguration.json` 與 `SetupConfiguration.json`，綁定此工作目錄、既有 Python 與正式 GoFly 專案；生成的絕對路徑設定不追蹤進版控。實際程序入口只接受隨 Mac App 附帶的固定 Bridge 腳本與設定。沒有手機不等於環境檢查失敗；本輪開發不偵測或操作實體手機。

## 驗證

```sh
env DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  CLANG_MODULE_CACHE_PATH="$PWD/work/gofly-mac/module-cache" \
  swift test --disable-sandbox --package-path app/GoFlyMac \
  --scratch-path work/gofly-mac/build --cache-path work/gofly-mac/cache \
  --config-path work/gofly-mac/config --security-path work/gofly-mac/security

PYTHONDONTWRITEBYTECODE=1 work/mac-setup-env/bin/python -m unittest discover \
  -s app/GoFlyMac/Bridge
```

Mac Swift 與 Python 的實際數量以最後一次 `check.sh` 綠燈為準；不再逐輪記錄測試數。重建後 bundle 資源雜湊與 Setup 來源副本須一致，打包的唯讀 status 入口不呼叫裝置。這些離線結果不替代完整 GUI 或手機矩陣驗收。

設計：[GoFly Mac](https://www.figma.com/design/RtPV8PXCQJ2WXK3jk3kPrq/?node-id=21-46408)。首頁、裝置列表、安裝與手機交接均已讀取相應設計內容；本地素材在 `Sources/GoFlyMac/Resources`。視窗使用 macOS 原生標題列；唯讀限制與預覽標示是本版狀態。

介面使用 macOS 內建系統字體（中文交由系統選擇字形），支援系統深淺色。功能圖示採 SF Symbols，品牌圖形保留使用者提供的 GoFly 素材，沒有暫時素材 URL 留在執行程式中。詳見 [Mac UI 設計規格](../../docs/MAC-UI-DESIGN.md)。既有 LocalGo 裝置邊界沿用 AGPL-3.0，見 `../LocalGo/LICENSE`。
