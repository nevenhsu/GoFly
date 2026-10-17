# LocalGo

GoFly 三語使用者文件：[English](../../README.md) · [繁體中文](../../README.zh-Hant.md) · [简体中文](../../README.zh-Hans.md)。本文是較早 prototype 與設計歷程，不作為新版 GoFly 正式安裝指南。AI 代理請先讀 [AI-INSTALL.md](../../docs/AI-INSTALL.md)，確認使用者是否選擇 LocalGo 實驗。既有 AGPL 授權保留，新文件 0BSD 範圍見[授權說明](../../docs/LICENSING.md)。

2026-10-17 開發定位確認：**現有 iOS 程式僅為 prototype，不計入正式 GoFly 的功能完成度。** 歷史編譯、測試與裝置實驗保留為技術參考；正式 App 須依核可流程重新建立實作與驗收。視覺採使用者指定的 [Uber design.md](https://getdesign.md/uber/design-md)，原生適配見 [GoFly 視覺方向](../../DESIGN.md)；開發拆分見 [步驟草案](../../work/gofly-planning/IOS-DEVELOPMENT-PLAN-DRAFT.md)。Figma 繼續定義流程／布局／互動，本次只更新規格與計畫，未修改 App 或 Figma。

**iOS wireframe 規格已定稿，App 待實作／真機驗收。** 使用者已核可 [全模組審查](../../work/gofly-planning/IOS-FINAL-UX-REVIEW.md) 的 #1–10 與 C1–C6；現行規格、詞彙與 [單一開發交接](../../work/gofly-planning/IOS-DEVELOPMENT-HANDOFF.md) 已同步。服務待命不移動；新任務準備成功決定交接時先停舊送點再啟新；指定起點在開始路線時才先移至起點；關閉來回維持當下方向到下一端點、原位置 % 不歸零；GPX 用摘要與完整軌跡；位置回覆未知跨返回仍鎖原 Go；背景／冷啟動依原模式且不重播；還原中不開始任務；路線／GPX 刪除可復原。路線各地點 input 只開 search mode，同一張路線清單，角色小字在名稱上方、右側垃圾桶可刪任意節點；選定確認才回填，取消保留。手動路線只保留有效已確認節點，既有值清空確認等於刪除、取消保留；搜尋關鍵字清空不刪節點，非空無效輸入不覆寫，少於兩點停用開始／儲存。真實 GPS 缺少仍只小提示，H06 GPS 待確認仍可啟動準備服務。只做繁中靜態 wireframe，不做 prototype，不改 App 或 Mac docs；App 三語要求維持。Figma 本輪已透過 Desktop Bridge 套用本機並完成靜態讀回（雲端同步未另驗證），最新實際數量以 [定稿交付](../../work/design-localgo-v2/oct17-ios-finalized/README.md) 為準，以下較早交付數量屬當輪記錄。

2026-10-17 最新修正：撤下 iOS H12 與 Mac U19，不新增手機支援資料下載或額外設定頁。程式確有 DDI 自動準備需求，規格由 Mac 安裝流程按實際需要處理／驗證，已備妥項目重用；UI 僅「準備裝置」，U18 安裝完成即可結束。08–11 現為 17 張 App 狀態＋4 張註記（09：4 張）。[本次交付](../../work/design-localgo-v2/oct17-mac-install-readiness/README.md)。僅 wireframe 與 docs，Mac 新能力尚待實作。

2026-10-17 最新修正：無真實目前位置只顯示「目前無法取得真實位置」小提示，右側 × 可關閉，不擋搜尋、座標、地圖選點、最愛或有效候選 Go；關閉後相同情況本次流程不反覆出現。撤下 H02／H03 提示窗，F07 保留非模態示例；無真實 GPS 不畫定位箭頭，實際模擬服務失敗才共用 O14 準備失敗。該輪曾為 18 張 App 狀態＋4 張註記；最新已再撤下 H12，以本文最新修正為準。[本次交付](../../work/design-localgo-v2/oct17-optional-real-location/README.md)。僅 wireframe 與 docs。

08–11 最新 wireframe：撤下過時 UI 與模式排列副本，由 60 張舊 App 頁合併為 **17 張必要 App 狀態（08：4、09：4、10：3、11：6）**，每區另有一張小型規則參考框。08 只在送點前最多三次準備嘗試，原任務僅健康時維持；送點後回覆不明先核對、不盲目重送。09 VPN 修復共用 07 C05，恢復連線不自動繼續任務。10 健康回前景沿用 03／06，僅補確認中、背景中斷暫停及能力未就緒；背景持續仍待實作／實機驗收。11 區分停止送點、clear 確認與取得 GPS，「已停止・GPS 待確認」可恢復 GPS／重置 VPN 通道；停止終結任務，路線取消保留模擬位置的規則不變。舊 O26 暫停改道與 H08 不顯示已停止的規則撤下。詳見 [執行 flow 審查](../../work/gofly-planning/RUNTIME-FLOW-REVIEW.md) 與 [本輪交付](../../work/design-localgo-v2/oct17-runtime-flow/README.md)；本輪只改繁中靜態 wireframe 與 docs，不做 prototype、不改 App，三語開發要求維持。

Mac 開發新定案：裝置管理選擇裝置並成功連線後，USB／Wi-Fi 都自動重新簽名 GoFly App，保留資料；現有手動重新簽名 flow 保留。每筆選取連線交易觸發一次，刷新／同機傳輸切換不重複寫入；沿用前置條件及中斷規則。詳見 [Mac 開發規格](../GoFlyMac/DEVELOPMENT.md)。本輪僅更新 docs，App／Figma 未修改。

C06 已新增常駐「更新簽名」字卡：開啟 Mac App → 裝置管理更新簽名；簽名到期後 iOS App 將無法使用。到期日依真實資料，未知不造假；不提供 iOS 自動續簽按鈕。只更新 wireframe 與 docs，見 [C06 交付](../../work/design-localgo-v2/oct17-c06-signing/README.md)。

C05 最新補充：開啟 LocalDevVPN 下方並排「檢查連線／重置 VPN 通道」按鈕，移除重複檢查列表列；C01 重置入口保留，兩者共用同一操作。重置仍僅停止送點後可用（含 GPS 待確認），檢查／重置互斥，不清資料、不恢復 GPS 或重播任務。只更新 wireframe 與 docs；[C05 交付](../../work/design-localgo-v2/oct17-c05-channel-actions/README.md)。

最新補充：B01 前景立即及每 5 秒檢查 VPN 通道，2 秒逾時；手動「檢查連線」在下一步正上方，狀態為檢查連線／檢查中…／連線成功，成功才啟用下一步。重置按鈕統一「重置 VPN 通道」，停止送點後手動修復 LocalDevVPN Connected 但 GoFly 無法連線，實際重建／探測成功才宣告可用；不清資料或當作恢復 GPS。見 [本輪交付](../../work/design-localgo-v2/oct17-vpn-poll-reset/README.md)；僅靜態 wireframe 與 docs。

最新必要條件：B01 與 C05／設定入口統一「VPN 通道」，合併原 VPN、通道兩列。B01 移除略過，實際通道可用才啟用下一步，點擊再次確認；開啟 LocalDevVPN 或 Connected 外觀不能代替實測。回 App 自動檢查，也可按檢查連線重試；A02 定位略過保留。配對與定位服務仍在啟動／Go 自動確認。見 [VPN 通道定案](../../work/design-localgo-v2/oct17-vpn-channel/README.md)。

最新定案：B01 改「VPN 通道」，移除「裝置／尚未檢查」；首次引導只處理 VPN，配對與定位服務在按啟動或 Go 時自動確認，成功才允許送點；啟動本身不移動。C06 移除底部 VPN 按鈕，VPN 從設定首頁進入。B01 必須通過 VPN 通道，不提供略過；只有定位仍可略過。只更新靜態 wireframe 與 docs。見 [B01／C06 交付](../../work/design-localgo-v2/oct17-vpn-onboarding/README.md)。

01 保留完整前進操作與 A02 定位略過，B01 必要通道不可略過；按鈕均位於安全區內且未裁切；拒絕定位、檢查失敗／未知、略過及外部返回都有明確去向。見 [01 完整流程修復](../../work/design-localgo-v2/oct17-onboarding-flow-repair/README.md)；僅繁中靜態 wireframe 與 docs，不做 prototype。

自用 iOS 定位 App 開發版，目標 iPhone 15／iOS 27，部署目標 iOS 26。地圖介面與功能以 SwiftUI／MapKit 實作，裝置通道採 StikDebug／idevice 開源引擎並保留 AGPL-3.0 授權。

2026-10-17 全部核可的 HIG 精簡：01 主線為 A01／A02／B01／B06 四個 App 畫面，A03 為外部系統參考，A05 背景設定移至 07，B05 成功狀態合併 B01。最新修復保留明確前進／略過：A01「下一步」、A02「允許定位／略過」、B01「VPN 通道」不提供略過，通道實際可用才啟用下一步；失敗／未知留原頁，可按檢查連線重試。外部返回只更新狀態、不自動跳頁；後續啟動／Go 仍須完成準備。「可用」不等於「已啟動」。07 合為 C01／C03／C04／C05／C06／C07 六個主畫面，首頁分組列狀態，01／07 頂部統一「返回」、移除底部長返回按鈕，按鈕採「開啟系統設定／重新檢查／連線說明／連線協助」；C04 用途字卡說明路線／漫步可在背景持續模擬 GPS，此為最新功能目標，尚待實作及實機驗收；系統背景重新整理開關本身不保證持續排程。02 移除正常狀態教學與保留提示，地點入口統一「☆ 最愛地點」，保留錯誤與有用空清單，D18 設計規則註記保留；02 合併六張重複資料／收藏副本並補 K02 空最愛，現為 18 張 App 狀態＋D18，共 19 張。**無效座標保留上一有效候選與收藏，但停用 Go；修正有效或明確選取另一有效地點後才恢復。** 所有操作區設計要求至少 44 × 44 pt。詳見 [01／02 核可紀錄](../../work/gofly-planning/ONBOARDING-TELEPORT-FLOW-REVIEW.md) 與 [07 核可紀錄](../../work/gofly-planning/SETTINGS-FLOW-REVIEW.md)。只更新 Figma 靜態 wireframe 與 docs，不做 prototype、不改 App。最終清單及讀回見 [本輪交付](../../work/design-localgo-v2/oct17-approved-hig/README.md)。

最新背景功能目標：路線與自動漫步在 App 背景仍可持續模擬 GPS，C04 保留用途字卡；需採適用 iOS 背景機制並實測 VPN／裝置通道，不能只靠背景重新整理開關宣告支援。既有 App 的背景暫停行為仍如實記錄，尚未依此目標實作或驗收。

**Wireframe 只用繁體中文；App 開發支援英文（en）、繁體中文（zh-Hant）、簡體中文（zh-Hans）。** UI／錯誤／輔助技術文案使用本地化 string keys，未支援語言及翻譯缺漏以英文 fallback；使用者標籤與地點資料不自動翻譯。開發需驗三語格式、長英文、最大 Dynamic Type 與 VoiceOver；尚未宣告三語或無障礙實作完成，不另畫三套 Figma。

2026-10-17 地圖標示最新規則：所有模式的地圖標示 icon 下方均不顯示文字，包含目前模擬位置箭頭、真實 GPS、最後已知／待取得位置、當前目的地與當前點擊地 Pin、移動方向及路線標記。名稱、地址、經緯度由地點 Pin 點擊後的 card 呈現；頂部位置／任務狀態仍保留。當前點擊地 Pin 上方的 Go 是操作按鈕，繼續保留。已同步主要 Figma 靜態 wireframe 與開發規格，App 尚未依此修改。交付見 [地圖標示文字清理](../../work/design-localgo-v2/oct17-map-marker-captions/README.md)。

**不接入 AnyGo／iToolab 的登入、授權、配對下載或其他服務，也不使用其程式碼、素材、憑證或嵌入金鑰。** 研究樣本留在專案 `work/`，不納入 App。Apple 地圖／搜尋仍需網路。現有 iOS 程式會在準備時下載上游 DDI；最新設計改由 Mac 安裝流程依需要自動取得並驗證，iOS 不另設下載步驟，此能力尚待實作。

2026-10-17 追加：設定「偏好設定」新增語言（跟隨系統／英文／繁體中文／簡體中文）與外觀（跟隨系統／淺色／深色），皆預設跟隨系統、單選立即保存套用，重開保留；變更不影響服務、任務或位置。僅更新繁中 wireframe 與 docs，App 待實作；[偏好設定交付](../../work/design-localgo-v2/oct17-settings-preferences/README.md)。

## 最新設計需求

07 設定首頁頂部裝置服務 card：全寬大按鈕啟動／停止，下方並排恢復 GPS／重置 VPN 通道，僅停止送點後可用。GPS 恢復與停止送點分開顯示；「已停止・GPS 待確認」仍可修復，不會鎖死操作。C07 已更正漫步放開搖桿會繼續自動；使用者確認停止同時恢復 GPS；重置用於清除 VPN 失效的暫存錯誤／舊通道並重新檢查，不清除最愛與草稿、不宣告 GPS 已恢復或自動繼續任務。未連接仍走既有 VPN 指引。僅更新靜態 wireframe 與開發規格，App 未修改；見 [07 交付](../../work/design-localgo-v2/oct17-settings-service-card/README.md)。

2026-10-17 最新追加：**所有模組只做靜態 UI／UX wireframe flow，不製作 prototype、接線或原型測試。** 03 已移除漫步開關及自動隨機下一站功能，路線細項只保留 「已匯入路線」清單入口、來回走動與速度，不放起點／途經點／目的地等地點 UI。03 初始／規劃 mode 保留路線編輯工具；進行中僅進度、來回 checkbox、取消、暫停，暫停時僅進度、來回 checkbox、取消、繼續。取消結束本次路線、保留草稿回初始 mode 才能編輯；暫停／繼續保留進度，取消後保留最後模擬位置，與設定內「停止／恢復原定位」分開。GPX、來回走動與速度放入滑桿 icon 的「路線細項」；全域設定改齒輪 icon，03 top bar 統一「位置／狀態 → 播放或暫停 → 設定」。初始 UI 的最愛路線入口對齊「☆ 最愛地點」樣式，不另放最愛地點按鈕。初始 mode 的起點、途經點與目的地列最左側都有按住拖動的六點把手，支援整列重排；首尾角色與途經點編號隨新順序更新，地點資料不變。起點、途經點與目的地共用搜尋 input：點擊進入地點編輯 UI，空白／無 options 時可從最愛選擇該欄位，輸入後顯示選項，確認才回填並回到初始 UI，取消保留原值。路線 star 改為開啟「加入最愛路線」Label 彈窗，取消不新增、儲存才新增完整起終點與有序途經點；不查重、不顯示實心／空心狀態，允許重複紀錄，速度與來回設定另外管理。最愛路線清單保留選取與長按標籤編輯，移除操作改用刪除圖示；地點最愛星號規則不變。規格與驗收見 [PRODUCT-SPEC.md](PRODUCT-SPEC.md) 的「03 單次路線 wireframe 定案」，交付見 [本輪紀錄](../../work/design-localgo-v2/oct17-route-details/README.md)；App 尚未依此更新。

所有地圖 Pin 共用地點 card：Pin 下方不放文字，點擊後看名稱、地址、經緯度，右上星號即時加入／移除最愛地點。搜尋選項仍保留單一 title；查看／收藏不移動或暫停任務，瞬移 Go 維持獨立操作。主流程 25 個可見 Pin 已統一，另補一張共用詳情示例，見 [Pin card 交付](../../work/design-localgo-v2/oct17-pin-place-card/README.md)；只更新 Figma 與開發 docs。

06「搖桿與地圖視角」已整合漫步，05 的 21 張舊畫面整區刪除。勾選漫步顯示目前目的地 icon，同列最右側有「隨機目的地」無框按鈕，可立即更換目前目標，抵達後仍會自動換下一站；自動行進時搖桿 UI 同步方向。拖動搖桿只暫時接管，保持勾選與目的地，放開後從目前位置恢復自動漫步。漫步中也可點地圖放候選 Pin（上方 Go），按 Go 才更換目前目的地，從當下位置前進、不瞬移；按 Go 前仍前往原目標，當前目的地（輪廓 icon、無 Go）與當前點擊地（黑點細線 icon、有 Go）明確區分，再次點擊任一 icon 都可開其地點 card／加入最愛，關閉後可重開。手動接管與暫停狀態保持。搖桿下方說明文字全部移除，操作面板縮為 354 pt，規則保留於開發規格及 flow 註記。06 共 8 張靜態 wireframe（含共用 Pin card 與地圖候選／Go 示例），詳見 [06 交付](../../work/design-localgo-v2/oct17-joystick-wander/README.md)；沒有 prototype 或 App 實作變更。

04「來回走動」保留順向／逆向兩張靜態 wireframe。勾選後，在來回 checkbox 同一 row 右側顯示無框「切換 icon＋目前方向」，點一下直接改向，不用方向 checkbox；圖示在文字左側。位置條為「目前位置 %」，固定起點 0%、終點 100%，順向增加、逆向減少，切換方向不跳變。面板 190 pt，暫停／取消確認與編輯沿用 03；未勾選的 03 畫面保持。見 [04 交付](../../work/design-localgo-v2/oct17-roundtrip/README.md)；App 未修改，沒有 prototype。

D04／O23 暫停時按取消，先顯示「取消這次路線？」確認窗；返回維持暫停與原進度，確認取消才結束本次路線、保留最後模擬位置與草稿回可編輯初始 mode。只補一張共用靜態確認窗，未製作 prototype 或修改 App。

「已匯入路線」清單按鈕放在路線細項，GPX 匯入／匯出按鈕都放在清單內；匯出以目前選取路線為對象，無選取時停用。成功匯入後加入清單並選取，按「載入路線」才回初始 mode，按開始才移動。清單保留可重用的完整路線，選取、刪除與最愛收藏分開；只更新 Figma／開發規格，App 尚未實作。

**目前僅討論 UI／UX wireframe，不製作互動 prototype。** 搜尋欄下方不再重複顯示名稱／經緯度輸入標題與選定後更新 Pin 的說明。02 模組已移除原型接線、02B 重複狀態畫面及原型專用元件；保留主要畫面與卡片規則示例。搜尋、候選、座標與到達卡片不放「編輯標籤」按鈕；最愛清單逐筆列地點，短按選取，長按該筆開啟 Label input 與鍵盤。編輯頁不顯示 mode tab，底部僅「儲存／取消」，兩者皆回原清單，保留候選與定位任務；星號繼續獨立即時切換收藏。開發規格見下方連結，早先原型實測僅屬歷史紀錄。

2026-10-17 已確認 GoFly 瞬移流程：直接點地圖指定目的地，取消右上角選點按鈕；搜尋、有效經緯度、點圖及最愛選點都更新並置中候選 Pin。Pin 按鈕一律寫 **Go**，未啟動時會自動啟動服務並準備後前往；成功才更新模擬位置箭頭並移除 Pin。到達、暫停／繼續保留正確目的地與收藏狀態；執行、失敗及位置待確認分支需保留候選並避免重複送出。完整規則及驗收條件見 [PRODUCT-SPEC.md](PRODUCT-SPEC.md)。相關設計已套用 Figma 本機靜態 wireframe 並同步 docs，早先互動原型已撤下；雲端同步仍待確認，已另存本機副本。以下「已實作」不代表已符合這次設計；本輪不修改 App。後續確認變更需同時更新相關 docs。

最愛地點統一以實心星號表示已收藏、空心表示未收藏，點一下立即儲存加入／移除並更新列表，之後可另行編輯標籤。G02 名稱列最右側也使用同一星號切換，取代寬幅加入／移除按鈕。**經緯度地點也可透過星號加入最愛，不必先按 Go**，無地標名稱時先顯示座標。標籤儲存只改標籤，放棄標籤變更不還原收藏；操作保留目前目的地、定位及任務。詳見 [PRODUCT-SPEC.md](PRODUCT-SPEC.md) 的「GoFly 最愛地點操作定案」。03 路線已開始依最新指示檢視；06 已加入漫步 checkbox、自動方向連動與手動暫時接管，見 06 最新規格。

2026-10-17 追加確認：02 模組的搜尋、候選及最愛地點選項統一為單一 title＋右側 ☆／★ 的圓角矩形卡片。title 優先名稱、無名稱時地址、再經緯度；直接輸入座標顯示座標，不加地址副標。初始／未選取與目前選取以外框、淡底色區分，收藏獨立；有效座標輸入後自動選取其卡片及置中 Pin，仍須按 Go 才瞬移。本輪已用 Figma Desktop Bridge 更新本機畫布；規則與驗收見 [PRODUCT-SPEC.md](PRODUCT-SPEC.md) 的「02 模組地點選項卡定案」，雲端同步待確認，App 尚未更新。

## 已實作

- 目前位置使用方向箭頭；已套用位置優先於手機讀取的位置，搖桿與路線方向會配合地圖旋轉顯示。
- 地圖選點、地址／經緯度搜尋，區分預覽選點與服務接受的位置；點圖保留縮放，上方顯示已接受的位置名稱或 GPS 座標。
- 原生霧白／墨綠介面，含深色模式、44 pt 圖示操作與簡潔設定；LocalDevVPN 按鈕可直接開啟 App，開啟失敗時轉到 App Store。
- 可收合的控制面板；未啟動時提供啟動及「恢復真實定位」。啟動後，模式列固定在面板最上方，只有瞬移顯示搜尋與儲存地點。頂端圖示控制啟動／停止；清除命令完成後回到啟動狀態，真實定位須由使用者在其他 App 確認。
- 單點瞬移；多點直線路線或 Apple 步行道路規劃。道路失敗時顯示失敗，由使用者明確選擇直線。
- 路線開始、暫停、手動繼續、往返；速度 2–100 km/h、步進 1，預設 20 km/h，快捷 5／20／60。
- 搖桿方向與速度；放開停止送點，按停止要求清除模擬位置。
- GPX 1.1 匯入／匯出；上限 2 MiB／10,000 點，驗證座標、拒絕 DTD／外部實體。
- 本機收藏與歷史各最多 100 筆、個別刪除；私有儲存、原子替換與檔案保護。
- 真實裝置命令 adapter、UDID 綁定、DDI 準備；單一命令排程與過期回覆防護。正式 App 不使用假定位引擎。

切到背景時暫停路線、停止搖桿送點，保留最後送出的位置；返回後需手動繼續。停止會取消排程並要求清除。清除失敗維持「未知」，不能把關閉 App、刪配對或停 VPN 當作定位已恢復。

更新或重新開啟 App 後仍可按「恢復真實定位」，不必先啟動或設定新位置。清除要求已完成但位置仍未恢復時，可再次送出清除；正在進行中的要求只執行一次。開發者服務回傳成功不代表實際座標已恢復，介面不再顯示「已確認清除」。本次使用者回報多個 App 仍是錯誤位置，實際恢復尚未驗收。

裝置身分驗證使用定位專用通道，平常重用，傳輸失敗時重建一次；啟動的開發映像檢查也改用獨立通道，避免舊通道阻擋停止與重新啟動。本機端點無法連通時，即使 LocalDevVPN 顯示 Connected，仍可在該 App Disconnect 再 Connect，回來重試停止；當時的操作建議是確認清除後再重新啟動。這段是既有修正紀錄，不構成新門檻：本次定稿的 H06 GPS 待確認仍可啟動準備服務，不移動、不重播。使用者回報本次切回 4G 後自行恢復；這不代表新版本已驗證。此修正已補上模擬通道失效的回歸測試，更新後的鎖屏及 Wi-Fi／4G 切換仍待實機驗收。

## 尚未完成的驗收

已在使用者的 iPhone／iOS 27.0.1 完成自有 RP 配對、Personal Team 簽署安裝與私密 USB 交付；App 已回報本次交易匯入成功。使用者也確認手機端裝置身分與 DDI 核對成功。使用者已確認斷開 USB 後，兩個其他 App 都收到選定位置。使用者也已確認停止清除後恢復真實位置；iOS 26 尚未實測。

[Mac 首次設定工具](MacSetup/README.md) 已實作自動選擇唯一 USB iPhone／Personal Team、簽署、建立及驗證自有 RP、安裝、私密交付與手機回報。使用者已接受另裝 LocalDevVPN，手機透過它運作；不再要求自行搬配對檔。前景會檢查本機通道，通道不可達時顯示開啟 LocalDevVPN 的提示，恢復連通後自動收起。這項檢查不代表能讀取另一個 App 的 VPN 開關，啟動仍會驗證配對及裝置身分。背景持續移動、重啟後恢復、所有 App 相容性、遊戲助手與雲端同步仍未交付。簽署及配對有效期依 Apple／裝置狀態，需要時可重跑設定工具，不承諾永久免續簽。

完整能力對照見 [PRODUCT-SPEC.md](PRODUCT-SPEC.md)。AnyGo 靜態研究見專案 `work/anygo-installed-ios/SPEC.md` 與 `work/anygo-mac-installer/FLOW.md`；不能將研究線索當作自用 App 的實機成功證據。

## 建置與測試

需已接受條款的 Xcode 27；首次解析套件需網路。從研究專案根目錄執行：

```sh
env DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -project app/LocalGo/StikDebug.xcodeproj -scheme StikDebug \
  -configuration Debug -destination 'generic/platform=iOS' -sdk iphoneos \
  -derivedDataPath work/localgo-derived \
  -clonedSourcePackagesDirPath work/localgo-packages \
  -onlyUsePackageVersionsFromResolvedFile \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY= \
  ARCHS=arm64 build
```

產物：`work/localgo-derived/Build/Products/Debug-iphoneos/StikDebug.app`，顯示名稱 LocalGo。這條命令產生未簽署產物，不能直接安裝。實際首次安裝請使用 [MacSetup](MacSetup/README.md) 的 `setup --execute` 流程；本次已用使用者的 Personal Team 完成開發簽署與指定裝置安裝，未發布。

```sh
env DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  swift test --package-path app/LocalGo --scratch-path work/localgo-swift-tests

bash app/LocalGo/Tests/NativeRecovery/run.sh
```

受限 SwiftPM 環境可另設模組快取；最新首次設定驗證在 `work/mac-first-setup/`：48 項 Swift 核心測試、26 項 Mac 測試，以及實機安裝／匯入紀錄。測試假引擎僅用於宿主的命令與排程驗證，不代表實機通道已成功。

## 裝置設定與待驗收情境

1. 開發者模式已啟用；在 Mac 執行 [首次設定工具](MacSetup/README.md)，由自己的 USB 裝置產生自有 RP。
2. 目前通道需另裝並啟用 [LocalDevVPN](https://apps.apple.com/us/app/localdevvpn/id6755608044)，使用預設本機位址 `10.7.0.1`。
3. Mac 自動簽署、安裝並交付配對，收到匯入回報後，在 LocalGo 按「啟動」。手動匯入保留作為進階修復選項。
4. 斷開 USB、停止 Mac 連線工具，從 LocalGo 套用位置；在 Apple 地圖與另一個 App 重新取得位置。服務 ACK 只代表接受命令。
5. 分別驗證瞬移、路線、搖桿、切換 App 後保留最後位置，以及停止後恢復真實定位。
6. 在 iOS 26、27 各自測試鎖屏、VPN／網路中斷、重啟及重新準備。未通過前不能宣稱相容或持續有效。

配對存於私有 Application Support/Pairing，目錄 0700、檔案 0600、首次解鎖後可讀、排除備份，含 1 MiB 上限與內容／身分檢查。無配對分享、Documents 鏡像或識別碼診斷。開啟 App 不會自動開始模擬定位或下載開發元件；前景只檢查本機通道。按「回到目前位置」時才詢問使用期間定位權限，已允許時前景顯示手機位置；不要求背景定位或背景音訊權限，也不儲存或記錄手機定位。

來源及限制見 [UPSTREAM.md](UPSTREAM.md)，授權見 [LICENSE](LICENSE)。

07 已按指定 ios-hig-design skill 完成排查並全部核可；六個主要頁面與短文案定案見 [設定 flow 審查](../../work/gofly-planning/SETTINGS-FLOW-REVIEW.md)，本輪套用靜態 wireframe 與開發 docs，App 未修改。

2026-10-17：01／02 已依指定 ios-hig-design skill 排查。D01 移除「尚未選擇地點」與重複搜尋教學，面板縮為 186 pt、不留佔位；01 舊 prototype 接線已撤下，01／02 均僅靜態 wireframe。其他刪字／短文案及流程精簡已全部核可，見 [01／02 審查](../../work/gofly-planning/ONBOARDING-TELEPORT-FLOW-REVIEW.md)。App 未修改。

2026-10-17 最新核可：已改為一張路線清單，單一圓角外框、細分隔線及 72 pt 列；中間角色／名稱上下排列，左把手、右垃圾桶，各自獨立操作。地點區開啟 search mode，選定確認才提交、取消保留原值；其餘節點／任務規則不變。D02／O24／R06 背景共 8 列已套用，無新手機頁或 prototype，App 待實作；[本輪讀回與截圖](../../work/design-localgo-v2/oct17-route-list/README.md)。
