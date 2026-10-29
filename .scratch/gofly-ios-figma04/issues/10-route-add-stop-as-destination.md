# 10: 路線：新增停靠點加在最後當終點

**What to build:** 使用者按『＋ 新增停靠點』（規劃面板與『全部點位』清單頁兩處）時，新增一個空的輸入欄位到清單**最後**，成為新的終點；原本的終點降為最後一個停靠點，原值不變。選取該空欄位並可立刻搜尋／選點回填。其他點的順序、起點與草稿持久化行為不變。

**Blocked by:** 09, 00.

**Status:** ready-for-agent

**Assignee hint:** Luna

- [ ] 有起點與終點的草稿按新增後，清單順序為 起點、…、原終點、新空欄位；新空欄位的角色標示為『終點』，原終點標示為『停靠點 N』。
- [ ] 只有起點時按新增（nodes < 2）行為維持：先補出終點欄位；已達 27 個地點上限時按鈕停用並保留 accessibility hint。
- [ ] 新欄位為空時不觸發規劃、不顯示錯誤；回填後才重新規劃預覽路線。
- [ ] 核心單元測試覆蓋：插入位置、角色重算、上限、持久化與復原往返、`reverseNodes`／`moveNode` 與新欄位互動。
- [ ] UI test：規劃面板與全部點位頁各一條新增流程；`docs/ROUTE-MODE-TASKS.md` 與 `docs/IOS-UI-DESIGN.md` 的『插在終點前』敘述全部更新。
- [ ] **地圖一律滿版**：所有出現地圖的畫面，地圖都填滿整個螢幕（延伸到狀態列、Dynamic Island、底部 Tab Bar 與 home indicator 後方，忽略四邊 safe area），面板、Sheet、Tab Bar、浮動控制項與狀態列疊在地圖上方；Sheet 展開／收合、鍵盤出現、旋轉與切換淺深色時地圖不縮放、不留空白邊或色帶，地圖的有效中心與右側控制鈕位置依可見區域（扣除 Sheet）計算。
- [ ] 本票涵蓋的畫面中，所有圖示都經 `GoFlyIcon` 使用 Figma『0 · 共用元件（Icon）』匯出的資產（依票 03 對照表），不再出現 SF Symbol；尺寸、顏色 token 與 Figma 一致；對照表沒有的 icon 列入『執行紀錄』回報。
- [ ] **截圖驗證（必做，沒有截圖視為未完成）**：用 01a 的 fixture（不需網路、VPN、真機）對本票涵蓋的每一張 frame、Light 與 Dark 各截一張，存到 `work/gofly-ios-figma04/screenshots/`，並與 `work/gofly-ios-figma04/figma/` 的同名 Figma 截圖並排比對：無破版、無文字截斷、無缺漏元素、顏色與層級一致。把每張的結論（一致／有差異＋原因）與檔案路徑寫入票尾『執行紀錄』；到不了的 frame 如實列出，不略過。
- [ ] 最大 Dynamic Type 與 Reduce Motion 下仍可操作；互動元件觸控命中範圍 ≥ 44 × 44 pt；每個圖示按鈕有 accessibility label。
- [ ] 相關單元測試與 UI tests 更新並通過；`app/GoFly/scripts/check.sh` 通過。
- [ ] 不改命令、送點、ACK、背景執行語意（`app/GoFly/ARCHITECTURE.md` 不變量）；不宣稱實機驗證。

## 執行紀錄

（執行者在此記錄：日期、完成項、截圖路徑、未完成與原因、決策。）
