# 任務：iOS 實機截圖回饋修正（B1 Dark、R04 Light、R05 精簡）（給 Luna）

你在 repo `/Users/neven/Documents/projects/ianygo` 工作，對象是 iOS App `app/GoFly`。使用者在實機看到三處與 Figma 04 不一致，請修正。這兩項屬於 `.scratch/gofly-ios-figma04/issues/` 的票 01（色彩 token）、05（Tab Bar／面板）、06（A 區）、07（B 區）範圍：若那幾票已經做完，就在現有 token 上修正；若還沒做，併入該票並在『執行紀錄』註明。先讀 `AGENTS.md` 與 `.scratch/prompts/05-ios-figma04-luna.md` 的共同規則（只改 UI、不改命令／送點／背景語意、不 commit、不安裝到手機、不跑 Prettier）。

視覺準據：Figma 04（`121:50359`）渲染畫面。只讀 Figma，不要修改。

## 實機截圖（本機，已 git ignore）

- `work/gofly-ios-figma04/device-feedback/B1-dark-tabbar-map.webp`
- `work/gofly-ios-figma04/device-feedback/R04-light-background-list.webp`

## 問題 1：B1 Dark（瞬移首頁，深色）

Figma 對照：Dark section 的 `B1 · 地圖首頁…`（`Dark · B1`），共用元件 `Dark · TabBar / 瞬移・路線・搖桿（等寬）`、`Dark · BottomSheet / 收合`。

截圖現象與要求：

1. **Tab Bar 背景要與上方 panel（bottom sheet）一致**：目前 Tab Bar 比 panel 更暗，且半透明、底下地圖的文字與圖示會透出來（「搖桿」旁可見地圖標註）。要求 Tab Bar 與 panel 使用同一個色彩 token 與同一個不透明度（Figma：`surface/overlay/sheet`、`surface/overlay/tab-panel`，Dark 值 `#1A1A1C` @ 95%；兩者視覺上要連成同一塊面板，交界不可有色差或透出差異）。Light 同步檢查（Light 值 `#F9F9F9` 系，以 Figma 為準）。Tab Bar 頂部細線、選中態依 Figma 共用元件。
2. **地圖改為黑色（Dark）主題**：Dark 外觀下地圖仍是淺色（米白底、淺色道路），與 Figma Dark `Map / Base`（`map/canvas` `#131315`，建物、公園、水域、道路對照 `Dark · Color Scheme` 的 `color/map/*`）差很多。要求 Dark 外觀時 MapKit 使用深色樣式並壓低亮度與飽和度（例如深色＋muted 的標準地圖設定、減少或淡化 POI 與標註），整體接近 Figma 的近黑地圖；Light 外觀不變。App 已有 `applyColorScheme`（`overrideUserInterfaceStyle`）與離線 fixture 底圖，請先查為何實機 Dark 時沒有生效（偏好設定的外觀與系統外觀不一致、地圖元件沒收到 colorScheme、或只有 fixture 底圖套用），修正根因，不要只在 fixture 補色。
3. 路線、Pin、箭頭、地圖標註在深色地圖上仍要清楚可讀（箭頭與標註顏色依 Dark token）。

驗收：
- [ ] Dark：Tab Bar 與 panel 同色同透明度，連續無接縫，地圖不透出；Light 也一致。
- [ ] Dark：地圖為深色樣式，與 Figma `Dark · B1` 並排比對視覺一致（近黑底、低飽和）；切換偏好設定的外觀（系統／淺色／深色）時地圖立即跟著變。
- [ ] 其他有地圖的 Dark 畫面（B、D、E 區）同步受益，截圖抽查至少 B1、B5、D1、D6、E1。

## 問題 2：R04 Light（首次引導 3／3，連接 VPN 通道）

Figma 對照：Light section 的 `R04 · 首次引導 3／3 · 設定 VPN 通道`、`R04.a`、`R05`（同一組步驟清單樣式）；色票 `Light · Color Scheme`。

截圖現象：整頁背景是近白（`#FBFBFD` 級，等於 card 色），而「連線步驟」清單卡片是灰色（約 control 級），層級顛倒；Figma Light 為 **背景 canvas `#EEEEF3`、清單／卡片 card `#FBFBFD`**（canvas → card → control → active）。

要求：
1. 頁面背景改用 `canvas`（Light `#EEEEF3`），步驟清單卡片改用 `surface/card`（`#FBFBFD`），不使用灰色 control 當清單底；步驟分隔線用 `line/separator`。
2. 同一個引導流程的其他頁（R02、R03、R05、R06–R08、啟動前的引導頁）與 Figma `已連線` 狀態樣式也按 Light 檢查：背景一律 canvas、卡片一律 card、success 狀態使用 `surface/status/success` 與 `line/status/success`，主要按鈕 primary 底白字、次要按鈕 control 底。App 中 VPN 檢查成功後沿用再次確認並自動進入 B1 收合 sheet，不顯示 success Toast。
3. Dark 也各看一次（Dark 背景 `#0B0B0D`、清單 `#1A1A1C`），確認沒有同類顛倒。

驗收：
- [ ] Light R04 靜態畫面背景為 canvas、清單為 card，與 Figma 並排一致；另截 R04 成功後自動進 B1 收合 sheet 的 App 行為。R02、R03、R05、R06–R08 同樣檢查通過。
- [ ] Dark 同頁層級正確（canvas → card）。

## 問題 3：R05 連線說明（VPN 通道）要比照 Figma 精簡

Figma 對照：Light `R05 · 連線說明（VPN 通道）`（`123:56962`）與 Dark 同名；實機截圖是舊版冗長畫面（使用者已在對話貼圖，未存檔，以 Figma R05 渲染為準）。

現況（App）：導覽列標題只有「說明」、大標題「四步完成連線」＋副標、四個步驟各帶兩行說明小字、「仍然無法連線？」下有兩張列（重新連接、本機網路權限）、底部大按鈕「返回並檢查連線」，整頁字多、清單用灰底。

Figma 渲染（以此為準，精簡）：
1. 導覽列：左側返回（chevron＋「返回」）、置中標題「連線說明」；沒有大標題、沒有副標。
2. 一張步驟卡（card 色、單一圓角卡）：三列單行——「1 下載 LocalDevVPN ›」「2 開啟 LocalDevVPN ›」「3 點 Connect」；藍色圓形數字（白字）、無說明小字，前兩列右側有 `chevron-right`（對應原有可開啟的連結：App Store／LocalDevVPN），第三列無 chevron；列間用 `line/separator`。
3. 步驟卡下方一張卡「仍然無法連線？」：標題一行（`Theme/subheadlineEmphasis` 級）＋一則提示「確認連著 Wi‑Fi，在 LocalDevVPN 中斷後重新連接，再回來檢查。」；沒有「本機網路權限」列、沒有第二則提示。
4. 沒有底部主按鈕；返回只用導覽列返回（返回後依既有流程重新檢查連線，不要因移除按鈕而失去自動檢查）。
5. 背景 canvas、卡片 card（同問題 2 的層級）；Light／Dark 都做。
6. 文案三語（zh-Hant、zh-Hans、en）同步精簡，刪除不再使用的字串與其 UI test 辨識碼；`EnglishButtonLabelTests`、`IssueCatalogTests` 要過。被移除的「本機網路權限」入口如在其他地方沒有替代，請在『執行紀錄』列出（不要因此遺失使用者去系統設定開啟本機網路權限的路徑；若沒有其他入口，回報給使用者決定，不自行保留舊列）。

驗收：
- [ ] R05 Light／Dark 與 Figma 並排一致：三列步驟、一張提示卡、無大標題／副標／底部按鈕／多餘說明。
- [ ] 步驟 1、2 的 chevron 行為保留原連結功能；導覽列返回後自動重新檢查連線。
- [ ] 最大 Dynamic Type 下單行文字可換行、不被裁切；UI test 更新。

## 補充：Toast 一律懸浮（適用本批所有畫面）

R04 VPN 檢查成功後不顯示 success Toast；沿用再次確認並自動進入 B1 收合 sheet。所有實際顯示的 Toast／Banner（首次引導錯誤、設定頁、瞬移／路線／搖桿通知與重置成功）改為 overlay 懸浮：疊在導覽列或搜尋列下方、左右 16 pt、不推動版面、帶浮層陰影（黑 18%、y 4、blur 16，Figma Toast 元件已設定），多個時依序堆疊並可個別關閉；使用共用 Toast 元件與單一 overlay 容器。驗收：R04 錯誤通知、設定首頁（含重置成功 toast）、B7、D8 截圖中 toast 都疊在內容上方且下方版面位置與無 toast 時相同。

## 驗證（每項都要）

- 用票 01a 的 fixture（不需網路、VPN、真機）對上述 frame（B1 Dark、R04、R05 及 R02／R03／R06–R08）在 Light 與 Dark 各截圖到 `work/gofly-ios-figma04/screenshots/`，與 `work/gofly-ios-figma04/figma/` 的同名 Figma 截圖並排比對；結論與路徑寫進相關票的『執行紀錄』。若 01a 尚未完成，先用既有 UI test 截圖並如實註明。
- `app/GoFly/scripts/check.sh` 通過；相關單元測試與 UI tests 更新。
- 回報：①修正內容與根因 ②各畫面截圖路徑 ③仍與 Figma 有差異的地方 ④聲明『未做實機驗證、未 commit』。
