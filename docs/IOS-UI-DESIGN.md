# GoFly iOS UI 設計與驗收規格

確認日期：2026-10-18。使用者要求把線框細化後直接實作於 iOS App，**不修改 Figma**。中文使用 **iOS 內建系統字體**。本文件補充 `DESIGN.md`，流程與命令語意仍依原開發規格；不增加頁面、權限或新的送點操作。

## 視覺系統

延續 GoFly 黑白、中性灰風格，地圖保持主體。主要 CTA 為深淺模式自適應的黑／白膠囊，次要 CTA 使用柔灰底；錯誤使用高對比語意文字及既有警示圖示，不能單靠顏色辨識。2026-10-20 改版新增 danger／warning／success 語意狀態色，僅用於狀態，見文末。

| 角色 | 設計與實作 |
| --- | --- |
| 字體 | SwiftUI `.largeTitle`、`.title3`、`.headline`、`.body`、`.subheadline`、`.caption`；中文由 iOS 系統自動選字型，不指定第三方字體；數值才使用等寬數字 |
| 面板標題 | 路線 `.title3.bold`；狀態 `.headline`；一般內容 `.body`；說明 `.subheadline`／`.footnote` |
| 底面 | `.systemGroupedBackground`；內容卡 `.systemBackground`；內嵌控制 `.secondarySystemBackground` |
| 邊界 | 主面板 20 pt 連續圓角、0.5 pt 語意分隔線；搜尋／地點 14 pt；資料列及較小卡 12 pt |
| 輸入區 | 搜尋／標籤欄位使用 `systemGray5` 底色與 `systemGray` 0.75 pt 常態邊線；聚焦 1.5 pt primary。這取代原先與頁面相近的 secondarySystemBackground＋淡邊線 |
| 層次 | 一般頁面卡平面；地圖卡 16 pt 模糊、向下 5 pt 的克制陰影；深色提高陰影不透明度 |
| 主要按鈕 | 17 pt 語意 body semibold，最低內容高 44 pt，加上下各 6 pt；可因換行長高。僅地圖候選 Go 在無障礙字級取消額外上下留白，保留自然字高與至少 44 pt 操作範圍，避免鍵盤壓縮可視地圖 |
| 次要按鈕 | 同主按鈕字級，最低內容高 44 pt，加上下各 2 pt、柔灰底與細邊界 |
| 圖示按鈕 | 最小 44 × 44 pt，圓形柔灰底；共用圖示隨字級有限度縮放至最大 24 pt，避免極大字級溢出圓形；設定圖示依容器使用 18–24 pt。標籤與目前可用狀態由原有 accessibility 說明提供 |
| 留白 | 主面板內距 16 pt；頁面／詳情可用 24 pt；分組 20–24 pt；相關元素 8–12 pt |
| 按壓 | 按鈕即時降低亮度／透明度；不移動點擊範圍、不以動畫拖延命令 |

`GoFlyStyle` 是共用樣式來源；`goFlyCard(floating:radius:)` 統一卡片，`GoFlyEmptyState` 統一空白狀態。平台控制（導航、選單、滑桿、鍵盤、授權及確認框）保留原生行為。背景與卡片使用不透明語意底色，地圖內容不會透入文字區。

## 畫面與狀態細節

| 畫面／區域 | 實作細節與保留規則 |
| --- | --- |
| 首次歡迎／定位權限 | Logo 啟動銜接歡迎頁；背景檢查超過約 0.5 秒才顯示細進度條。引導顯示 1／2／3 步驟；定位區分尚未設定、已允許與已拒絕，主要動作分別為允許定位、下一步、前往設定；已允許不顯示略過，其餘可略過 |
| VPN 引導／說明 | 檢查中為中性、失敗 danger、成功 success，圖示與文字並用。首次引導與設定共用連線說明頁及 LocalDevVPN／App Store fallback；下一步仍由真實可達狀態啟用 |
| 地圖頂部 | 浮動搜尋列右側齒輪進設定，下方狀態 pill；執行模式與全螢幕頁隱藏一般 chrome，頂部不放啟停 |
| 模式列 | 底部瞬移／路線／搖桿三個等寬 tab；最愛由內容入口開啟。執行模式與全螢幕頁隱藏 bottom bar |
| 搜尋 | 全螢幕頁使用獨立輸入區及無框結果列，直接輸入有效座標；名稱搜尋比對最愛標籤、名稱與地址。最近搜尋只在目前地圖 view 生命週期的記憶體保留，最多 8 筆，不新增磁碟歷史 |
| 地點選項 | 無框結果列呈現標題與地址／座標，最愛標籤優先；點列返回地點 sheet 或回填指定路線欄位，不直接送點 |
| 位置箭頭／候選 Go／Pin | GPS 空心、模擬實心向量箭頭，等待保留 50% 透明度，無圓底／外圈。候選 Pin 上方小型 Go 約 28 pt，命中至少 44 pt；地點 sheet 亦有同一 Go，未確認位置時兩處停用。箭頭方向問題 #15 留待功能修正軌 |
| 地點詳情 | 地點 sheet 顯示名稱、地址與座標，動作列為 Go／收藏／設為起點或終點／複製；查看、收藏與複製不送點 |
| 最愛地點 | 清單星號先變空心，約 0.5 秒後刪除，期間再點可取消；⋯ 編輯標籤／刪除，選取多筆批次刪除，刪除後 2 秒 snackbar 可復原；底部搜尋只查最愛 |
| 路線編輯 | 可編輯規劃採單一節點清單，左把手／中角色與地點／右垃圾桶；欄位開全螢幕搜尋，點結果即回填返回。GPX 載入後完全唯讀，不顯示編輯控制 |
| 路線細節／執行 | 執行模式隱藏搜尋與 tabs，頂部深色指示卡、底部進度／暫停或繼續／結束，結束需確認；保留原 ACK、位置百分比與取消語意 |
| GPX／最愛路線 | 資料夾入口開匯入清單，點列開載入／查看全部點位／匯出／刪除選單；匯入成功 snackbar 可載入，失敗 banner 保留清單。≤10 點完整唯讀列出，>10 點顯示起點／第 2 點／中間 N 點／終點及全部點位入口 |
| 搖桿／漫步 | 刻度、陰影、拖曳高亮、觸覺與回彈；一般與漫步共用 150 pt 搖桿。隨機目的地為帶 ⟳ 的次要按鈕。漫步結束需確認，呼叫既有取消入口並保留最後模擬位置 |
| 準備／修復／背景通知 | 錯誤統一為 StatusBanner，修復指引在說明內，保留 loading 與既有重試／取消／設定／返回可用性；一次性結果以 2 秒 snackbar 呈現，不把畫面更新視為命令成功 |
| 設定首頁 | 分組底面、32 pt 單色圖示區、64 pt 最低行高、內縮分隔線；長狀態值可上下重排；服務卡與 GPS 狀態分層 |
| 設定子頁／說明 | 定位、背景、VPN、語言與外觀、裝置與簽名、說明使用原生導航；語言與外觀使用原生 Picker。拒絕定位標 warning，使用期間屬正常；裝置頁保留診斷匯出 |
| 首次交接／資料鎖定／還原 | 沿用共用按鈕、字體及卡片 token；不更動資料交接、准入及修復邏輯，不以裝飾掩蓋失敗提示 |

## 自適應與無障礙驗收

- 中文：繁中／簡中都由系統字體呈現；不得新增 `UIAppFonts`、`.custom` 字型或網路字型；數值使用等寬數字不影響中文。
- 字級：標準字級與 Accessibility XXXL；文字不縮小來塞進固定框，長標籤／狀態可重排或捲動；搜尋、確認、取消與星號須可觸及。
- 深淺色：文字、卡片與主次 CTA 依語意色切換；選取、失敗、停用不能只靠顏色判別。
- 操作：最少 44 × 44 pt；選點、最愛、詳情、排序、刪除與開始各維持獨立目標；地圖露出區依實測面板高度計算。
- 固定高度的 chrome（bottom bar、浮動搜尋列、狀態 pill）在 Accessibility 字級上限為 `accessibility1`（與 UIKit tab bar 相同），避免三個等寬 tab 互相擠壓；sheet 與面板內文不設上限。
- 原生能力：保留系統鍵盤、手勢與 VoiceOver 標籤；裝飾圖示不加入朗讀；沒有新增持續動畫，支援減少動態效果。
- 圖示：`GoFlySymbols` 為標準 SF Symbol 語意目錄；齒輪、重定位、關閉、重試、排序、匯入／匯出、外部連結同一用途用同一符號。`goFlyControlSymbol` 只調整獨立 glyph，文字不因固定圖示容器縮小；目前／模擬位置、候選 Pin 與目的地各可辨識。
- 驗證順序：專案 `check.sh`、既有對應 UI 測試、模擬器截圖檢視；手機 VoiceOver、觸感與定位／背景效果集中於裝置驗收。

## 完成度與證據

以上為本次 App 精修範圍，並非 Figma 視覺稿更新。驗證結果與截圖索引記錄在 `work/gofly-ios/design-polish/RESULT.md`。模擬器／建置通過不代表真機定位、GPS、VPN 或接收 App 行為已通過。

設計依據：`ios-hig-design` 與 `mobile-ios-design` skills，以及 Apple [Layout](https://developer.apple.com/design/human-interface-guidelines/layout)／[Typography](https://developer.apple.com/design/human-interface-guidelines/typography) 的原生版面與語意字級方向。

## 地圖語言的可實作範圍

App 偏好語言優先用於介面、marker 輔助標籤，以及點選地點的反向地理編碼地址。`MapKitPlaceResolver` 在每次建立 request 時讀取最新偏好，設定 `MKReverseGeocodingRequest.preferredLocale`；系統選項使用 nil 以沿用 MapKit 預設，不需要替換地圖、移動鏡頭或重建任務。

查核已安裝 iOS 27.1 SDK：`MKMapView`、`MKMapConfiguration`、`MKLocalSearch.Request` 未提供每張底圖／搜尋結果的 locale 設定。底圖地名與 POI 標籤仍由 iOS／Apple 地圖及可用資料決定，不宣告已隨 App 偏好翻譯；既有最愛、歷史搜尋與使用者標籤也不改寫。可用公開 API 見 Apple [preferredLocale](https://developer.apple.com/documentation/mapkit/mkreversegeocodingrequest/preferredlocale)。

本輪圖示、Pin、輸入對比與地址語言的驗證位於 `work/gofly-ios/icon-refinement/RESULT.md`；Debug Simulator 元件預覽只驗證繪圖，不提供 GPS、服務或 ACK 證據，也不編入 iPhone target。

## Google Maps 參考改版（2026-10-20）

**狀態：使用者已核可方向與決策；Figma「04 · iOS Redesign（Google Maps 參考）」已畫正式版精細度靜態畫面（淺色 40 張：共用元件 1、A 5、B 7、C 4、D 12、E 3、F 8；同頁右側「Dark · 」前綴為對應深色版 40 張；2026-10-20 第二輪：移除 R03、新增 R05 連線說明、D5–D12 匯入路線（清單、超過 10 點摘要、全部點位唯讀清單、匯入與匯出流程）、F4–F8 設定子頁），不含 prototype。App 步驟 1–8 已實作；步驟 9 的完整檢查、既有 UI 測試與代表性畫面驗證由本輪交付結果記錄，未宣稱全部驗收通過；真機項目仍待驗證。** 計畫、comments 對照與待補事項見 `work/gofly-planning/IOS-GOOGLE-MAPS-REDESIGN-PLAN.md`。

### 取代的規則

| 原規則 | 改版後 |
| --- | --- |
| 地圖頂部：位置來源／服務狀態卡＋啟停＋設定 | 浮動搜尋列（右側齒輪＝設定）＋狀態 pill；頂部不放啟停／暫停 |
| 面板內的瞬移／路線／搖桿膠囊模式列 | 底部 bottom bar 三個等寬 tab；最愛不設 tab |
| 搜尋在面板內輸入 | 全螢幕搜尋頁；鍵盤出現時隱藏地圖、pill、tabs |
| Go 位於候選 Pin 上方；點選置中候選 Pin | Go 兩處、同一動作：候選 Pin 上方小型 Go（約 28 pt 高，維持 44 pt 點擊範圍）＋地點 sheet 動作列第一個黑色按鈕；sheet 不放自明說明（如「Go 會把模擬位置移到此地點」）；點地圖不自動置中，Pin 被 sheet 遮住才最小平移 |
| 路線欄位選定後須確認才提交 | 點選結果即回填並返回；返回鍵取消 |
| 最愛：點星號即刪除；長按編輯標籤 | 點星號：變空心，約 0.5 秒後刪除；期間再點一次恢復實心＝取消；刪除後 snackbar「已刪除 1 項・復原」。「⋯」開編輯 sheet（改標籤、刪除）；「選取」多選批次刪除；底部固定「搜尋最愛地點」欄位（只搜尋已收藏地點） |
| 路線／漫步執行時沿用一般面板 | 執行模式：隱藏 tabs 與搜尋列，頂部深色指示卡，底部固定控制面板 |
| 右側地圖控制含圖層 | 只有指北、置中到模擬位置（執行模式加跟隨方向）；不做圖層 |
| 定位權限要求升級「永遠」 | 只請求「使用 App 期間」，顯示目前權限狀態，不提示升級 |
| 錯誤只用黑白高對比文字 | StatusBanner（danger／warning／success）固定在 sheet 或執行面板頂端；一次性結果用 snackbar |

### 新增 token（淺色值；深色依 iOS 系統色自動對應）

| Token | 值 | 用途 |
| --- | --- | --- |
| danger | `systemRed` #FF3B30；文字 #D70015 | 錯誤圖示、banner 邊與底（12%） |
| warning | `systemOrange` #FF9500；文字 #C93400 | 受限、權限不足 |
| success | `systemGreen` #34C759；文字 #248A3D | 需確認的成功、pill 色點 |
| snackbar | #1C1C1E 底、白字 | 不需處理的結果 |

深色值（Figma Dark 版使用，對應 iOS 系統色的 dark variant）：背景 #000000、卡片／sheet #1C1C1E、次要底與輸入 #2C2C2E、分隔線 #38383A、次要文字 #98989F、主要按鈕反轉為白底黑字、執行模式指示卡與 snackbar #2C2C2E；danger #FF453A（文字 #FF6961）、warning #FF9F0A（文字 #FFB340）、success #30D158；地圖採深色底圖。實作時用語意色自動切換，不寫死色碼。

其餘沿用本文件既有 token：`label`、`secondaryLabel`、`systemBackground`、`secondarySystemBackground`、`systemGray5` 輸入底、`separator`；主面板 20 pt、搜尋／地點 14 pt 連續圓角；浮層陰影 9%／y 5。

### 改版驗收條件（逐項結果見交付記錄）

- Bottom bar 三個 tab 等寬，標準與 Accessibility 字級都不截斷；執行模式與全螢幕頁面隱藏。
- 鍵盤出現時沒有任何面板被擠壓或遮住輸入框；搜尋框與結果列在外觀上可區分。
- 點地圖放 Pin 時鏡頭不動；Pin 被 sheet 遮住時才平移且平移量最小。
- 路線欄位點選結果一次即回填並返回；返回鍵保留原值。
- 最愛清單點星號後變空心，約 0.5 秒內再點可取消；逾時刪除並出現「已刪除 1 項・復原」snackbar。多選刪除後同樣可復原。
- 候選 Pin 上方與地點 sheet 都有 Go，兩者觸發同一瞬移；「位置待確認」時兩者都停用。
- 錯誤 banner 的說明內含修復指引（例如持續失敗請到「設定 › VPN 通道」修復），不另放在 sheet 底部。
- VPN 通道失敗頁與設定 › VPN 通道的「連線說明」開同一頁（Figma R05）。
- 匯入 GPX 路線不可編輯：不顯示把手、刪除、新增停靠點或反轉。10 點以下以唯讀清單完整列出；超過 10 點時 sheet 顯示摘要＋折疊點位（起點、第 2 點、「中間 N 點」、終點），最後一列「查看全部 N 點」開唯讀可捲動清單，點列只在地圖定位該點（2026-10-20 決定，Figma D6／D7）。
- 「開啟 LocalDevVPN」在首次引導與設定 › VPN 通道行為一致：未安裝（`localdevvpn://` 無法開啟）時改開 LocalDevVPN 的 App Store 頁；App Store 也打不開才提示手動搜尋。兩入口已共用 `GoFlyExternalLinks`；系統拒絕 URL、App Store fallback 與實際安裝情況仍待真機驗證。
- 搜尋（地圖全螢幕搜尋與路線欄位搜尋）同時比對最愛地點的自訂標籤（label），例如輸入「公司」可找到標為「公司」的最愛地點；結果列以標籤為標題、地址為副標。
- 首次引導定位頁顯示目前權限狀態：尚未設定（「允許定位」跳系統視窗，可略過）／已允許（綠色「已允許」，主要按鈕改「下一步」，不跳視窗、不顯示略過）／已拒絕（warning，主要按鈕改「前往設定」，仍可略過）。避免已允許時按鈕沒反應被誤以為壞掉（Figma R02／R03）。
- 設定子頁：定位權限、VPN 通道、背景執行、語言與外觀、裝置與簽名（Figma F4–F8）。
- GPX 匯入：「匯入 GPX 檔案」開系統檔案選擇器（GPX／XML、上限 2 MiB）；成功後新路線列在最上方並出現 snackbar（動作「載入」）；失敗以清單頂端 danger StatusBanner 說明原因，原清單不變（Figma D8–D10）。
- 已匯入路線清單：點一下路線開底部動作選單：載入路線、查看全部點位、匯出路線、刪除路線（紅字）、取消；不使用左滑。「載入路線」帶到路線 tab；「查看全部點位」開唯讀清單；「匯出路線」開系統分享 sheet 分享原檔；刪除後 snackbar 可復原（Figma D11–D12）。
- 全螢幕頁、sheet 與執行模式面板的底部主要按鈕，下緣一律對齊距螢幕底 34 pt（home indicator 上方）；有 bottom bar 的畫面則在 bottom bar 上方。
- 搖桿在搖桿 tab 與漫步執行模式使用同一尺寸（150 pt）。
- 右側地圖控制只有指北（地圖旋轉後才出現）與置中到模擬位置，執行模式多「跟隨方向」；不做圖層／Layers。控制組貼在 sheet／面板上方 16 pt，按鈕間距 8 pt。
- 候選 Pin 上方的小型 Go 約 28 pt 高，點擊範圍至少 44 × 44 pt。
- 路線 sheet 右上「路線資料夾」按鈕使用資料夾類 icon（例如 SF Symbol `folder`），不使用文件／`doc` 類 icon。
- 最愛清單：「⋯」開編輯 sheet（改標籤、刪除）；右上「選取」多選批次刪除；底部固定「搜尋最愛地點」只搜尋已收藏地點。
- 錯誤一律以 StatusBanner 呈現在 sheet／執行面板頂端，含圖示與文字，VoiceOver 朗讀嚴重度與標題；不只靠顏色。
- 路線與漫步的模擬箭頭依行進方位旋轉為既有功能需求；#15 箭頭方向問題屬獨立功能修正軌，本輪不宣稱已修復或通過。
- 背景持續不依賴定位權限：GoFly 只請求「使用 App 期間」，不要求「永遠」，也不顯示權限升級 sheet（2026-10-20 決定，取代原「非永遠時出現升級說明 sheet」條件）。
- 開始路線或漫步時送出一個 `com.neven.gofly.movement` 背景繼續運作任務（iOS 26 `BGContinuedProcessingTask`）；有終點路線顯示已確認距離比例，來回路線與漫步顯示不確定進度。
- 系統拒絕、不支援或讓任務到期時，移動暫停，回到前景以 StatusBanner 說明原因（`background.expired`／`background.rejected`／`background.unavailable`）；前景執行中、系統尚未啟動背景任務時被拒絕，只提示、不中斷前景移動。
- 切到其他 App 與鎖定螢幕後是否持續送點、任務多久會到期、到期後是否正確暫停，均**待真機驗證**；目前只有程式實作與單元測試，未有裝置結果。

### 改版實作狀態（2026-10-20）

- 步驟 0 盤點：完成，清單在 `work/gofly-ios/redesign/INVENTORY.md`（`work/` 不進版控）。
- 步驟 1 共用元件：**已實作**（`GoFlyStatusBanner`、`GoFlySnackbar`、`GoFlyStatusPill`、三段式 `GoFlyBottomSheet`、`GoFlyBottomBar`、執行模式 header／controls 骨架、danger／warning／success token）。**模擬器已驗證**淺色、深色、Accessibility XXXL，截圖在 `work/gofly-ios/redesign/step-1/`。
- 步驟 2 主畫面骨架：**已實作**浮動搜尋列＋齒輪、狀態 pill、右側指北／置中、三段式 sheet 骨架、三個等寬 bottom tab；舊的頂部狀態卡與面板內膠囊模式列已移除。**模擬器已驗證**淺色、深色、Accessibility XXXL，截圖在 `work/gofly-ios/redesign/step-2/`。
- 步驟 3 搜尋與瞬移：**已實作**全螢幕搜尋、最愛標籤比對、地點 sheet、兩處 Go 與點圖最小避讓。最近搜尋為目前地圖 view 記憶體內最多 8 筆。
- 步驟 4 路線：**已實作**點結果即回填、資料夾入口、GPX 匯入／匯出／刪除復原、唯讀摘要與全部點位、路線執行模式。
- 步驟 5 搖桿／漫步：**已實作**共用 150 pt 搖桿、隨機目的地次要按鈕、漫步執行模式與結束確認；結束維持既有取消漫步語意，不清除最後模擬位置。
- 步驟 6 最愛：**已實作**星號延遲刪除／取消、編輯 sheet、多選、單次批次復原與最愛搜尋。
- 步驟 7 錯誤：**已實作**StatusBanner／snackbar 統一與修復指引，保留診斷資訊與既有命令可用性。
- 步驟 8 引導／設定：**已實作**Logo 啟動、延遲進度、定位三態、共用 VPN 說明及 URL fallback、語言與外觀子頁、診斷匯出保留。
- 步驟 9：最終建置、測試、代表性視覺抽樣及未完成項目，以 `work/gofly-ios/redesign/RESULT.md` 為準。僅新增兩個直接 Core 驗收案例（最愛批次復原、GPX 原始 bytes），調整既有基本 UI 測試，選取 3 個視覺樣本；不新增複雜或排列組合預防性測試。不將本節實作狀態視為逐條驗收通過。
- **未經真機驗證**：GPS、VPN、背景任務、觸覺、VoiceOver 與裝置版面仍見 `.scratch/gofly-ios/DEVICE-ACCEPTANCE.md`；本輪未修改 Figma。箭頭方向 #15 與移動停止除錯仍分軌處理。
