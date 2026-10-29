# 07: B：地圖首頁、搜尋、地點 sheet、瞬移

**What to build:** Figma B 區所有 frame：瞬移首頁與收合 sheet、模擬中 pill、全螢幕搜尋（B3 空輸入、B4 座標與結果、原生鍵盤）、地點 sheet 與 LocationCard、Pin 與 Go、瞬移失敗／中斷／Wi‑Fi／連接中的 toast 與 pill。

**Blocked by:** 05.

**Status:** ready-for-agent

**Assignee hint:** Luna

- [ ] B 區每張 frame 對應 fixture 並完成 Light／Dark 比對。
- [ ] 全螢幕搜尋進入時隱藏地圖、pill、tabs；鍵盤出現時鍵盤配色符合 Dark 規格（鍵盤底為 card 級、按鍵為 control 級、確認鍵白字）。
- [ ] Toast 與 pill 的錯誤、警告、成功三種語意不混用；B11 連接中只有 Light 設計，Dark 依 Light 結構並標註缺口。
- [ ] **地圖一律滿版**：所有出現地圖的畫面，地圖都填滿整個螢幕（延伸到狀態列、Dynamic Island、底部 Tab Bar 與 home indicator 後方，忽略四邊 safe area），面板、Sheet、Tab Bar、浮動控制項與狀態列疊在地圖上方；Sheet 展開／收合、鍵盤出現、旋轉與切換淺深色時地圖不縮放、不留空白邊或色帶，地圖的有效中心與右側控制鈕位置依可見區域（扣除 Sheet）計算。
- [ ] 本票涵蓋的畫面中，所有圖示都經 `GoFlyIcon` 使用 Figma『0 · 共用元件（Icon）』匯出的資產（依票 03 對照表），不再出現 SF Symbol；尺寸、顏色 token 與 Figma 一致；對照表沒有的 icon 列入『執行紀錄』回報。
- [ ] **截圖驗證（必做，沒有截圖視為未完成）**：用 01a 的 fixture（不需網路、VPN、真機）對本票涵蓋的每一張 frame、Light 與 Dark 各截一張，存到 `work/gofly-ios-figma04/screenshots/`，並與 `work/gofly-ios-figma04/figma/` 的同名 Figma 截圖並排比對：無破版、無文字截斷、無缺漏元素、顏色與層級一致。把每張的結論（一致／有差異＋原因）與檔案路徑寫入票尾『執行紀錄』；到不了的 frame 如實列出，不略過。
- [ ] 最大 Dynamic Type 與 Reduce Motion 下仍可操作；互動元件觸控命中範圍 ≥ 44 × 44 pt；每個圖示按鈕有 accessibility label。
- [ ] 相關單元測試與 UI tests 更新並通過；`app/GoFly/scripts/check.sh` 通過。
- [ ] 不改命令、送點、ACK、背景執行語意（`app/GoFly/ARCHITECTURE.md` 不變量）；不宣稱實機驗證。

## 執行紀錄

（執行者在此記錄：日期、完成項、截圖路徑、未完成與原因、決策。）
