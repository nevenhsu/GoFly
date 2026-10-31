# 13: D：GPX 匯入與匯出（D11–D18）

**What to build:** Figma D 區：已匯入路線清單、動作選單、查看全部點位、系統分享 sheet、匯入摘要與折疊點位、檔案選擇器、匯入成功 snackbar 與失敗 toast。

**Blocked by:** 05.

**Status:** in progress: D15 surface token delta pending UI verification

**Assignee hint:** Luna

- [x] D11–D18 對應 fixture 完成 Light／Dark 比對。
- [x] 系統分享 sheet 在 Dark 由 iOS 原生畫面呈現；依 Figma 原生系統 sheet 規格保留，差異記於執行紀錄。
- [x] 動作選單、分享、刪除可復原行為不變，只改外觀。
- [x] 本票涵蓋的所有 Toast／Banner 都以懸浮方式顯示（疊在內容上方、含浮層陰影、不推動版面），依票 04 的共用 Toast overlay 容器。
- [x] **地圖一律滿版**：所有出現地圖的畫面，地圖都填滿整個螢幕（延伸到狀態列、Dynamic Island、底部 Tab Bar 與 home indicator 後方，忽略四邊 safe area），面板、Sheet、Tab Bar、浮動控制項與狀態列疊在地圖上方；Sheet 展開／收合、鍵盤出現、旋轉與切換淺深色時地圖不縮放、不留空白邊或色帶，地圖的有效中心與右側控制鈕位置依可見區域（扣除 Sheet）計算。
- [x] 本票涵蓋的畫面中，所有圖示都經 `GoFlyIcon` 使用 Figma『0 · 共用元件（Icon）』匯出的資產（依票 03 對照表），不再出現 SF Symbol；尺寸、顏色 token 與 Figma 一致；對照表沒有的 icon 列入『執行紀錄』回報。
- [x] 本票涵蓋畫面的文字一律 `Font.system`（依 `Theme/*`），圖示一律來自 Figma『0 · 共用元件（Icon）』（經 `GoFlyIcon`）；沒有 `Font.custom`、SF Symbol 或自繪替代。
- [x] **截圖驗證（必做，沒有截圖視為未完成）**：用 01a 的 fixture（不需網路、VPN、真機）對本票涵蓋的每一張 frame、Light 與 Dark 各截一張，存到 `work/gofly-ios-figma04/screenshots/`，並與 `work/gofly-ios-figma04/figma/` 的同名 Figma 截圖並排比對：無破版、無文字截斷、無缺漏元素、顏色與層級一致。把每張的結論（一致／有差異＋原因）與檔案路徑寫入票尾『執行紀錄』；到不了的 frame 如實列出，不略過。
- [x] 最大 Dynamic Type 與 Reduce Motion 下仍可操作；互動元件觸控命中範圍 ≥ 44 × 44 pt；每個圖示按鈕有 accessibility label。
- [x] 相關單元測試與 UI tests 更新並通過；`app/GoFly/scripts/check.sh` 通過。
- [x] 不改命令、送點、ACK、背景執行語意（`app/GoFly/ARCHITECTURE.md` 不變量）；不宣稱實機驗證。

## 執行紀錄

### 2026-10-30 App implementation（Figma 04 只讀）

- **完成項**：D11 路線清單與 D12 動作卡使用共用元件；D13 改為全螢幕點位清單，導覽列為左側返回＋置中標題，「唯讀」移至檔名／點數資訊列右側的小字；點位列分隔線左右各內縮 16 pt、座標顯示 5 位小數。D15 長序號 1,248 改用 footnote 後保持單行。D17 Snackbar 與 D18 錯誤 Banner 使用共用浮層 Toast 容器；D18 顯示「重試」，點擊重新開啟檔案選擇器。D13 共用頁首在最大 Dynamic Type 下改為分行排列，避免返回鍵與標題互相遮擋；GPX 頁容器保留子項 accessibility identity。未更動匯入、分享、刪除復原、載入路線、命令或背景執行語意。
- **Light／Dark 截圖與對照**：D11 `work/gofly-ios-figma04/screenshots/D11-light.png`／`D11-dark.png`；D12 `D12-light.png`／`D12-dark.png`；D13（按最新 Figma 位置重拍）`D13-light.png`／`D13-dark.png`；D14 `D14-light.png`／`D14-dark.png`；D15 `D15-light.png`／`D15-dark.png`；D16 `D16-light.png`／`D16-dark.png`；D17 `D17-light.png`／`D17-dark.png`；D18 `D18-light.png`／`D18-dark.png`。各圖均與 `work/gofly-ios-figma04/figma/` 同名 Figma render 並排比較。D11 清單卡、D12 遮罩／動作卡、D13 導覽列／清單層級、D15 千位序號、D17 成功 Snackbar 位置、D18 錯誤 Banner 結構和按鈕符合 Figma；MapKit 地圖底圖與 Figma 靜態底圖有原生地圖差異。
- **仍有差異／Figma 與 fixture 限制**：匯入 GPX 資料模型只有檔名、座標及點數，沒有具名端點或路線距離，所以 D11／D12／D13／D15 以實際座標／點數呈現，不偽造 Figma 樣例的地名與距離。D14 使用 iOS 原生分享 sheet，系統版本與可用分享目標（本次顯示 Health／More 等）和 Figma 的靜態列舉不同；D16 使用原生 Files picker，模擬器「最近項目」為空，Figma 預置的三個最近檔案無法由 app 填入。兩者都是系統原生畫面差異，Figma 本身亦註明由 iOS 呈現。
- **測試**：`testCaptureSectionD3GPXFramesInBothAppearances` 通過（D11–D18 共 16 張）；`testCaptureD13PointsFrameInBothAppearances` 通過並重拍 D13 Light／Dark；`testD13PointsStayScrollableAtMaximumDynamicTypeWithReduceMotion` 通過（Light／Dark、可操作返回並捲動到後續點位）。`bash app/GoFly/scripts/check.sh` 通過：359 tests／58 suites、Native handoff tests、unsigned simulator build；`git diff --check` 通過。**未做實機驗證**。
