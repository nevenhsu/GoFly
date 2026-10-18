# GoFly for Mac

**M1 軟體完成、手機待驗：** 正式 GoFly 首次安裝、私密交易紀錄及明確繼續流程已完成本機實作、檢查與雙軸審查。驗證與限制見 [首次安裝票](../../.scratch/gofly-ios/issues/M1-first-install.md)及[決策](../../.scratch/gofly-ios/decisions/M1-first-install.md)。開發期間不要求連接 iPhone，全部軟體完成後才集中實機驗收；本機開發 bundle 不是發行用 DMG。

使用者入口：[English](../../README.md) · [繁體中文](../../README.zh-Hant.md) · [简体中文](../../README.zh-Hans.md)。本文保留 Mac 開發現況與驗證說明；預定 DMG 發行／手機安裝流程及 [AI 操作說明](../../docs/AI-INSTALL.md) 均區分待實作與目前能力。授權範圍見 [LICENSING.md](../../docs/LICENSING.md)。

原生 SwiftUI macOS App，依 GoFly 的 Mac 線框製作。M1 已實作正式 `com.neven.gofly` 首次安裝；裝置管理、重新簽名、重裝與備份頁的預覽不代表這些功能已交付。自動續簽與 Wi-Fi 重裝仍不在 M1 範圍。

## 正式首次安裝（M1）

選取同一支 USB iPhone、10 碼 Team ID，以及本機固定 GoFly 專案或已簽署的 `GoFly.app`，先做唯讀檢查，再明確開始安裝。專案來源的「允許 Xcode 連線 Apple 更新開發簽署資料」預設關閉；勾選只授權本次操作。預檢不建立配對、不安裝 App、不下載支援資料。

開始後會將選項與裝置綁定在私密交易：驗證並固定 App、準備本次配對、安裝、按實際 OS 準備必要裝置支援，最後取得 iOS 的精確資料提交回報。只有安裝、本次配對匯入與新觀察的裝置支援均已確認，才顯示「Mac 安裝完成」並於 U18 結束。沒有 H12／U19 額外下載或中途 VPN 成功畫面，手機不自行下載支援檔案。VPN、GPS 與移動仍依 iPhone 內的正常流程確認。

重開 Mac App 會讀取原交易；「查詢原交易」不寫入裝置，「繼續原交易」保留同一裝置與選項。取消仍等待實際程序返回。交易建立前的預檢失敗可保留選項重試；一次性配對交付結果不明時僅顯示查詢，不能重送。若安裝結果遺失，即使後來看到同名 App，也維持待確認，不接管、不重送、不自動移除資料。首次安裝遇到既有 GoFly 會拒絕覆蓋。詳見 [M1 票](../../.scratch/gofly-ios/issues/M1-first-install.md)及 [protocol 2](Bridge/Setup/README.md)。

## 開啟

在專案根目錄執行：

```sh
bash app/GoFlyMac/build-app.sh
open work/gofly-mac/GoFly.app
```

需要 Xcode 與 macOS 15 以上。本機開發產物放在 `work/gofly-mac/GoFly.app`，未做發行簽署或 notarization。這個開發版綁定目前工作目錄與現有 `work/mac-setup-env/bin/python`，不是可攜式安裝包。缺少檢查環境時仍可開啟介面預覽；不會自行安裝依賴。

## 真實流程與預覽

真實環境檢查沿用 protocol 1 的唯讀裝置邊界，僅利用既有信任，優先選取 USB 並去重。正式 `com.neven.gofly` 的安裝使用分離的 protocol 2；protocol 1 仍拒絕安裝請求。未讀到的簽名有效期或 VPN 資訊維持「待確認」，不以固定日期或按鈕點擊當成證據。

介面預覽持續顯示預覽標示，使用示意裝置與日期，可討論安裝、管理、續簽、修復、保留資料等畫面；預覽資料不會成為真實交易成功證據。正式尚未實作的操作維持停用。

建置腳本產生固定 `LocalConfiguration.json` 與 `SetupConfiguration.json`，綁定此工作目錄、既有 Python 與正式 GoFly 專案；生成的絕對路徑設定不追蹤進版控。實際程序入口只接受隨 Mac App 附帶的固定 Bridge 腳本與設定。沒有手機不等於環境檢查失敗；本輪開發不偵測或操作實體手機。

## 驗證

```sh
env DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  CLANG_MODULE_CACHE_PATH="$PWD/work/gofly-mac/module-cache" \
  swift test --disable-sandbox --package-path app/GoFlyMac \
  --scratch-path work/gofly-mac/build --cache-path work/gofly-mac/cache \
  --config-path work/gofly-mac/config --security-path work/gofly-mac/security

PYTHONDONTWRITEBYTECODE=1 work/mac-setup-env/bin/python -m unittest discover \
  -s app/GoFlyMac/Bridge/Tests

PYTHONDONTWRITEBYTECODE=1 work/mac-setup-env/bin/python -m unittest discover \
  -s app/LocalGo/MacSetup/Tests
```

M1 的 Mac Swift 37 項通過，最終 Python 交易／支援檢查數量見 M1 票。Swift 測試涵蓋環境門檻、USB 去重、裝置身分核對、過期／錯誤回覆、取消與程序逾時、過量輸出、預覽／真實隔離。Python 測試核對唯讀 allowlist、既有 venv、非配對式身分檢查及依賴失敗。測試假資料不代表真機驗收。

設計：[GoFly Mac](https://www.figma.com/design/RtPV8PXCQJ2WXK3jk3kPrq/?node-id=21-46408)。首頁、裝置列表、安裝、裝置管理、修復、保留資料與手機交接均已讀取相應設計內容；本地素材在 `Sources/GoFlyMac/Resources`。視窗使用 macOS 原生標題列；唯讀限制與預覽標示是本版新增狀態。

字體使用 [Google Fonts 的 Noto Sans TC](https://github.com/google/fonts/tree/main/ofl/notosanstc)，保留 `NotoSansTC-OFL.txt`。圖示來自使用者提供的 GoFly Figma，沒有暫時素材 URL 留在執行程式中。既有 LocalGo 裝置邊界沿用 AGPL-3.0，見 `../LocalGo/LICENSE`。
