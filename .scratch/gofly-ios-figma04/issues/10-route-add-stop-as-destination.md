# 10: 路線：新增停靠點加在最後當終點

**What to build:** 使用者按『＋ 新增停靠點』（規劃面板與『全部點位』清單頁兩處）時，新增一個空的輸入欄位到清單**最後**，成為新的終點；原本的終點降為最後一個停靠點，原值不變。選取該空欄位並可立刻搜尋／選點回填。其他點的順序、起點與草稿持久化行為不變。

**Blocked by:** 09, 00.

**Status:** done: software-verified

**Assignee hint:** Luna

- [x] 有起點與終點的草稿按新增後，清單順序為 起點、…、原終點、新空欄位；新空欄位的角色標示為『終點』，原終點標示為『停靠點 N』。
- [x] 只有起點時按新增（nodes < 2）行為維持：先補出終點欄位；已達 27 個地點上限時按鈕停用並保留 accessibility hint。
- [x] 新欄位為空時不觸發規劃、不顯示錯誤；回填後才重新規劃預覽路線。
- [x] 核心單元測試覆蓋：插入位置、角色重算、上限、持久化與復原往返、`reverseNodes`／`moveNode` 與新欄位互動。
- [x] UI test：規劃面板與全部點位頁各一條新增流程；`docs/ROUTE-MODE-TASKS.md` 與 `docs/IOS-UI-DESIGN.md` 的『插在終點前』敘述全部更新。
- [x] **地圖一律滿版**：所有出現地圖的畫面，地圖都填滿整個螢幕（延伸到狀態列、Dynamic Island、底部 Tab Bar 與 home indicator 後方，忽略四邊 safe area），面板、Sheet、Tab Bar、浮動控制項與狀態列疊在地圖上方；Sheet 展開／收合、鍵盤出現、旋轉與切換淺深色時地圖不縮放、不留空白邊或色帶，地圖的有效中心與右側控制鈕位置依可見區域（扣除 Sheet）計算。
- [x] 本票涵蓋的畫面中，所有圖示都經 `GoFlyIcon` 使用 Figma『0 · 共用元件（Icon）』匯出的資產（依票 03 對照表），不再出現 SF Symbol；尺寸、顏色 token 與 Figma 一致；對照表沒有的 icon 列入『執行紀錄』回報。
- [x] 本票涵蓋畫面的文字一律 `Font.system`（依 `Theme/*`），圖示一律來自 Figma『0 · 共用元件（Icon）』（經 `GoFlyIcon`）；沒有 `Font.custom`、SF Symbol 或自繪替代。
- [x] **截圖驗證（必做，沒有截圖視為未完成）**：用 01a 的 fixture（不需網路、VPN、真機）對本票涵蓋的每一張 frame、Light 與 Dark 各截一張，存到 `work/gofly-ios-figma04/screenshots/`，並與 `work/gofly-ios-figma04/figma/` 的同名 Figma 截圖並排比對：無破版、無文字截斷、無缺漏元素、顏色與層級一致。把每張的結論（一致／有差異＋原因）與檔案路徑寫入票尾『執行紀錄』；到不了的 frame 如實列出，不略過。
- [x] 最大 Dynamic Type 與 Reduce Motion 下仍可操作；互動元件觸控命中範圍 ≥ 44 × 44 pt；每個圖示按鈕有 accessibility label。
- [x] 相關單元測試與 UI tests 更新並通過；`app/GoFly/scripts/check.sh` 通過。
- [x] 不改命令、送點、ACK、背景執行語意（`app/GoFly/ARCHITECTURE.md` 不變量）；不宣稱實機驗證。

## 執行紀錄

### 2026-10-30 執行紀錄（Luna）

- **Figma 設計（只讀）**：重新讀取 D1 Light `121:52566` 與 D2 Light `222:11484` 渲染；D1／D2 說明要求新空欄位追加於清單最後成為終點，原終點保留原值並降為停靠點。未修改 Figma。沒有專門的新增後互動 frame，票內行為說明提供規格。
- **App 實作**：`RouteDraft.inserting` 改為尾端追加；新欄位仍為空時不排程路線規劃且不顯示錯誤，選取新欄位。規劃面板與「全部點位」清單新增後都捲至新列，方便立即開 D5 搜尋／回填。更新 `ROUTE-MODE-TASKS.md`、`IOS-UI-DESIGN.md` 中舊的「終點前插入」規格。
- **測試**：`RouteEndpointTests` 覆蓋追加順序、角色重算、空終點不規劃與填值後重規劃、單一起點、27 點上限、復原序列化、反轉及移動。UI test `testAddingWaypointFromPanelAndAllPointsCreatesSelectedDestinationInBothAppearances` 通過，覆蓋面板／全點位入口、Light／Dark、新終點選取及第二次點擊進 D5。`bash app/GoFly/scripts/check.sh` 通過（353 tests／58 suites、LocalGoSetupHandoff host tests、unsigned simulator build）；UI test 1 passed／0 failed（`work/gofly-ios/ticket10-add-stop-ui-retry1.xcresult`）。
- **App 截圖**：`work/gofly-ios-figma04/screenshots/ticket10-feedback/D2-panel-add-stop-light.png`、`D2-panel-add-stop-dark.png`、`D2-all-points-add-stop-light.png`、`D2-all-points-add-stop-dark.png`。與 `work/gofly-ios-figma04/figma/` 的 D1／D2 同名靜態 frame 並排查看；新增後空終點、原終點角色、選取邊框與全點位列順序符合說明。靜態 Figma 沒有新增後狀態畫面，故互動截圖屬 App 行為驗收；MapKit 地圖道路與地名仍不同於 Figma 靜態底圖。
- 未做實機驗證；未 commit。
