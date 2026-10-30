# 09: D：路線規劃面板與選點（D1–D5、D2.a 視覺）

**What to build:** Figma D 區前段：路線規劃面板（初始、多停靠點、panel 收合、Pin 設定選中地點、選擇終點回填）、停靠點清單與選中列、拖曳排序示意（被抓取列、一般列、新順序位置框三種外框角色）、「檢視路線」入口。只做視覺與版面對齊，不改新增停靠點或規劃邏輯。

**Blocked by:** 05.

**Status:** done: software-verified

**Assignee hint:** Luna

- [x] D1、D2、D2.a、D3、D4、D5 對應 fixture 完成 Light／Dark 比對。
- [x] D5 選點頁為『輸入為空』狀態：搜尋欄不顯示 placeholder（顯示游標與貼上鈕、無清除鈕）；清單最上方有『使用目前位置』列（定位箭頭圖示，點選以目前位置回填選中欄位並返回），下方為『最近搜尋』。只有輸入為空時才顯示這兩個區塊，輸入文字後改顯示搜尋結果——依當前 Figma 渲染對齊。
- [x] 清單外框、一般列、抓取列、新順序位置框的邊線角色與 Figma 色票一致（`subtle`／`default`／`focus`／`strong`）。
- [x] 停靠點清單背景、Sheet 與按鈕層級符合 Dark 階梯；選中列為 primary 邊線＋中性底。
- [x] **地圖一律滿版**：所有出現地圖的畫面，地圖都填滿整個螢幕（延伸到狀態列、Dynamic Island、底部 Tab Bar 與 home indicator 後方，忽略四邊 safe area），面板、Sheet、Tab Bar、浮動控制項與狀態列疊在地圖上方；Sheet 展開／收合、鍵盤出現、旋轉與切換淺深色時地圖不縮放、不留空白邊或色帶，地圖的有效中心與右側控制鈕位置依可見區域（扣除 Sheet）計算。
- [x] 本票涵蓋的畫面中，所有圖示都經 `GoFlyIcon` 使用 Figma『0 · 共用元件（Icon）』匯出的資產（依票 03 對照表），不再出現 SF Symbol；尺寸、顏色 token 與 Figma 一致；對照表沒有的 icon 列入『執行紀錄』回報。
- [x] 本票涵蓋畫面的文字一律 `Font.system`（依 `Theme/*`），圖示一律來自 Figma『0 · 共用元件（Icon）』（經 `GoFlyIcon`）；沒有 `Font.custom`、SF Symbol 或自繪替代。
- [x] **截圖驗證（必做，沒有截圖視為未完成）**：用 01a 的 fixture（不需網路、VPN、真機）對本票涵蓋的每一張 frame、Light 與 Dark 各截一張，存到 `work/gofly-ios-figma04/screenshots/`，並與 `work/gofly-ios-figma04/figma/` 的同名 Figma 截圖並排比對：無破版、無文字截斷、無缺漏元素、顏色與層級一致。把每張的結論（一致／有差異＋原因）與檔案路徑寫入票尾『執行紀錄』；到不了的 frame 如實列出，不略過。
- [x] 最大 Dynamic Type 與 Reduce Motion 下仍可操作；互動元件觸控命中範圍 ≥ 44 × 44 pt；每個圖示按鈕有 accessibility label。
- [x] 相關單元測試與 UI tests 更新並通過；`app/GoFly/scripts/check.sh` 通過。
- [x] 不改命令、送點、ACK、背景執行語意（`app/GoFly/ARCHITECTURE.md` 不變量）；不宣稱實機驗證。

## 執行紀錄

### 2026-10-30 執行紀錄（Luna）

- D1–D5 視覺與排版已更新；D5「使用目前位置」改用與最近搜尋相同的 list row 結構、card 底色與 12 pt 圓角，保留至最近搜尋區 16 pt 間距。Favorite 使用共用 Primary Icon + Text inline button，按鈕命中區 ≥ 44 pt。D1 focused row 的 primary 邊線圓角改為與外層清單卡相同的 14 pt。
- StatusPill 與其上方搜尋列／執行標題統一 12 pt；D5 Role chip 上下視覺留白各 16 pt，搜尋清單列上下內距各 8 pt。已同步更新 `GoFlyStyle.statusPillTopSpacing`、設計規格與路線任務文件。
- D2 離線 fixture 使用標題為「目前位置」的固定座標 place 產生預覽，避免模擬器沒有 GPS 時觸發 route error toast；僅供截圖 fixture，不改定位、規劃或命令語意。
- 測試通過：`testRoutePlanningFramesMatchFixturesInBothAppearances`（D1、D2、D2.a、D3、D4、D5 各 Light／Dark）；`testD1ControlsRemainReachableAtMaximumDynamicTypeAndReduceMotion`（Light／Dark）；`bash app/GoFly/scripts/check.sh`（349 tests／58 suites、host tests、unsigned simulator build）。沒有執行 Prettier。
- App 截圖：`work/gofly-ios-figma04/screenshots/D1-light.png`、`D1-dark.png`、`D2-light.png`、`D2-dark.png`、`D2.a-light.png`、`D2.a-dark.png`、`D3-light.png`、`D3-dark.png`、`D4-light.png`、`D4-dark.png`、`D5-light.png`、`D5-dark.png`；與 `work/gofly-ios-figma04/figma/` 中同名 Figma 渲染並排核對。總覽：`work/gofly-ios-figma04/screenshots/index.html`。
- 比對結果：D1 清單色階、選中列、14 pt 圓角與按鈕位置一致；Figma 靜態畫面將空終點時的「開始」畫成啟用藍色，App 因沒有完整路線而維持停用，保留既有不可空路線啟動行為。D2／D2.a 點位名稱、列數與拖曳示意已對齊；D2 不再顯示錯誤 toast。D3 收合面板與路線預覽可見，D4 選點 Pin／LocationCard 版面可見；D5 空搜尋欄、Role chip、最近位置卡、最近搜尋卡與鍵盤下方留白已比對。所有地圖 frame 的底圖與路線圖樣仍因 App 使用原生 MapKit、Figma 使用靜態示意地圖而不同；D5 鍵盤由 iOS 原生控制器繪製，與 Figma 示意鍵盤字樣不同。
- 差異／決策：D4 Figma 渲染 CTA 顯示「開始」，但其說明是設定選中路線地點，App 保留「確認」回填動作；靜態 Figma 的 CTA 文案與行為說明不一致，未改動路線命令語意。D5 Figma 畫面為 primary 色的星號＋`Favorite` 文字，依使用者追加要求，App 改成共用 Primary 填色 Icon + Text 按鈕；此為明確使用者覆寫，Figma 未修改。`GoFlyIcon` 對照表涵蓋本票圖示，畫面字型依 Theme 使用 `Font.system`。
- 未做實機驗證；Figma 全程唯讀，未修改。

### 使用者追加比對項（2026-10-29，已完成）

- D1 Dark：停靠點 list 背景色與「新增停靠點」文字／圖示顏色不符 Figma。
- D1 Light：停靠點 list 背景色與 star button 樣式不符 Figma。
- 已依本票執行紀錄重截 `D1-light.png`、`D1-dark.png` 並完成並排核對。

### 使用者追加比對項（2026-10-30，已完成）

- D1 focused row 藍色邊線被清單外框遮住：focused row 背景與邊線圓角統一為清單卡片的 14 pt。
- D5「使用目前位置」列改為與最近搜尋相同的 list row 排版、card 底色與卡片圓角；按鈕本身命中高度為 52 pt。
- D5 Favorite 使用共用 Primary Icon + Text inline button；Role chip、目前位置列、搜尋列間距依使用者最終更正值執行。StatusPill 的最終上方間距為 12 pt。
