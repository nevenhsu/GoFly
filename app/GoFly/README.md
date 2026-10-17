# GoFly iOS

正式 GoFly 的獨立 iOS 專案，部署目標 iOS 26，App bundle `com.neven.gofly`。現有 `../LocalGo` 是 prototype；本專案逐票實作及驗收，不直接繼承其完成度。

目前實作票 01：MapKit 地圖、服務啟動待命、停止／clear、恢復 GPS、GoFly 端 VPN 修復，以及三語與 Uber 風格的最小可操作主線。後續搜尋／路線／搖桿入口依各票接入，不提供假功能。

開啟 `GoFly.xcodeproj` 的 GoFly scheme。原生裝置庫只有 arm64 iPhone slice；模擬器可驗介面，裝置操作如實回報需要實機，不能用來驗證定位服務。

## 建置與檢查

從專案根目錄執行：

```sh
bash app/GoFly/scripts/check.sh
```

`check.sh` 把衍生輸出放到根目錄 `work/gofly-ios`，執行正式核心測試、固定來源的原生測試／重建、輸入雜湊核對與 unsigned simulator／device build，不簽署、不安裝到手機、不動 prototype。Xcode 預設使用 `/Applications/Xcode.app/Contents/Developer`，可由 `DEVELOPER_DIR` 指定。

首次原生建置需要 Apple Silicon、可用的固定 idevice 來源 checkout，以及下載 Rust 工具鏈與鎖定依賴的網路。來源位置、工具鏈隔離與建置步驟見 [NativeBridge](NativeBridge/README.md)。不使用 prototype 的舊 archive；缺少新產物或雜湊不符時，device 驗證直接失敗。

只檢查來源邊界可執行 `python3 app/GoFly/scripts/verify-native.py --source-only`；原生建置完成後，去掉此參數才會連同 archive 與建置 manifest 核對。來源檢查通過不能代替 device build 或真機驗收。

## 裝置準備與驗收界線

新 bundle 有獨立私有資料空間。Mac 的 target profile、配對交付及必要 DDI 準備須對準新 bundle，且在同機確認 App／配對／必要支援就緒後才宣告完成。原有 prototype 的安裝與配對不會自動出現在這個 App；手機端不下載 DDI。

建置、host 測試及模擬器畫面均不證明真機服務或接收 App 位置已正確。票 01 真機驗收需測已備妥裝置 Start 不送點、Stop／clear 三段結果、逾時後修復，以及拔 USB／停止 Mac 後的行為；未取得證據前狀態維持 verification-pending。

規格：[架構](ARCHITECTURE.md)、[視覺方向](../../DESIGN.md)、[開發步驟](../../work/gofly-planning/IOS-DEVELOPMENT-PLAN-DRAFT.md)。票單及進度位於根目錄 `.scratch/gofly-ios`。

## 來源

三個精確沿用的 StikDebug setup 來源及 AGPL-3.0 授權雜湊見 `NativeSources.json`。原生 idevice 採 MIT 授權，固定 upstream commit、鎖定依賴及 GoFly verify-only 修改見 `NativeBridge`；Swift 僅匯入經審查的窄 header。AGPL-3.0、idevice MIT 與來源註記隨 App 放入 Legal。完整傳遞依賴授權清單及裝置驗收仍待完成，本次不宣告已具發行資格。
