# 11: 路線：無法規劃時「修正」自動調整順序

**What to build:** 路線規劃失敗（`planningFailed`）的 warning toast 按鈕由「重試」改為「修正」。按下後系統自動重新安排**全部**地點的順序（含起點，使用者已決定），以能成功規劃為目標重新規劃：找到可成功的順序就採用並更新清單與地圖預覽；找不到就保留原順序與 toast，提示仍無法規劃。過程中按鈕顯示進行中、禁止重入，可被後續編輯取消。

**Blocked by:** 10, 00.

**Status:** ready-for-agent

**Assignee hint:** Luna

- [ ] 失敗 toast 在 Light／Dark 與 Figma D8 一致，按鈕文字為「修正」（英文 Fix）；`IssueCatalog` 與本地化字串同步，原「重試」文案只保留給連線類錯誤。
- [ ] 修正的搜尋策略有上限（例如固定地點數上限與逐段規劃次數上限），在 27 個地點上限內不會長時間卡住；策略與上限寫在票尾決策紀錄。
- [ ] 成功時清單順序、角色（起點／停靠點／終點）、地圖預覽路線都已更新，且可再用既有拖曳或『反轉順序』微調；失敗時原草稿完全不變。
- [ ] 核心單元測試以假的規劃器覆蓋：原順序失敗但某順序成功、全部失敗、規劃中被編輯取消、地點數 2／3／27。
- [ ] UI test：D8 情境按『修正』的成功與失敗各一條。
- [ ] 本票涵蓋的所有 Toast／Banner 都以懸浮方式顯示（疊在內容上方、含浮層陰影、不推動版面），依票 04 的共用 Toast overlay 容器。
- [ ] **地圖一律滿版**：所有出現地圖的畫面，地圖都填滿整個螢幕（延伸到狀態列、Dynamic Island、底部 Tab Bar 與 home indicator 後方，忽略四邊 safe area），面板、Sheet、Tab Bar、浮動控制項與狀態列疊在地圖上方；Sheet 展開／收合、鍵盤出現、旋轉與切換淺深色時地圖不縮放、不留空白邊或色帶，地圖的有效中心與右側控制鈕位置依可見區域（扣除 Sheet）計算。
- [ ] 本票涵蓋的畫面中，所有圖示都經 `GoFlyIcon` 使用 Figma『0 · 共用元件（Icon）』匯出的資產（依票 03 對照表），不再出現 SF Symbol；尺寸、顏色 token 與 Figma 一致；對照表沒有的 icon 列入『執行紀錄』回報。
- [ ] **截圖驗證（必做，沒有截圖視為未完成）**：用 01a 的 fixture（不需網路、VPN、真機）對本票涵蓋的每一張 frame、Light 與 Dark 各截一張，存到 `work/gofly-ios-figma04/screenshots/`，並與 `work/gofly-ios-figma04/figma/` 的同名 Figma 截圖並排比對：無破版、無文字截斷、無缺漏元素、顏色與層級一致。把每張的結論（一致／有差異＋原因）與檔案路徑寫入票尾『執行紀錄』；到不了的 frame 如實列出，不略過。
- [ ] 最大 Dynamic Type 與 Reduce Motion 下仍可操作；互動元件觸控命中範圍 ≥ 44 × 44 pt；每個圖示按鈕有 accessibility label。
- [ ] 相關單元測試與 UI tests 更新並通過；`app/GoFly/scripts/check.sh` 通過。
- [ ] 不改命令、送點、ACK、背景執行語意（`app/GoFly/ARCHITECTURE.md` 不變量）；不宣稱實機驗證。

## 執行紀錄

（執行者在此記錄：日期、完成項、截圖路徑、未完成與原因、決策。）
