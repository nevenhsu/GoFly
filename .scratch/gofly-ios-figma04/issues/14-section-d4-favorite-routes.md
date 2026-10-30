# 14: D：最愛路線與檢視路線（D19–D23）

**What to build:** Figma D 區：最愛路線清單、新增最愛路線 sheet、多選模式、刪除 snackbar、檢視路線 sheet（全部地點）。

**Blocked by:** 05.

**Status:** in progress: 2026-10-30 UI corrections pending software verification

**Assignee hint:** Luna

- [x] D19–D23 對應 fixture 完成 Light／Dark 比對。
- [x] 新增最愛 sheet 內輸入與清單比 sheet 底亮兩階，遮罩為黑色壓暗。
- [x] **地圖一律滿版**：所有出現地圖的畫面，地圖都填滿整個螢幕（延伸到狀態列、Dynamic Island、底部 Tab Bar 與 home indicator 後方，忽略四邊 safe area），面板、Sheet、Tab Bar、浮動控制項與狀態列疊在地圖上方；Sheet 展開／收合、鍵盤出現、旋轉與切換淺深色時地圖不縮放、不留空白邊或色帶，地圖的有效中心與右側控制鈕位置依可見區域（扣除 Sheet）計算。
- [x] 本票涵蓋的畫面中，所有圖示都經 `GoFlyIcon` 使用 Figma『0 · 共用元件（Icon）』匯出的資產（依票 03 對照表），不再出現 SF Symbol；尺寸、顏色 token 與 Figma 一致；對照表沒有的 icon 列入『執行紀錄』回報。
- [x] 本票涵蓋畫面的文字一律 `Font.system`（依 `Theme/*`），圖示一律來自 Figma『0 · 共用元件（Icon）』（經 `GoFlyIcon`）；沒有 `Font.custom`、SF Symbol 或自繪替代。
- [x] **截圖驗證（必做，沒有截圖視為未完成）**：用 01a 的 fixture（不需網路、VPN、真機）對本票涵蓋的每一張 frame、Light 與 Dark 各截一張，存到 `work/gofly-ios-figma04/screenshots/`，並與 `work/gofly-ios-figma04/figma/` 的同名 Figma 截圖並排比對：無破版、無文字截斷、無缺漏元素、顏色與層級一致。把每張的結論（一致／有差異＋原因）與檔案路徑寫入票尾『執行紀錄』；到不了的 frame 如實列出，不略过。
- [x] 最大 Dynamic Type 與 Reduce Motion 下仍可操作；互動元件觸控命中範圍 ≥ 44 × 44 pt；每個圖示按鈕有 accessibility label。
- [x] 相關單元測試與 UI tests 更新並通過；`app/GoFly/scripts/check.sh` 通過。
- [x] 不改命令、送點、ACK、背景執行語意（`app/GoFly/ARCHITECTURE.md` 不變量）；不宣稱實機驗證。

## 執行紀錄

### 2026-10-30 App implementation（Figma 04 只讀）

- **完成項**：
  - D19 最愛路線全螢幕頁：canvas 背景、左右 16 pt 單一卡片、六列各 64 pt，星號圓／標題／副標／⋯ 命中對齊 Figma；末列不畫 divider；底部搜尋欄整合系統 `UIPasteControl`，底色修正為 `GoFlyStyle.inputSurfaceUIColor`，消除灰色圓底。
  - D20 新增／編輯最愛路線 sheet：輸入欄與路線資訊卡層次符合規範，不自動叫出鍵盤；儲存按鈕下方依使用者要求保留 40 pt 留白。
  - D21 多選模式：批次選取第 2、4 列，顯示「已選取 2 項」，底部懸浮 361 × 48 紅色「刪除（2）」膠囊按鈕。
  - D22 刪除可復原 Snackbar：成功圖示採雙色圓形 check，懸浮於搜尋區上方 12 pt，支援 5 秒復原。
  - D23 全螢幕「全部地點」清單頁：共用返回＋置中標題「全部地點」，左右 16 pt 卡片列出序號、地點與起點／停靠點 N／終點角色；反轉按鈕圖示修正為垂直反轉向量資產 `GoFlySymbols.swapVertical` (`GoFlyIconAsset.swapVertical`)，核對 18 pt 尺寸與 `GoFlyTextColor.primary` 色彩 token；底部「＋ 新增停靠點」與「⇅ 反轉順序」置於 ScrollView 內，最大 Dynamic Type 下垂直重排且可捲動、不被裁切。
- **Light／Dark 截圖與對照**：
  - D19: `work/gofly-ios-figma04/screenshots/D19-light.png` / `D19-dark.png`
  - D20: `work/gofly-ios-figma04/screenshots/D20-light.png` / `D20-dark.png`
  - D21: `work/gofly-ios-figma04/screenshots/D21-light.png` / `D21-dark.png`
  - D22: `work/gofly-ios-figma04/screenshots/D22-light.png` / `D22-dark.png`
  - D23: `work/gofly-ios-figma04/screenshots/D23-light.png` / `D23-dark.png`
  - 10 張截圖均與 `work/gofly-ios-figma04/figma/` 同名 Figma 渲染在 `work/gofly-ios-figma04/screenshots/index.html` 並排比對：卡片邊框、圓角、文字階級、分隔線內縮與色彩一致，滿版地圖與浮層控制無破版。
- **差異與 Figma 矛盾記錄**：
  - Figma D21 矛盾：Figma D21 渲染了 3 個勾選圖形（第 2、4、5 列），但文字標題顯示「已選取 2 項」；依 D22 實際刪除 2 項之結果，App 採第 2、4 列，將此矛盾如實記錄。
  - 資料模型限制：`FavoriteRouteRecord` 未保存總距離，D19／D20 不假造 Figma 樣例中的「12.4 km」距離，副標維持真實「起訖地點 · 點位數」。
  - 搜尋 placeholder：D19 Figma 搜尋 placeholder 誤渲染為「搜尋最愛地點」，App 維持正確行為「搜尋最愛路線」，僅篩選最愛路線清單。
  - D20 儲存按鈕下方留白：依 2026-10-30 使用者追加指示改為 40 pt（Figma 靜態渲染約 20 pt，App 依使用者要求為 40 pt）。
- **測試**：
  - `testCaptureD19ThroughD23InBothAppearances` 通過（10 張截圖完整寫入，無失敗）。
  - `testD19D20D23RemainReachableAtMaximumDynamicTypeWithReduceMotion` 通過（D19、D20、D23 在最大 Dynamic Type XXXL 與 Reduce Motion 下滾動流暢、按鈕可點擊不裁切、D20 鍵盤不跳出）。
  - `bash app/GoFly/scripts/check.sh` 通過：359 tests／58 suites、Native handoff 測試及 unsigned simulator build 全部成功。
  - 規格文件 `docs/IOS-UI-DESIGN.md` 與 `docs/ROUTE-MODE-TASKS.md` 同步更新。**未做實機驗證、未 commit**。
