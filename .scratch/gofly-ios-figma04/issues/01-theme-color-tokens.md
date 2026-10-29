# 01: App Theme 色彩 token 對齊 Figma Light／Dark

**What to build:** App 以單一語意色彩表（canvas、surface／card／control／active／disabled、overlay、text、icon、line、action、status、map）取代 `GoFlyGrayScale` 自訂灰階與散落的系統色。Light／Dark 值以 Figma Variables 為準（`GoFly iOS / Light Theme`、`Dark Theme`、`Common Color`）；`docs/IOS-COLOR-SCHEME.json` 是快照，開工先與 Figma 讀回值核對，不一致時回報、不自行決定。外觀偏好（系統／淺／深）維持有效。

**Blocked by:** 01a.

**Status:** ready-for-agent

**Assignee hint:** Luna

- [ ] Light 與 Dark 的每個語意色都有對應 token，名稱與 Figma 變數名稱可一對一對照（`color/surface/card` ↔ 對應 Swift 名稱，對照表寫入票尾）。
- [ ] Dark 階梯：畫面底 `#0B0B0D`、Tab／Sheet／info card `#1A1A1C`、Sheet 上的按鈕與 list `#2C2C2F`、active／focused `#48484D`；Light 為 `#EEEEF3`／`#FBFBFD`／`#DEDEE4`／`#B9B9BF`。
- [ ] 舊的 `GoFlyGrayScale` 字面值與 `Color(uiColor: .system…)` 在 UI 層沒有殘留（地圖原生元件與系統控制例外，須列清單）。
- [ ] 新增單元測試：每個 token 在 Light／Dark 的值等於 `IOS-COLOR-SCHEME.json`；外觀偏好切換即時生效。
- [ ] 元件畫面此票不要求逐張對齊；本票只建立 token 並讓 App 在兩個外觀下可正常運作。
- [ ] **截圖驗證（必做，沒有截圖視為未完成）**：用 01a 的 fixture（不需網路、VPN、真機）對本票涵蓋的每一張 frame、Light 與 Dark 各截一張，存到 `work/gofly-ios-figma04/screenshots/`，並與 `work/gofly-ios-figma04/figma/` 的同名 Figma 截圖並排比對：無破版、無文字截斷、無缺漏元素、顏色與層級一致。把每張的結論（一致／有差異＋原因）與檔案路徑寫入票尾『執行紀錄』；到不了的 frame 如實列出，不略過。
- [ ] 最大 Dynamic Type 與 Reduce Motion 下仍可操作；互動元件觸控命中範圍 ≥ 44 × 44 pt；每個圖示按鈕有 accessibility label。
- [ ] 相關單元測試與 UI tests 更新並通過；`app/GoFly/scripts/check.sh` 通過。
- [ ] 不改命令、送點、ACK、背景執行語意（`app/GoFly/ARCHITECTURE.md` 不變量）；不宣稱實機驗證。

## 執行紀錄

（執行者在此記錄：日期、完成項、截圖路徑、未完成與原因、決策。）
