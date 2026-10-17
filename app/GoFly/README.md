# GoFly iOS

正式 GoFly 的獨立 iOS 專案，部署目標 iOS 26，App bundle `com.neven.gofly`。現有 `../LocalGo` 是 prototype；本專案逐票實作及驗收，不直接繼承其完成度。

目前實作票 01：MapKit 地圖、服務啟動待命、停止／clear、恢復 GPS、GoFly 端 VPN 修復，以及三語與 Uber 風格的最小可操作主線。後續搜尋／路線／搖桿入口依各票接入，不提供假功能。

開啟 `GoFly.xcodeproj` 的 GoFly scheme。原生裝置庫只有 arm64 iPhone slice；模擬器可驗介面，裝置操作如實回報需要實機，不能用來驗證定位服務。

## 建置與檢查

從專案根目錄執行：

```sh
python3 app/GoFly/scripts/verify-native.py
bash app/GoFly/scripts/check.sh
```

`check.sh` 把衍生輸出放到根目錄 `work/gofly-ios`，執行正式核心測試與 unsigned simulator／device build，不簽署、不安裝到手機、不動 prototype。Xcode 預設使用 `/Applications/Xcode.app/Contents/Developer`，可由 `DEVELOPER_DIR` 指定。

## 裝置準備與驗收界線

新 bundle 有獨立私有資料空間。Mac 的 target profile、配對交付及必要 DDI 準備須對準新 bundle，且在同機確認 App／配對／必要支援就緒後才宣告完成。原有 prototype 的安裝與配對不會自動出現在這個 App；手機端不下載 DDI。

建置、host 測試及模擬器畫面均不證明真機服務或接收 App 位置已正確。票 01 真機驗收需測已備妥裝置 Start 不送點、Stop／clear 三段結果、逾時後修復，以及拔 USB／停止 Mac 後的行為；未取得證據前狀態維持 verification-pending。

規格：[架構](ARCHITECTURE.md)、[視覺方向](../../DESIGN.md)、[開發步驟](../../work/gofly-planning/IOS-DEVELOPMENT-PLAN-DRAFT.md)。票單及進度位於根目錄 `.scratch/gofly-ios`。

## 來源

連結的 idevice header／archive 及三個精確沿用的 setup 來源，見 `NativeSources.json`。保留 StikDebug／idevice 的來源註記與 AGPL-3.0，授權全文隨 App 放入 Legal。原生 archive 的生成 commit 與全部傳遞授權尚未獨立重現；本次不宣告已具發行資格。
