# iOS App 對齊 Figma 04（含 Route Mode 與設定 UX 更新）

視覺唯一準據：Figma 04 · iOS Redesign（`121:50359`）的 Light／Dark 渲染；本輪另含三項 UX 決定（2026-10-29）：
1. 路線『＋ 新增停靠點』新欄位加在最後當終點。
2. 無法規劃路線的 toast 按鈕『重試』改『修正』，系統自動調整**全部**地點順序（含起點）重新規劃。
3. 設定服務卡只有一顆按鈕；重置成功後文字變『啟動模擬』，導覽列下方懸浮出現 success toast（『已重置連線』／『可以重新啟動模擬』）。

補充（2026-10-29）：R04 VPN 檢查成功後沿用再次確認並自動進入 B1，sheet 收合；此成功不顯示 Toast。共用 Toast 視覺仍更新依 Figma `Light · 0 · 共用元件 / STATUS · BANNER / SNACKBAR / PILL` 的 Light／Dark 渲染。

依賴：00（Figma，Claude）、01a（截圖驗證工具）→ 01 → 02 → 03／04 → 05 → 06–09、12–16、18（互不依賴，照 A→F 順序做）→ 10 → 11；16 → 17；全部 → 19。
一票一檔，狀態寫在各票的 Status 與『執行紀錄』。Handoff prompt：`.scratch/prompts/05-ios-figma04-luna.md`。

| # | 票 | Blocked by |
| --- | --- | --- |
| 00 | Figma 同步新 UX（Claude） | — |
| 01a | UI 截圖驗證工具（繞過無網路／VPN／真機） | — |
| 01 | Theme 色彩 token | 01a |
| 02 | Typography | 01 |
| 03 | 按鈕、Icon Button、輸入欄 | 01, 02 |
| 04 | 狀態回饋元件 | 01, 02 |
| 05 | 地圖與面板元件 | 03, 04 |
| 06 | A 啟動與首次引導 | 05 |
| 07 | B 地圖首頁／搜尋／地點 sheet／瞬移 | 05 |
| 08 | C 最愛地點 | 05 |
| 09 | D 路線規劃視覺（D1–D5、D2.a） | 05 |
| 10 | 新增停靠點加在最後當終點 | 09, 00 |
| 11 | 無法規劃時『修正』 | 10, 00 |
| 12 | D 執行／中斷／速度 | 05 |
| 13 | D GPX 匯入匯出 | 05 |
| 14 | D 最愛路線與檢視路線 | 05 |
| 15 | E 搖桿與漫步 | 05 |
| 16 | F 設定首頁視覺 | 05 |
| 17 | 服務卡單一按鈕＋重置成功 toast | 16, 00 |
| 18 | F 設定子頁 | 05 |
| 19 | 全流程回歸與文件 | 06–18 |

另：**地圖一律滿版**（2026-10-29 使用者指示）——所有含地圖的票（05、07、09–15）都有此驗收項。

另：**圖示一律匯出成資產、不用 SF Symbol**（Figma『0 · 共用元件（Icon）』目前渲染 53 個 icon；票單原記 52，票 03 已同步，建立 `GoFlyIcon`，05–18 驗收）。

另：**每張票完成都要截圖驗證**（01a 的 fixture，不需網路／VPN／真機；Light 與 Dark，與 Figma 並排比對）。

另：實機截圖回饋（B1 Dark Tab Bar／黑色地圖、R04 Light 層級、R05 精簡、Toast 懸浮）已併入票 05、06、07；執行用 prompt 見 `.scratch/prompts/06-ios-device-feedback-luna.md`，整體逐頁更新用 `.scratch/prompts/07-ios-figma04-page-by-page-luna.md`。

另：**字型一律 `Font.system`；圖示一律使用 Figma『0 · 共用元件（Icon）』**（票 02、03 建立並檢查，05–18 驗收）。
