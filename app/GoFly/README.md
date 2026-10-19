# GoFly iOS

2026-10-18 VPN 回報修正：使用者拔 USB 後回報 build 22 在 LocalDevVPN Connected 時仍無法通過首次流程。已重現其 Network.framework waiting 提前失敗邏輯，修正為沿用成功 prototype 的等待語意及原兩秒期限；三語說明改為步驟卡、可達性狀態與首次流程可用的系統設定入口，沒有本機網路選項時不要求繼續尋找。離線測試與建置結果見 `work/gofly-ios/vpn-regression-20261018/RESULT.md`；手機仍是 build 22，修正版實際 VPN 連線待重新安裝後驗收。

2026-10-18 使用者要求先行手機測試：已用 `b2179d2` 程式快照加上缺少 transfer namespace 的唯讀啟動修正建置並安裝 build 22；iPhone 15 Pro／iOS 27.0.1 已完成正式 Mac producer 的配對匯入、支援核對與啟用回報，且正常顯示 Welcome。既有路徑仍執行完整 no-follow 檢查；只有明確不存在的 transfer namespace 可保持空白，避免首次啟動提前進入資料錯誤鎖定。使用者已接手拔 USB 測試，其他實機項目維持待驗。這次測試包不含之後仍在開發的管理功能；證據位於 `work/gofly-ios/device-test`。

2026-10-17 最新開發／驗收安排：依序持續完成全部實作與可離線驗證工作，期間不要求接 iPhone、不等待 USB、不安裝或操作手機。所有實機項目（含背景、跨端還原及全流程）最後才由使用者統一測試；前置票實作／自動驗證完成即可繼續，待實機不阻擋後續開發。實作完成與實機通過分開記錄，進度及集中驗收步驟見[本機票單](../../.scratch/gofly-ios/TRACKER.md)與[集中手機驗收](../../.scratch/gofly-ios/DEVICE-ACCEPTANCE.md)。此為執行安排更新，不宣告新增功能或實機結果。

正式 GoFly 的獨立 iOS 專案，部署目標 iOS 26，App bundle `com.neven.gofly`。現有 `../LocalGo` 是 prototype；本專案逐票實作及驗收，不直接繼承其完成度。

目前已依序完成票 01–16 的軟體實作與對應檢查，涵蓋地圖、搜尋、路線、搖桿、漫步、資料保留、背景資格與三語設定。硬體／接收 App 結果另行驗收，不由模擬器或 prototype 推定。正式 Mac 首次安裝與 iOS 資料交接（M1）已完成軟體實作與本機驗證；重裝還原（M2／17）及最終整合（18）接續開發。

開啟 `GoFly.xcodeproj` 的 GoFly scheme。原生裝置庫只有 arm64 iPhone slice；模擬器可驗介面，裝置操作如實回報需要實機，不能用來驗證定位服務。

## 建置與檢查

從專案根目錄執行：

```sh
bash app/GoFly/scripts/check.sh
```

`check.sh` 把衍生輸出放到根目錄 `work/gofly-ios`，預設執行核心測試與 unsigned simulator build，不簽署、不安裝到手機。加上 `--device` 才會重建原生程式庫、核對 native patch 與 Swift shim 宣告數，並執行 unsigned device build。Xcode 預設使用 `/Applications/Xcode.app/Contents/Developer`，可由 `DEVELOPER_DIR` 指定。

首次原生建置需要 Apple Silicon、可用的固定 idevice 來源 checkout，以及下載 Rust 工具鏈與鎖定依賴的網路。來源位置、工具鏈隔離與建置步驟見 [NativeBridge](NativeBridge/README.md)。原生 patch 或 shim 不符時，device 驗證直接失敗。

## 裝置準備與驗收界線

新 bundle 有獨立私有資料空間。Mac 的 target profile、配對交付及必要 DDI 準備須對準新 bundle，且在同機確認 App／配對／必要支援就緒後才宣告完成。原有 prototype 的安裝與配對不會自動出現在這個 App；手機端不下載 DDI。

建置、host 測試及模擬器畫面均不證明真機服務或接收 App 位置已正確。票 01 真機驗收需測已備妥裝置 Start 不送點、Stop／clear 三段結果、逾時後修復，以及拔 USB／停止 Mac 後的行為；未取得證據前狀態維持 verification-pending。

規格：[架構](ARCHITECTURE.md)、[視覺方向](../../DESIGN.md)、[開發步驟](../../work/gofly-planning/IOS-DEVELOPMENT-PLAN-DRAFT.md)。票單及進度位於根目錄 `.scratch/gofly-ios`。

## 來源

三個精確沿用的 StikDebug setup 來源及 AGPL-3.0 授權雜湊見 `NativeSources.json`。原生 idevice 採 MIT 授權，固定 upstream commit、鎖定依賴及 GoFly verify-only 修改見 `NativeBridge`；Swift 僅匯入經審查的窄 header。AGPL-3.0、idevice MIT 與來源註記隨 App 放入 Legal。完整傳遞依賴授權清單及裝置驗收仍待完成，本次不宣告已具發行資格。


## Mac 正式首次安裝與啟動交接（M1）

Mac 使用正式 `com.neven.gofly` 交易完成首次安裝、一次性配對匯入與必要裝置支援。iOS 首次啟動直接顯示 onboarding 歡迎頁，底部在「下一步」上方顯示 loading indicator；交接檢查完成前停用下一步，不建立正常服務、任務及資料商店。通過後才開放使用者按下一步，失敗或等待 Mac 時保留必要提示。沒有正式交接狀態仍可一般啟動，缺少／錯誤的正式資料不回退到舊支援。此介面更新尚未安裝至手機驗收。

交接資料不代表 VPN、GPS、clear 或移動已成功。正式 activation 存在時不再消耗無關的舊 v1 輸入；消耗本次 v1 時在實際解碼後核對交易 ID，不因相同配對 bytes 接受另一筆交易。設定頁以背景唯讀觀察的快取顯示配對狀態，畫面求值不讀配對檔。共享 v1 API 只增加可選交易核對，舊呼叫格式相容，沒有新增 native FFI 或重建原生程式庫。

M1 的最終軟體驗證與限制見[首次安裝票](../../.scratch/gofly-ios/issues/M1-first-install.md)；所有手機步驟見[集中驗收](../../.scratch/gofly-ios/DEVICE-ACCEPTANCE.md)。安裝完成不解除冷啟動待確認，也不自動送點；支援資料由 Mac 準備，手機不另行下載。
