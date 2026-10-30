# 01a: UI 截圖驗證工具（繞過模擬器沒有網路、VPN、真機的限制）

**What to build:** 建立只存在於 Debug＋模擬器的 fixture 層，讓 Figma A–F 每一張 frame 的狀態都能在**沒有網路、沒有 VPN、沒有真機**的模擬器上直接開到、截圖、與 Figma 比對。沿用 repo 既有 `GoFlyUITestOverrides` 的模式（只在 `DEBUG && targetEnvironment(simulator)` 編譯，Release 與真機 build 為無作用版本，正式參數不可選取測試狀態）。目前已有的旗標只涵蓋 VPN 不可達（`-gofly-ui-unreachable`）、Wi‑Fi 連線／中斷、各種 store 與偏好；本票補齊其餘無法在模擬器自然出現的狀態。

**Blocked by:** None (can start immediately).

**Status:** done: software-verified

**Assignee hint:** Luna

- [x] 新增單一入口旗標（例如 `-gofly-ui-frame <FrameID> -gofly-ui-appearance light|dark`），直接啟動到對應 Figma frame 的狀態；FrameID 與 Figma frame 名稱一致（A 區 R01…、B1–B11、C1–C4、D1–D23、E1–E7、F1–F9 含 F1.a、F1.b、F6.a）。
- [x] Fixture 提供下列離線、可預期的替身（僅 fixture 模式使用，不改正式程式路徑）：裝置服務與 session 狀態（已停止、啟動中、運行中、暫停、錯誤、停止失敗、重置成功）、VPN 通道可用／不可用、Wi‑Fi 連線／中斷、定位權限（使用期間／拒絕／尚未決定）與真實定位、模擬位置、MapKit 搜尋與地點解析（固定結果）、路線規劃器（成功、`planningFailed`、重排後成功）、最愛地點／最愛路線／匯入 GPX 的種子資料、背景運行時間。
- [x] 模擬器沒有網路時 MapKit 底圖是空白：fixture 模式以本地固定底圖（與 Figma `Map / Base` 的 Light／Dark 色票一致、滿版）取代底圖，讓含地圖的畫面可以截圖比對；路線線、Pin、箭頭仍用正式繪製程式。
- [x] 提供一個 UI test（例如 `GoFlyFigmaFrameScreenshots`）一次產生全部 frame × Light／Dark 的截圖，輸出到 `work/gofly-ios-figma04/screenshots/<frame>-<light|dark>.png`，並寫入 `manifest.json`（frame、主題、路徑、使用的 fixture 旗標）。`work/` 不進版控。
- [x] 同一資料夾產生 `index.html` 總覽頁：每個 frame 一列，左 Figma、右 App，Light 與 Dark 各一欄，可依 section 篩選，直接用瀏覽器開啟即可查看（`open work/gofly-ios-figma04/screenshots/index.html`）；每次重跑會覆蓋，並保留上一輪於 `screenshots/previous/`。資料夾已由根目錄 `.gitignore` 的 `work/` 忽略，不進版控；驗證 `git check-ignore` 命中。
- [x] 提供 Figma 對照圖的取得方式（以 Figma Console `figma_capture_screenshot` 讀取同名 frame，輸出到 `work/gofly-ios-figma04/figma/`），並寫成腳本或說明，後續每票的比對都用這兩個資料夾。
- [x] 驗證不外洩：Release 與真機（unsigned device）build 都能編譯，且不含這些旗標的實作（以單元測試或 build 檢查證明）；`check.sh` 通過。
- [x] 本票結束時，已知 Figma 有、但 fixture 暫時到不了的 frame 列成清單寫入『執行紀錄』，不得略過不報。
- [x] 不改命令、送點、ACK、背景執行語意；fixture 不得呼叫真實裝置 API、不要求網路或 VPN。

## 執行紀錄

### 2026-10-30 執行紀錄（Luna）

- 完成 A–F 目前 Figma 04 catalog 的 64 個 frame fixture，Light／Dark 共 128 張 App 截圖；manifest 列出的 App 與 Figma PNG 皆齊全，沒有 fixture 不可達 frame。總覽頁：`work/gofly-ios-figma04/screenshots/index.html`；輸出與 Figma 對照圖分別在 `work/gofly-ios-figma04/screenshots/`、`work/gofly-ios-figma04/figma/`。每張 frame 的並排圖可在 HTML 開啟檢視；此票驗證 fixture 可達性，不將尚未逐頁修正的視覺差異宣稱為一致。
- 全量 UI capture：`work/gofly-ios/figma-harness-all-frames.xcresult`，64 個 frame × 2 外觀，1 test、0 failures；archive regression：`work/gofly-ios/figma-harness-archive-regression.xcresult` 通過。修正 previous-run 保存流程，舊輸出先封存再移出主目錄；主目錄現有 128 張與 manifest 完全相符。
- `bash app/GoFly/scripts/check.sh --device` 通過（含 Swift 342 tests／57 suites、Native host tests、Simulator build、NativeBridge build／驗證與 unsigned iPhoneOS build）；Release Simulator build 通過。檢查 Release Simulator 與 iPhoneOS app 執行檔／dylib，均沒有 `-gofly-ui-*` 旗標字串。`git diff --check` 通過；`git check-ignore` 確認截圖輸出位於忽略的 `work/`。
- Figma 僅讀取，未修改。Figma 缺口：R06 沒有 frame 或渲染版本，未合成假圖。文件衝突：目前目錄與只讀渲染有 Dark · B11（node `322:40470`），舊票 00 紀錄稱其缺 Dark；保留在 manifest，等待文件整理。其他已知視覺差異保留給相應頁面票修正。
- 未做實機驗證；未安裝到手機。

### 2026-10-29 執行紀錄（Luna）

- 已建立 Debug＋Simulator-only 的 `-gofly-ui-frame`／`-gofly-ui-appearance` 入口、`Figma04FrameCatalog.json`、兩外觀 screenshot UI test、HTML 並排頁與 previous-run 保存；Release／device target 不編譯 fixture view。Figma 參考只讀取，未修改。
- 截圖已產生到 `work/gofly-ios-figma04/screenshots/`，目前支援 R01、R02、R03、R04、R04.a、R05、R07、R08、B1、B2、B5、B7、B10、D1、D6、D8、E1、F1、F1.b 的 Light／Dark 共 38 張；對照總覽：`work/gofly-ios-figma04/screenshots/index.html`，manifest 記錄 Figma node、fixture flags、不可達 frame 與缺口。R04 Light／Dark 標題位置修正已有更新截圖；其餘 frame 的全量逐張視覺驗收仍未完成。
- 尚未支援的 45 個 frame 及原因已逐項列在 `manifest.json`：需要 deterministic MapKit search／command／recovery、最愛與路線種子資料、GPX／share 狀態、搖桿／漫步狀態或設定權限 fixture；逐票補齊後再重跑。B11 Dark 截圖目前列為 Figma 衝突證據，不算已核准設計。
- **未完成**：ticket 要求的 A–F 全 frame fixture／截圖尚未達成，因此本票維持 `in progress`；需隨後續票補齊 fixture，不能以缺圖視為通過。`check.sh` 與現有 screenshot UI test 曾通過；未做實機驗證。
