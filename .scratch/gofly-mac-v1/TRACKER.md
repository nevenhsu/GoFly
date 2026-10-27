# GoFly Mac V1 重構

日期：2026-10-26。依 [`docs/MAC-INSTALLER-SPEC.md`](../../docs/MAC-INSTALLER-SPEC.md)（設計已確認 v1）與 Figma「05 · Mac Redesign（新版）」的 V1 section 建立 12 張票。取代 `.scratch/prompts/03-mac-redesign.md` 與 `work/gofly-planning/MAC-RESET-BACKUP-PLAN.md`（備份／還原／重置／接續第一版不做）。逐票實作與驗收；軟體驗證不等於實機驗收。

| 票 | 狀態 | 依賴 | 驗收記錄 |
|---|---|---|---|
| 01 App 自給自足（內建 Python、iOS 專案、原生函式庫） | implemented; software-verified | — | 完整 arm64 app／DMG 建置、SHA-256 與 codesign 通過；隔離 quarantine 安裝後執行內建 Python、CFFI／cryptography、arm64 FFI 與 App launch；Swift 65、Bridge 94（2 skipped）、iOS 343＋13 boundary＋simulator build 全過；乾淨 Mac／實機未驗 |
| 02 依 Team 產生 Bundle ID | implemented; software-verified | 01 | Mac 47、Bridge 13、Setup 52、iOS 343 + 13 boundary、simulator build 與背景任務 ID 對照全過；Personal Team 簽署／實機交接未驗證 |
| 03 全新 Mac 環境檢查（bridge `environment`） | implemented; software-verified | 01 | Bridge 18、Mac Swift 48 全過；E06 乾淨 Mac 驗證待使用者依 `work/gofly-mac/v1/E06-VERIFY.md` 執行 |
| 04 App 外殼、E00 啟動畫面與啟動路由 | implemented; software-verified | 03 | Swift 60/60；Figma E00、Flow、D01 淺／深比對；截圖存 `work/gofly-mac/v1/screens/`；Mac 專屬色彩 token，未連實機 |
| 05 環境步驟頁 E01–E09 | implemented; software-verified | 04 | Swift 60/60、三語 plist lint；E01–E09 淺／深 Figma 比對；E06 乾淨 Mac 人工驗證待完成 |
| 06 以裝置為中心的側欄與裝置頁狀態 | implemented; software-verified | 04 | Swift 60/60；D01–D04、D08、D09、D12、D13 淺／深截圖比對；實體裝置狀態未驗 |
| 07 首次安裝流程 D04–D07 | implemented; software-verified | 02、06 | Swift 60/60、Bridge 18/18、Setup 53（2 skipped）；D04–D07 淺／深比對；實體安裝與 receipt 未驗 |
| 08 中斷「重新開始」，移除接續 | implemented; software-verified; visual-design-verified | 07 | Python 63（2 skipped）、Mac Swift 61 全過；iOS offline check／Simulator build 全過（含交接 host 測試）；原子認領／隔離 race 與同 setupID 離線重送覆蓋；D14 淺／深 Figma 比對，截圖已存；未做實機交易中斷驗收 |
| 09 Wi‑Fi 延長簽名 | implemented; software-verified; visual-design-verified | 08 | Network transport／只核對既有 pairing／receipt 讀回；Bridge 94（2 skipped）、Swift 65 全過；D08–D11、D13–D14 淺／深比對；同網路實機尚未驗 |
| 10 自動延長簽名 | implemented; software-verified; visual-design-verified | 09 | 啟動＋24 小時排程、4 天門檻、逐裝置開關、USB 優先、通知／保持喚醒；Swift 65 全過；D08、D10、D11 淺／深比對；真實 24 小時運行／通知／sleep assertion／receipt 尚未驗 |
| 11 DMG 與 install.sh | implemented; software-verified | 01、02 | `work/dist/GoFly-1.0.0-arm64.dmg`；SHA-256 與 `hdiutil verify` 通過；隔離 quarantine install、Python／原生模組／App launch 通過；乾淨 Mac 步驟在 `work/gofly-mac/v1/DMG-VERIFY.md`；正式 `/Applications` 安裝／公證尚未驗 |
| 12 文件與驗收清單收尾 | implemented; static-design-verified; pending user confirmation for Figma archive deletion | 全部 | Mac 安裝／UI 規格、README、DEVELOPMENT、Bridge protocol、AI install、裝置驗收清單同步；色彩掃描確認 Mac 專屬 token；Figma 68 個 Archive section 待使用者確認刪除 |

## 舊代碼與舊 UI：該刪就刪（所有票都適用）

- V1 取代的程式、畫面、資源、測試與文件**直接刪除**（`git rm`），不保留相容入口、隱藏開關、舊頁面備份、註解掉的程式或 `Legacy`／`Old` 命名的副本。刪除後無引用的型別、函式、字串、資源與測試一起刪。
- 刪除前用 `git grep` 確認沒有其他引用；刪除項目與理由寫進該票 Evidence。只刪 V1 範圍內被取代的東西，不動 iOS App 的功能程式（`app/GoFly` 只做票 01、02、08 指定的改動）。
- 使用者資料不在此列：手機上的 App、配對、偏好，以及 Mac 上舊的 `~/Library/Application Support/GoFlySetup` 狀態目錄，**不讀、不刪、不搬**。

| 刪除項目 | 取代者 | 在哪張票刪 |
|---|---|---|
| `LocalConfiguration.json`／`SetupConfiguration.json` 的產生與讀取、`workspaceRoot`／`work/mac-setup-env`／`app/GoFly` 路徑檢查（`build-app.sh`、`ProcessBridge.swift`、`setup_config.py`、`bridge.py`） | 從 `Bundle.main` 推導的路徑 | 01 |
| `app/LocalGo/StikDebug` 中被搬走的 3 個檔案；搬完後 `app/LocalGo/` 若無其他用途整個刪除（授權聲明改放 `app/GoFly/Legal/`） | `app/GoFly` 內的同名檔案 | 01 |
| 寫死的 `com.neven.gofly`（功能用途） | 依 Team 產生的 Bundle ID | 02 |
| bridge 的 `python-runtime`、`project`、`developer-tools`（命令列工具）等使用者可見檢查項目與對應測試 | 全新 Mac 檢查項目＋`bundle-damaged` | 03 |
| `MacEnvironmentGate.swift`、`MacPages.swift`（首頁、裝置清單頁、Mac 環境頁）、`MacRootView` 的舊導覽、`MacPage` 的 `home／environment／devices／device／install` 頁面列舉、舊首頁的 `EnvironmentPassed` 等不再使用的資源 | E00 啟動路由＋E01–E09＋裝置頁 | 04、05、06 |
| `MacSetupPage.swift` 舊安裝表單與 4 步首次安裝頁、「此 iPhone 已安裝 GoFly」頁（I08 行為） | D04–D07、D08 | 07 |
| `MacSetupContinuation`、`canResume`、`resume()`、`status()` 接續 UI、「繼續原交易／查詢原交易」按鈕；bridge 與 `scripts/install-ios-test.py` 的 `resume` action；只為接續存在的 journal 欄位與測試 | 「重新開始」 | 08 |
| `app/GoFlyMac/DEVELOPMENT.md`、`README.md`、`Bridge/PROTOCOL.md`、`docs/MAC-UI-DESIGN.md` 中已取代的舊規則與舊畫面描述；`.scratch/prompts/03-mac-redesign.md` | `docs/MAC-INSTALLER-SPEC.md` | 12 |
| Figma `05` 頁右側 `Archive ·` 舊版 section（34＋34 張） | V1 section | 12（V1 實作完成、使用者確認後才刪） |

## UI 準據：Figma（所有 UI 票都適用）

- Mac App 的每個畫面一律照 Figma 檔 `RtPV8PXCQJ2WXK3jk3kPrq` 頁面 `05 · Mac Redesign（新版）`（`123:61504`）的 `V1 · E Mac 環境（全新 Mac）`、`V1 · D 裝置` 及對應的 `Dark ·` section 製作。節點 ID 與共用版面數值見 [`FIGMA-NODES.md`](FIGMA-NODES.md)。
- 實作畫面前，用 Figma Console MCP 截圖該節點的淺色與深色版本，並讀畫面下方的灰字說明（行為規則）。版面、文案、間距、按鈕位置、狀態顏色照圖做。
- 連不到 Figma 時停下，請使用者開啟 Figma Desktop 與 Desktop Bridge plugin；不憑記憶、舊頁面或 `Archive ·` section 猜測。
- 完成後把 App 截圖存到 `work/gofly-mac/v1/screens/<畫面編號>-light.png`／`-dark.png`，與 Figma 並排比對到一致，截圖位置寫進票單的 Evidence。Figma 有而規格沒寫的細節照 Figma；規格與 Figma 衝突時停下回報，並在同一任務更新規格。
- 品牌圖示用 `00 · 品牌與基礎元件` › `Logo masters`（`13:1693`）；E00 對齊 iOS `R01 · 啟動畫面 / Logo`（`121:51102`）。系統視窗示意圖用 SwiftUI 繪製。
- Mac 顏色集中在 `app/GoFlyMac/Sources/GoFlyMac/MacColorSystem.swift` 的 Mac 專屬語意 token，跟隨系統淺／深外觀；Mac View 不散落原始色值，iOS 色彩程式獨立維護。
- 使用 macOS 系統字體與 SF Symbols；支援深淺色、鍵盤焦點、1000 × 700 可捲動；三語字串。

Figma 節點 ID 見 [`FIGMA-NODES.md`](FIGMA-NODES.md)。逐票證據、未驗證事項記在 `issues/` 對應票單。
