# GoFly for Mac

原生 SwiftUI macOS app，依 GoFly 的 Mac 線框製作。目前交付範圍是 **介面與唯讀檢查**。不安裝手機 App，不簽署、不建立或交付配對、不重新安裝，也不備份／刪除手機資料；既有 iOS 程式沒有變更。

## 開啟

在專案根目錄執行：

```sh
bash app/GoFlyMac/build-app.sh
open work/gofly-mac/GoFly.app
```

需要 Xcode 與 macOS 15 以上。本機開發產物放在 `work/gofly-mac/GoFly.app`，未做發行簽署或 notarization。這個開發版綁定目前工作目錄與現有 `work/mac-setup-env/bin/python`，不是可攜式安裝包。缺少檢查環境時仍可開啟介面預覽；不會自行安裝依賴。

## 兩種模式

- **唯讀檢查**：啟動後檢查 Xcode、必要元件、既有 Python 工具與裝置偵測介面。通過後可查看 USB 首次安裝介面、USB／Wi-Fi 裝置管理與指定手機的身分、開發者模式及可讀取的 App 安裝資訊。沒有手機不等於環境失敗；裝置偵測服務無法讀取時會顯示失敗原因。
- **介面預覽**：右上模式選單或首頁「預覽操作流程」進入。全部使用示意資料，頁面上持續顯示預覽標示。可操作首次安裝 → LocalDevVPN → 手機交接、裝置管理、續簽、連接修復、保留資料重裝與備份管理。可切換環境未就緒、沒有裝置、等待信任、開發者模式關閉、簽名過期與裝置中斷等情境。

真實檢查只利用既有信任，不自動配對。相同裝置以 USB 優先去重；首次安裝介面排除 Wi-Fi 裝置。切換裝置、取消或檢查失敗會作廢先前的檢查證據，不自動重試或沿用舊成功狀態。安裝、續簽、配對修復與重裝操作在唯讀模式停用，Python 邊界也拒絕寫入要求。

沒有讀到的資料會顯示「待確認」。例如現有讀取介面未提供可驗證的簽名有效期及 LocalDevVPN bundle ID，因此不會根據過往紀錄、固定日期或使用者按下按鈕來宣告有效或已安裝。預覽日期只存在預覽後端。

## 之後銜接正式 iOS app

`GoFlyMacCore` 定義裝置狀態與唯讀檢查契約，`ProcessBridge` 執行隨 app 附帶的 `Bridge/bridge.py`，SwiftUI 頁面只使用這個邊界。目標 App 名稱、bundle ID、專案與本機 runtime 在建置時寫入 `LocalConfiguration.json`，不追蹤生成的絕對路徑設定。

目前 profile 指向既有 `com.neven.localgo`，用途只有讀取安裝資訊。正式 iOS app 確定後，更新 profile 與橋接 adapter，再加入明確的寫入交易協定；不需要重做 Mac 導覽。安裝回報、選擇性備份／匯入、簽名相容性與資料還原仍需正式實作與實機驗證；目前預覽不代表這些能力已完成。

橋接格式與邊界見 [Bridge/PROTOCOL.md](Bridge/PROTOCOL.md)。隨 app 只複製既有 `localgo_device.py` 作為唯讀依賴邊界，不包含舊的安裝 CLI；保留來源授權。

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

Swift 測試涵蓋環境門檻、USB 去重、裝置身分核對、過期／錯誤回覆、取消與程序逾時、過量輸出、預覽／真實隔離。Python 測試核對唯讀 allowlist、既有 venv、非配對式身分檢查及依賴失敗。測試假資料不代表真機驗收。

設計：[GoFly Mac](https://www.figma.com/design/RtPV8PXCQJ2WXK3jk3kPrq/?node-id=21-46408)。首頁、裝置列表、安裝、裝置管理、修復、保留資料與手機交接均已讀取相應設計內容；本地素材在 `Sources/GoFlyMac/Resources`。視窗使用 macOS 原生標題列；唯讀限制與預覽標示是本版新增狀態。

字體使用 [Google Fonts 的 Noto Sans TC](https://github.com/google/fonts/tree/main/ofl/notosanstc)，保留 `NotoSansTC-OFL.txt`。圖示來自使用者提供的 GoFly Figma，沒有暫時素材 URL 留在執行程式中。既有 LocalGo 裝置邊界沿用 AGPL-3.0，見 `../LocalGo/LICENSE`。
