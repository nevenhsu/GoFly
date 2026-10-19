# 來源與可重現性

- 上游：[StikDebug](https://github.com/StikDebug/StikDebug)，commit `734361bb9d03817ed8dd82cb27cf8b2b3792b458`。
- 上游原樣保存在研究專案 `tools/StikDebug`；完整 git archive 在 `work/localgo-upstream-734361bb.tar`，SHA-256 `c81e961cfd0e8f1e374167d6ed3d9cb3a91896e5848360f0b839f8e7fa318f8a`。
- 保留 AGPL-3.0 [LICENSE](LICENSE)、作者註記及 [原 README](UPSTREAM-README.md)。移除 `.git`、`.github` 及 JIT App Intents；未發布 workflow。
- 模組仍名 StikDebug；顯示名稱為 LocalGo，Bundle ID 為 `com.neven.localgo`。

## 已知直接依賴

| 項目 | 精確來源／版本 | 邊界 |
|---|---|---|
| StikDebug | 上述 commit | AGPL-3.0，來源與 LICENSE 保留 |
| idevice header／FFI 靜態庫 | 原樣來自上述 commit | 上游指向 [idevice](https://github.com/jkcoxson/idevice)；生成檔未附獨立建置 commit，不能假定是目前 main |
| CodeEditorView | 0.15.4，`aba6c189bb2f6fd9d7b8e9f5739aeb3c8c7e3254` | 保留上游鎖檔；驗證介面不使用編輯器 |
| Rearrange | 1.8.1，`5ff7f3363f7a08f77e0d761e38e6add31c2136e1` | 保留上游鎖檔 |
| DDI | DeveloperDiskImageService 內 HTTPS GitHub 來源 | 使用者開始準備才下載；來源可變，需另記實機版本才能重現 |
| LocalDevVPN | 使用者另裝 | 不在此來源或產物中 |

原樣檔案 SHA-256：

- `StikDebug/idevice/idevice.h`：`696286794e8cf1c18a91d4dab5046cef4d9bae352f5e7a1ad33fbc0ba30d7ab4`
- `StikDebug/idevice/libidevice_ffi.a`：`4db23fe1d342927b9480bb9a8577f219994365621dc28aa0018e23ea1990ecc8`
- `LICENSE`：`8486a10c4393cee1c25392769ddd3b2d6c242d6ec7928e1414efff7dfb2f07ef`

這不是靜態庫全部傳遞依賴的完整授權稽核，也未建立 App Store 發布資格。套件鎖檔在 `StikDebug.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`，下載來源內的授權檔保留在 `work/localgo-packages/checkouts`。

## 本地變更與建置

變更為 SwiftUI／MapKit 地圖、搜尋、路線與搖桿、GPX、本機收藏／歷史、前景移動排程、實際引擎 adapter、配對保護／目標核對、停止與清除排程、測試、停用原始診斷及自動動作、移除 JIT 捷徑、精簡權限和產品識別。

建置：Xcode 27.0（27A266a）、iPhoneOS 27.0 SDK、arm64、Debug、部署目標 26.0、停用簽署。命令與結果在 `work/localgo-feature-build.log`；測試在 `work/localgo-feature-tests.log`；衍生 patch／來源雜湊清單在 `work/localgo-patches`。不含使用者配對或簽署資料。

## Mac 首次設定

曾新增獨立 Python USB 設定工具 `MacSetup/`，固定 `pymobiledevice3==11.31.0`（GPL-3.0）；該 prototype 與其測試已於 2026-10-20 移除。Mac App 現使用自有唯讀裝置邊界 `app/GoFlyMac/Bridge/Device/gofly_device.py`，仍以隔離的 `work/mac-setup-env` 執行（需求清單在 `app/GoFlyMac/requirements.txt`）。實際環境版本清單在研究專案 `work/mac-first-setup/dependency-lock.txt`。配對 schema 以 idevice 原始碼核對，未使用 AnyGo 的程式碼、嵌入身分、金鑰或服務。

新增手機端私密交付 codec、一次性匯入、交易回報與重播防護，保留 PairingFileStore 原子匯入與原生驗證。最新驗證及已遮蔽身分的實機狀態在 `work/mac-first-setup/`；簽署產物在 `work/localgo-signed`，個人配對／憑證不放入產品原始碼。
