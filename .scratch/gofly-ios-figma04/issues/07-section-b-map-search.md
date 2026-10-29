# 07: B：地圖首頁、搜尋、地點 sheet、瞬移

**What to build:** Figma B 區所有 frame：瞬移首頁與收合 sheet、模擬中 pill、全螢幕搜尋（B3 空輸入、B4 座標與結果、原生鍵盤）、地點 sheet 與 LocationCard、Pin 與 Go、瞬移失敗／中斷／Wi‑Fi／連接中的 toast 與 pill。

**Blocked by:** 05.

**Status:** in progress

**Assignee hint:** Luna

- [ ] B 區每張 frame 對應 fixture 並完成 Light／Dark 比對。
- [ ] 全螢幕搜尋進入時隱藏地圖、pill、tabs；鍵盤出現時鍵盤配色符合 Dark 規格（鍵盤底為 card 級、按鍵為 control 級、確認鍵白字）。
- [ ] Toast 與 pill 的錯誤、警告、成功三種語意不混用；B11 連接中只有 Light 設計，Dark 依 Light 結構並標註缺口。
- [ ] 本票涵蓋的所有 Toast／Banner 都以懸浮方式顯示（疊在內容上方、含浮層陰影、不推動版面），依票 04 的共用 Toast overlay 容器。
- [ ] **地圖一律滿版**：所有出現地圖的畫面，地圖都填滿整個螢幕（延伸到狀態列、Dynamic Island、底部 Tab Bar 與 home indicator 後方，忽略四邊 safe area），面板、Sheet、Tab Bar、浮動控制項與狀態列疊在地圖上方；Sheet 展開／收合、鍵盤出現、旋轉與切換淺深色時地圖不縮放、不留空白邊或色帶，地圖的有效中心與右側控制鈕位置依可見區域（扣除 Sheet）計算。
- [ ] 本票涵蓋的畫面中，所有圖示都經 `GoFlyIcon` 使用 Figma『0 · 共用元件（Icon）』匯出的資產（依票 03 對照表），不再出現 SF Symbol；尺寸、顏色 token 與 Figma 一致；對照表沒有的 icon 列入『執行紀錄』回報。
- [ ] B1 Dark 實機回饋已落實：Tab Bar 與 panel 同色同透明度、Dark 地圖為黑色主題（見票 05）；B1、B5、D1、D6、E1 的 Dark 截圖抽查地圖與 Tab Bar 無色差。
- [ ] 本票涵蓋畫面的文字一律 `Font.system`（依 `Theme/*`），圖示一律來自 Figma『0 · 共用元件（Icon）』（經 `GoFlyIcon`）；沒有 `Font.custom`、SF Symbol 或自繪替代。
- [ ] **截圖驗證（必做，沒有截圖視為未完成）**：用 01a 的 fixture（不需網路、VPN、真機）對本票涵蓋的每一張 frame、Light 與 Dark 各截一張，存到 `work/gofly-ios-figma04/screenshots/`，並與 `work/gofly-ios-figma04/figma/` 的同名 Figma 截圖並排比對：無破版、無文字截斷、無缺漏元素、顏色與層級一致。把每張的結論（一致／有差異＋原因）與檔案路徑寫入票尾『執行紀錄』；到不了的 frame 如實列出，不略過。
- [ ] 最大 Dynamic Type 與 Reduce Motion 下仍可操作；互動元件觸控命中範圍 ≥ 44 × 44 pt；每個圖示按鈕有 accessibility label。
- [ ] 相關單元測試與 UI tests 更新並通過；`app/GoFly/scripts/check.sh` 通過。
- [ ] 不改命令、送點、ACK、背景執行語意（`app/GoFly/ARCHITECTURE.md` 不變量）；不宣稱實機驗證。

## 執行紀錄

### 2026-10-29 執行紀錄（Luna）

- 目前 B 區 fixture screenshots：B1、B2、B5、B7、B10 Light／Dark，位置在 `work/gofly-ios-figma04/screenshots/`；Dark B1 及其他地圖色彩抽查亦記於票 05。通用 Toast 浮層可見於 B7／B10。
- B11 Dark Figma frame `322:40470` 的只讀渲染實際存在，與票單「B11 無 Dark 設計」的文字衝突；manifest 與本票只記為待釐清衝突，不視為已核准設計，沒有修改 Figma。
- B3／B4 搜尋、B6／B8／B9／B11 命令與恢復狀態仍缺 deterministic fixture；B 區其餘 frame 尚未逐一截圖比對，維持 `in progress`。地圖原生圖資無法逐物件設成 Figma 色票；未做實機驗證。
- 使用者追加的 B1 Dark 截圖回饋（`work/gofly-ios-figma04/device-feedback/B1-dark-tabbar-map.webp`）：SearchBar、StatusPill、貼上圖示顏色與 Figma Dark B1 渲染不一致。列為本票待修項；須待票 01a、01、02、03–05 依序完成後，在本票按 Figma 共用元件／Dark color token 修正並以 B1 Dark 截圖複核。
- 使用者追加 B 區 frame 比對項（尚待本票實作／重截）：B2 Light 貼上圖示顏色；B2 Dark 最愛地點第二列下方移除 divider、copy icon 顏色與「查看全部」按鈕樣式；B5 LocationCard 排版／間距及左側 primary button；B7 Toast title 與說明各限制為兩行、action button 更靠右；B10 Toast action button 背景色。以 `work/gofly-ios-figma04/figma/` 同名 frame 渲染為準。
