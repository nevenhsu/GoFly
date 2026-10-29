# 06: A：啟動與首次引導

**What to build:** Figma A 區所有 frame（啟動畫面、首次引導、VPN 通道步驟、連線說明、VPN 失敗與 Mac Setup 異常）在 App 完整對齊，含 Hero icon（非白底）、步驟圓點數字（白字）、StatusPill 與 error toast。

**Blocked by:** 05.

**Status:** in progress

**Assignee hint:** Luna

- [ ] A 區每張 frame 都有對應的 UI test fixture 與 Light／Dark 截圖，逐張比對 Figma。
- [ ] 啟動畫面中央 App icon 維持品牌白底；其他 Hero icon 底色為中性 control 色。
- [ ] 首次引導流程（定位權限 → VPN 通道 → 完成）可從頭走完且畫面與 Figma 一致。
- [ ] 本票涵蓋的畫面中，所有圖示都經 `GoFlyIcon` 使用 Figma『0 · 共用元件（Icon）』匯出的資產（依票 03 對照表），不再出現 SF Symbol；尺寸、顏色 token 與 Figma 一致；對照表沒有的 icon 列入『執行紀錄』回報。
- [ ] 本票涵蓋的所有 Toast／Banner 都以懸浮方式顯示（疊在內容上方、含浮層陰影、不推動版面），依票 04 的共用 Toast overlay 容器。
- [ ] **層級（實機回饋）**：Light 整頁背景為 `canvas`（`#EEEEF3`）、步驟清單與卡片為 `surface/card`（`#FBFBFD`），不得用灰色 control 當清單底（目前層級顛倒）；Dark 為 `#0B0B0D`／`#1A1A1C`；R02、R03、R04、R04.a、R05–R08 全部照此檢查。
- [ ] **R05 連線說明精簡版**（Figma R05 渲染為準）：導覽列『返回／連線說明』；一張步驟卡三列單行（1 下載 LocalDevVPN ›、2 開啟 LocalDevVPN ›、3 點 Connect；藍圓白字數字；前兩列右側 chevron 保留原連結功能）；下方『仍然無法連線？』卡片一則提示（確認連著 Wi‑Fi，在 LocalDevVPN 中斷後重新連接，再回來檢查）。刪除大標題、副標、各步驟說明小字、『本機網路權限』列與底部『返回並檢查連線』主按鈕；導覽列返回後仍自動重新檢查連線；三語文案與無用字串、UI test 辨識碼同步清理。移除『本機網路權限』入口後若無其他路徑開啟系統設定，回報使用者決定，不自行保留舊列。
- [ ] 首次引導的錯誤通知為懸浮 Toast（疊在內容上方、不推動標題與清單）；VPN 檢查成功後不顯示 success Toast，沿用再次檢查並自動進入 B1，首次進入時 sheet 收合。
- [ ] **截圖驗證（必做，沒有截圖視為未完成）**：用 01a 的 fixture（不需網路、VPN、真機）對本票涵蓋的每一張 frame、Light 與 Dark 各截一張，存到 `work/gofly-ios-figma04/screenshots/`，並與 `work/gofly-ios-figma04/figma/` 的同名 Figma 截圖並排比對：無破版、無文字截斷、無缺漏元素、顏色與層級一致。把每張的結論（一致／有差異＋原因）與檔案路徑寫入票尾『執行紀錄』；到不了的 frame 如實列出，不略過。
- [ ] 最大 Dynamic Type 與 Reduce Motion 下仍可操作；互動元件觸控命中範圍 ≥ 44 × 44 pt；每個圖示按鈕有 accessibility label。
- [ ] 相關單元測試與 UI tests 更新並通過；`app/GoFly/scripts/check.sh` 通過。
- [ ] 不改命令、送點、ACK、背景執行語意（`app/GoFly/ARCHITECTURE.md` 不變量）；不宣稱實機驗證。

## 執行紀錄

### 2026-10-29 執行紀錄（Luna）

- R02／R03／R04／R04.a／R05／R07／R08 Light／Dark fixtures 已有截圖，另有成功後自動進 B1 收合的 `R04-auto-B1-light.png`、`R04-auto-B1-dark.png`；截圖及對照總覽在 `work/gofly-ios-figma04/screenshots/` 與 `index.html`。R05 已精簡三語步驟與提示卡；返回仍觸發既有 VPN 重查。R04 成功後無 success Toast，依使用者確認直接進 B1 收合。
- R04 標題先前比 Figma 下移約 85 pt 且字級／字重不符；已移除多餘垂直留白並對齊 Figma `121:51267` 的 x=16、y=130、361×39 pt、28 pt Semibold。實作由共享 `GoFlyFont.display` 提供；接續 02 票會統一改為 `Font.system` text-style API 並保留 Figma 的 28 pt Semibold 對應。Light／Dark 標題位置由 `testR04TypographyAndPositionMatchFigmaInBothAppearances` 驗證，最新截圖為 `R04-light.png`、`R04-dark.png`。
- R04 `已連線` 靜態 Figma 狀態與自動 B1 行為分開：`R04-connected-light.png`／`R04-connected-dark.png` 是連線狀態截圖；`R04-auto-B1-*` 驗證實際成功導覽。Figma 靜態 frame 仍有檢查 CTA，未修改 Figma。
- R05 移除「本機網路權限」列後，程式中未找到替代的直接系統設定入口，保留為產品待決事項。R06 不在目前 frame catalog；A 區全量逐 frame／最大 Dynamic Type 驗收仍未完成，維持 `in progress`。未做實機驗證。
