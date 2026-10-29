# 06: A：啟動與首次引導

**What to build:** Figma A 區所有 frame（啟動畫面、首次引導、VPN 通道步驟、連線說明、VPN 失敗與 Mac Setup 異常）在 App 完整對齊，含 Hero icon（非白底）、步驟圓點數字（白字）、StatusPill 與 error toast。

**Blocked by:** 05.

**Status:** ready-for-agent

**Assignee hint:** Luna

- [ ] A 區每張 frame 都有對應的 UI test fixture 與 Light／Dark 截圖，逐張比對 Figma。
- [ ] 啟動畫面中央 App icon 維持品牌白底；其他 Hero icon 底色為中性 control 色。
- [ ] 首次引導流程（定位權限 → VPN 通道 → 完成）可從頭走完且畫面與 Figma 一致。
- [ ] 本票涵蓋的畫面中，所有圖示都經 `GoFlyIcon` 使用 Figma『0 · 共用元件（Icon）』匯出的資產（依票 03 對照表），不再出現 SF Symbol；尺寸、顏色 token 與 Figma 一致；對照表沒有的 icon 列入『執行紀錄』回報。
- [ ] **截圖驗證（必做，沒有截圖視為未完成）**：用 01a 的 fixture（不需網路、VPN、真機）對本票涵蓋的每一張 frame、Light 與 Dark 各截一張，存到 `work/gofly-ios-figma04/screenshots/`，並與 `work/gofly-ios-figma04/figma/` 的同名 Figma 截圖並排比對：無破版、無文字截斷、無缺漏元素、顏色與層級一致。把每張的結論（一致／有差異＋原因）與檔案路徑寫入票尾『執行紀錄』；到不了的 frame 如實列出，不略過。
- [ ] 最大 Dynamic Type 與 Reduce Motion 下仍可操作；互動元件觸控命中範圍 ≥ 44 × 44 pt；每個圖示按鈕有 accessibility label。
- [ ] 相關單元測試與 UI tests 更新並通過；`app/GoFly/scripts/check.sh` 通過。
- [ ] 不改命令、送點、ACK、背景執行語意（`app/GoFly/ARCHITECTURE.md` 不變量）；不宣稱實機驗證。

## 執行紀錄

（執行者在此記錄：日期、完成項、截圖路徑、未完成與原因、決策。）
