# 05: 地圖與面板共用元件

**What to build:** LocationCard（Route layout，底色比 sheet 亮一階）、`Top / 執行指示`（Active／Paused，底色與下方執行面板相同的實色）、MapControls 44 pt（locate）、Map Pin（含確認／Go 按鈕：primary 線條、白字白箭頭）、Map 底圖色票（Light／Dark）、Tab Bar（三格等寬、選中態）、Sheet 頂部 grabber 與標題列、清單列（搜尋結果、最愛、路線檔、點位、路線停靠點的輸入／選中／拖曳態）、NavBar、原生鍵盤與系統分享 sheet 的 Dark 配色（按鈕與 list 比 sheet 亮兩階）。

**Blocked by:** 03, 04.

**Status:** in progress

**Assignee hint:** Luna

- [ ] 以上元件逐一與 Figma 共用元件板（Light／Dark）並排截圖比對並通過。
- [ ] 路線停靠點選中列：primary 邊線、底色為中性（Light＝card、Dark＝active），不使用 primary 底色。
- [ ] 清單外框（Sheet 上的 list）在 Dark 使用 control 色，比 Sheet 亮兩階。
- [ ] GPX／最愛／搜尋清單列沿用同一個列元件，不再各自手刻。
- [ ] **地圖一律滿版**：所有出現地圖的畫面，地圖都填滿整個螢幕（延伸到狀態列、Dynamic Island、底部 Tab Bar 與 home indicator 後方，忽略四邊 safe area），面板、Sheet、Tab Bar、浮動控制項與狀態列疊在地圖上方；Sheet 展開／收合、鍵盤出現、旋轉與切換淺深色時地圖不縮放、不留空白邊或色帶，地圖的有效中心與右側控制鈕位置依可見區域（扣除 Sheet）計算。
- [ ] 本票涵蓋的畫面中，所有圖示都經 `GoFlyIcon` 使用 Figma『0 · 共用元件（Icon）』匯出的資產（依票 03 對照表），不再出現 SF Symbol；尺寸、顏色 token 與 Figma 一致；對照表沒有的 icon 列入『執行紀錄』回報。
- [ ] **Tab Bar 與 panel 同色同透明度**（實機回饋）：Tab Bar 與上方 bottom sheet／panel 使用同一個色彩 token 與同一個不透明度（Figma `surface/overlay/sheet`、`tab-panel`；Dark `#1A1A1C` @ 95%、Light 依 Figma），兩者視覺連成同一塊，交界無色差、地圖不從 Tab Bar 透出；頂部細線與選中態依 Figma。
- [ ] **Dark 地圖為黑色主題**（實機回饋）：Dark 外觀下 MapKit 使用深色樣式並壓低亮度與飽和度（深色＋muted、淡化 POI 與標註），接近 Figma Dark `Map / Base`（`map/canvas` `#131315` 與 `color/map/*`）；先查出實機 Dark 時沒生效的根因（偏好設定外觀與系統外觀不一致、地圖元件沒收到 colorScheme、或只有 fixture 底圖套用），不要只在 fixture 補色；切換外觀偏好時地圖立即跟著變；Light 不變。
- [ ] LocationCard 底色比 Sheet 亮一階（Dark `#232326` @ 95%，Figma 新 token `surface/overlay/location-card`）；`Top / 執行指示` 底色與下方執行面板相同的實色。
- [ ] **截圖驗證（必做，沒有截圖視為未完成）**：用 01a 的 fixture（不需網路、VPN、真機）對本票涵蓋的每一張 frame、Light 與 Dark 各截一張，存到 `work/gofly-ios-figma04/screenshots/`，並與 `work/gofly-ios-figma04/figma/` 的同名 Figma 截圖並排比對：無破版、無文字截斷、無缺漏元素、顏色與層級一致。把每張的結論（一致／有差異＋原因）與檔案路徑寫入票尾『執行紀錄』；到不了的 frame 如實列出，不略過。
- [ ] 最大 Dynamic Type 與 Reduce Motion 下仍可操作；互動元件觸控命中範圍 ≥ 44 × 44 pt；每個圖示按鈕有 accessibility label。
- [ ] 相關單元測試與 UI tests 更新並通過；`app/GoFly/scripts/check.sh` 通過。
- [ ] 不改命令、送點、ACK、背景執行語意（`app/GoFly/ARCHITECTURE.md` 不變量）；不宣稱實機驗證。

## 執行紀錄

### 2026-10-29 執行紀錄（Luna）

- Tab Bar 與 BottomSheet 改共用 `surfaceOverlaySheet` token、95% alpha；MapKit 外觀改由 App 的外觀偏好即時設定，Dark 使用 muted／flat 標準地圖、移除 POI，Light 保留標準外觀；滿版地圖、路線／Pin／箭頭／標註仍走語意色彩。
- 抽查 B1、B5、D1、D6、E1 Light／Dark 截圖位於 `work/gofly-ios-figma04/screenshots/`；同名 Figma 參考位於 `work/gofly-ios-figma04/figma/`，並排總覽 `work/gofly-ios-figma04/screenshots/index.html`。Tab／面板同 token 與透明度一致；MapKit 原生地物無法逐一套用 Figma 的 `color/map/*`，Dark 地圖僅為低飽和近黑近似。
- 未完成共用按鈕／面板所有 variants 與 A–F 全 frame 驗收；受 01a fixture 不足影響，維持 `in progress`。Figma Map Base 是自繪色票，與 MapKit 原生圖資有能力差異；未修改 Figma、未做實機驗證。
