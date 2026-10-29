# 01a: UI 截圖驗證工具（繞過模擬器沒有網路、VPN、真機的限制）

**What to build:** 建立只存在於 Debug＋模擬器的 fixture 層，讓 Figma A–F 每一張 frame 的狀態都能在**沒有網路、沒有 VPN、沒有真機**的模擬器上直接開到、截圖、與 Figma 比對。沿用 repo 既有 `GoFlyUITestOverrides` 的模式（只在 `DEBUG && targetEnvironment(simulator)` 編譯，Release 與真機 build 為無作用版本，正式參數不可選取測試狀態）。目前已有的旗標只涵蓋 VPN 不可達（`-gofly-ui-unreachable`）、Wi‑Fi 連線／中斷、各種 store 與偏好；本票補齊其餘無法在模擬器自然出現的狀態。

**Blocked by:** None (can start immediately).

**Status:** ready-for-agent

**Assignee hint:** Luna

- [ ] 新增單一入口旗標（例如 `-gofly-ui-frame <FrameID> -gofly-ui-appearance light|dark`），直接啟動到對應 Figma frame 的狀態；FrameID 與 Figma frame 名稱一致（A 區 R01…、B1–B11、C1–C4、D1–D23、E1–E7、F1–F9 含 F1.a、F1.b、F6.a）。
- [ ] Fixture 提供下列離線、可預期的替身（僅 fixture 模式使用，不改正式程式路徑）：裝置服務與 session 狀態（已停止、啟動中、運行中、暫停、錯誤、停止失敗、重置成功）、VPN 通道可用／不可用、Wi‑Fi 連線／中斷、定位權限（使用期間／拒絕／尚未決定）與真實定位、模擬位置、MapKit 搜尋與地點解析（固定結果）、路線規劃器（成功、`planningFailed`、重排後成功）、最愛地點／最愛路線／匯入 GPX 的種子資料、背景運行時間。
- [ ] 模擬器沒有網路時 MapKit 底圖是空白：fixture 模式以本地固定底圖（與 Figma `Map / Base` 的 Light／Dark 色票一致、滿版）取代底圖，讓含地圖的畫面可以截圖比對；路線線、Pin、箭頭仍用正式繪製程式。
- [ ] 提供一個 UI test（例如 `GoFlyFigmaFrameScreenshots`）一次產生全部 frame × Light／Dark 的截圖，輸出到 `work/gofly-ios-figma04/screenshots/<frame>-<light|dark>.png`，並寫入 `manifest.json`（frame、主題、路徑、使用的 fixture 旗標）。`work/` 不進版控。
- [ ] 提供 Figma 對照圖的取得方式（以 Figma Console `figma_capture_screenshot` 讀取同名 frame，輸出到 `work/gofly-ios-figma04/figma/`），並寫成腳本或說明，後續每票的比對都用這兩個資料夾。
- [ ] 驗證不外洩：Release 與真機（unsigned device）build 都能編譯，且不含這些旗標的實作（以單元測試或 build 檢查證明）；`check.sh` 通過。
- [ ] 本票結束時，已知 Figma 有、但 fixture 暫時到不了的 frame 列成清單寫入『執行紀錄』，不得略過不報。
- [ ] 不改命令、送點、ACK、背景執行語意；fixture 不得呼叫真實裝置 API、不要求網路或 VPN。

## 執行紀錄

（執行者在此記錄：日期、完成項、frame 對照表、到不了的 frame 與原因。）
