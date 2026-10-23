# iOS Figma Bug Report 修正計劃

更新日期：2026-10-23
狀態：程式修改完成，iOS Simulator build 成功；iPhone 已安裝 build 28，等待使用者進行 UI／定位驗收。

## 範圍與依據

- Figma `Bug Report` 頁中釘在 8 張實機截圖（`IMG_6364`–`IMG_6371`）的 13 則留言。
- iOS 視覺對照以 [04 · iOS Redesign（Google Maps 參考）](https://www.figma.com/design/RtPV8PXCQJ2WXK3jk3kPrq/GoFly-%C2%B7-UI-%E7%B7%9A%E6%A1%86%E8%A8%8E%E8%AB%96?node-id=121-50359) 為準：R01 啟動畫面、B1–B8.a 地圖／瞬移、C2 編輯最愛。
- 本計劃只涵蓋 `Bug Report` 頁的留言；釘在舊 `01 · iOS App` 頁的其他留言不納入。
- 既有 commit 和目前工作目錄的未提交修改都要先逐項核對。不可把「有相關程式碼」直接當成已完成或真機已驗收，也不可覆蓋既有未提交修改。

## 留言對照與修正項目

| ID | Bug Report 證據 | 留言重點 | 計劃與新版 Figma 對照 | 驗收條件 |
| --- | --- | --- | --- | --- |
| BR-01 | `IMG_6371` · [截圖節點](https://www.figma.com/design/RtPV8PXCQJ2WXK3jk3kPrq/GoFly-%C2%B7-UI-%E7%B7%9A%E6%A1%86%E8%A8%8E%E8%AB%96?node-id=200-9787) · 留言 20 | 開啟手機時閃過目前畫面；R01 的 Logo 為設計標準。 | 比對實機啟動瞬間與新版 R01（GoFly 標誌、名稱、短進度指示），找出目前閃屏來自系統 Launch Screen 或 App 內啟動畫面，再決定最小修正。Commit `05ef87c` 已加入 GoFly Logo launch asset/storyboard，但這不代表已符合 R01 或已通過真機視覺驗收。 | 冷啟動時不再閃過與 R01 不一致的舊畫面；啟動畫面的品牌圖像及轉入首頁符合 R01。記錄實機型號、iOS 版本與錄影／截圖。 |
| BR-02 | `IMG_6364` · [截圖節點](https://www.figma.com/design/RtPV8PXCQJ2WXK3jk3kPrq/GoFly-%C2%B7-UI-%E7%B7%9A%E6%A1%86%E8%A8%8E%E8%AB%96?node-id=200-9780) · 留言 23 | 地圖首頁 panel 預設高度應為最窄版本，對照 B1。 | 核對首次進入瞬移地圖時的 sheet detent 與內容；依 B1 收合狀態設定預設高度，不因最愛／最近清單而初始展開。 | 冷啟動及返回瞬移首頁時，初始 panel 高度符合 B1，地圖露出量一致；展開操作仍可使用。 |
| BR-03 | `IMG_6364`、`IMG_6369` · [截圖 6364](https://www.figma.com/design/RtPV8PXCQJ2WXK3jk3kPrq/GoFly-%C2%B7-UI-%E7%B7%9A%E6%A1%86%E8%A8%8E%E8%AB%96?node-id=200-9780) · [截圖 6369](https://www.figma.com/design/RtPV8PXCQJ2WXK3jk3kPrq/GoFly-%C2%B7-UI-%E7%B7%9A%E6%A1%86%E8%A8%8E%E8%AB%96?node-id=200-9785) · 留言 24、29 | `Needs attention` 太含糊，應直接說連線中斷；設定已啟動但地圖 status chip 狀態錯誤，應和連線狀態連動。 | 以同一個可觀察服務／連線狀態決定設定頁狀態與地圖 pill 的文案、語意色和狀態。連線中斷時使用明確文案；不要讓設定頁顯示 Running 而地圖同時顯示需注意，除非狀態模型明確表示兩者不同。 | 在 Running、連線中斷、恢復中及已恢復狀態下，設定頁與地圖的狀態描述一致且符合實際狀態；警告使用 warning 語意，不以模糊文案取代原因。 |
| BR-04 | `IMG_6364` · [截圖節點](https://www.figma.com/design/RtPV8PXCQJ2WXK3jk3kPrq/GoFly-%C2%B7-UI-%E7%B7%9A%E6%A1%86%E8%A8%8E%E8%AB%96?node-id=200-9780) · 留言 22、24 | 斷線但有真實 GPS 時箭頭應為藍色；狀態應明確反映連線中斷。 | 對照 B8 與 `RealArrow` 元件。區分真實 GPS 與模擬位置標記，不以一般黑色／等待樣式代替 B8 藍色實心箭頭；同步核對 pill。 | 注入或實際觀察「斷線、有新鮮真實 GPS」狀態時，箭頭為新版 B8 藍色樣式，狀態文字明確；沒有真實 GPS 時不得沿用此樣式。 |
| BR-05 | `IMG_6366` · [截圖節點](https://www.figma.com/design/RtPV8PXCQJ2WXK3jk3kPrq/GoFly-%C2%B7-UI-%E7%B7%9A%E6%A1%86%E8%A8%8E%E8%AB%96?node-id=200-9782) · 留言 21、25、26 | B8.a 無真實 GPS 時箭頭應灰色；Toast UI 不符 B8 標準；panel 高度應縮至最小。 | 對照 B8.a：最後模擬位置標籤、灰色模擬箭頭、獨立頂部 warning Toast、精簡恢復 panel。Bug Report 截圖中的 GPS 未確認 Toast 與位置卡，不應混為同一個恢復狀態；要按實際狀態選用 B8 或 B8.a。 | 無真實 GPS 時，標題明確為最後模擬位置、箭頭灰色；Toast 位置／樣式／重試與關閉入口符合對應畫面；panel 高度和 CTA 符合新版恢復畫面。 |
| BR-06 | `IMG_6368` · [截圖節點](https://www.figma.com/design/RtPV8PXCQJ2WXK3jk3kPrq/GoFly-%C2%B7-UI-%E7%B7%9A%E6%A1%86%E8%A8%8E%E8%AB%96?node-id=200-9784) · 留言 27、28 | 點最愛顯示 Pin 時地圖要往下移，讓 Pin 到畫面中央；Location Card 應覆蓋 bottom bar 和 panel。 | 對照新版 B5 的選點與地點卡。有候選地點時以整個地圖畫面作鏡頭中心，讓搜尋列／浮動卡片避開 Pin；地點資訊卡作為獨立浮層，不塞入或撐高原操作 panel。 | 點選最愛或地圖候選點後，Pin 不被頂部搜尋列／底部控制遮擋；Location Card 浮在底部導覽與 panel 上方，關閉後恢復原 panel 狀態。 |
| BR-07 | `IMG_6365`、`IMG_6369` · [截圖 6365](https://www.figma.com/design/RtPV8PXCQJ2WXK3jk3kPrq/GoFly-%C2%B7-UI-%E7%B7%9A%E6%A1%86%E8%A8%8E%E8%AB%96?node-id=200-9781) · [截圖 6369](https://www.figma.com/design/RtPV8PXCQJ2WXK3jk3kPrq/GoFly-%C2%B7-UI-%E7%B7%9A%E6%A1%86%E8%A8%8E%E8%AB%96?node-id=200-9785) · 留言 29、30 | 設定頁顯示 Running；另一張地圖畫面 chip 顯示 Needs attention，留言要求狀態連動。 | 以兩張截圖作為同一項狀態一致性回報處理，不把「設定 status 已經是 running」重複拆成新功能。狀態來源與文案仍須先依既有模型確認。 | 同一服務狀態在兩入口顯示一致；若狀態不同，畫面須表達不同狀態的具體依據。 |
| BR-08 | `IMG_6367` · [截圖節點](https://www.figma.com/design/RtPV8PXCQJ2WXK3jk3kPrq/GoFly-%C2%B7-UI-%E7%B7%9A%E6%A1%86%E8%A8%8E%E8%AB%96?node-id=200-9783) · 留言 31 | 編輯最愛 panel 對齊 C2；刪除文案改為 `Delete`；地址和 Save 間距太大。 | 對照新版 C2 編輯最愛 sheet。這是 Bug Report 頁的有效項目，但不屬瞬移中斷／GPS 主流程，列為相鄰修正，與瞬移修正分開驗收。 | 編輯最愛 sheet 的刪除按鈕文案依確認規格一致；地址卡和 Save 之間沒有截圖所示的大段空白；繁中／英文版皆檢視。 |
| BR-09 | `IMG_6370` · [截圖節點](https://www.figma.com/design/RtPV8PXCQJ2WXK3jk3kPrq/GoFly-%C2%B7-UI-%E7%B7%9A%E6%A1%86%E8%A8%8E%E8%AB%96?node-id=200-9786) · 留言 32 | 狀態 chip 文字／顏色錯誤，應為 warning；panel 標題依 GPS 自動更新為 B8 或 B8.a。 | 將 BR-03、BR-04、BR-05 合併成同一狀態呈現規則：warning 語意、依真實 GPS 條件切換面板標題和箭頭。避免同一個狀態 bug 重複實作。 | 有真實 GPS 時呈現 B8 標題／藍色箭頭；無真實 GPS 時呈現 B8.a 標題／灰色箭頭；狀態 chip 均用與狀態相符的 warning 樣式。 |

## 實作紀錄（2026-10-23）

| ID | 實作結果 | 尚待驗收 |
| --- | --- | --- |
| BR-01 | 系統 Launch Screen 與 App 內 Startup View 加入 GoFly 字標及短進度條，圖標與名稱組成置中。 | 冷啟動過渡及實機尺寸／深色外觀。 |
| BR-02 | 地圖初始 detent 改為收合，保留無障礙字級自動展開。 | 初次啟動、返回首頁及面板手勢。 |
| BR-03／BR-07／BR-09 | 移除模擬標記等待造成的誤報 warning；有連線中斷 recovery notice 時 pill 顯示明確「連線中斷」並使用 warning tone。 | 設定頁與地圖於實際斷線、恢復各狀態的一致性。 |
| BR-04／BR-05 | 新鮮 GPS 箭頭改為藍色實心；等待 GPS 或模擬位置採灰色實心樣式。恢復面板依新鮮 GPS 顯示「目前位置」或「最後模擬位置」。 | 真實定位狀態、箭頭對比及 B8/B8.a 轉換。 |
| BR-06 | 保留既有 Location Card 浮層與底部操作；已存在候選地圖可視區避讓。 | Pin 中央位置及 Location Card 對底部導覽／panel 的覆蓋實機核對。 |
| BR-08 | C2 刪除文字改為 Delete／刪除；編輯 sheet 改用 360 pt 初始 detent，縮小表單內容間距，仍可展開。 | 繁中／英文排版、鍵盤及可及性字級。 |

這些是程式修改結果，不等於建置成功或真機驗收通過。Bug Report 截圖所示 Location Card、warning toast、恢復面板與多語字串中已有未提交實作，保留並納入核對；不將其誤標為本次從零新增。

### 裝置交付紀錄

- 2026-10-23：依 `scripts/install-ios-test.sh --action preflight` 與 `--action apply --mode renew` 對先前已核對的 USB iPhone 執行唯讀預檢及覆蓋安裝，沿用原簽署 Team，未啟用佈建更新。預檢確認安裝前為 build 28；正式交易 `f0ff948f-fc54-4827-ba23-d4e9602c41e7` 回報 `complete=true`、`outcome=confirmed`，且 `installationConfirmed`、`pairingImported`、`supportObserved` 全為 true；簽署期限回報為 2027-10-17。未卸載 App、未清除資料。
- 此紀錄只確認 App／配對／支援交付；尚未確認實機畫面是否符合 R01、B1、B5、B8／B8.a、C2，也未驗證斷線轉換、GPS 箭頭或外部 App 定位效果。

## 修正順序

1. **先做狀態與畫面基線盤點**：對照 `05ef87c`、`42a2642` 等相關 commit，以及目前未提交 diff；逐條標為「已實作待真機核對」「有未提交修改」「尚未實作」或「與新版 Figma 不符」。保留既有使用者修改。
2. **先修共用狀態語意**：處理 BR-03、BR-07、BR-09 的狀態來源、文字、warning 顏色與 GPS 條件分流，避免各畫面各自猜狀態。
3. **修瞬移地圖呈現**：處理 BR-02、BR-04、BR-05、BR-06 的初始 panel、B8／B8.a 位置箭頭、Toast、恢復 panel、Pin 位置與浮動 Location Card。
4. **修啟動畫面**：處理 BR-01；既有 Logo commit 保留，依實機冷啟動畫面決定是否還需調整 Launch Screen／啟動過渡。
5. **相鄰項目獨立處理**：BR-08 編輯最愛對齊 C2，不與瞬移狀態修正混在同一驗收步驟。
6. **真機核對**：記錄 App build、iPhone 型號、iOS 版本及每項實際畫面。安裝／更新須依 `docs/AI-INSTALL.md` 與 `scripts/install-ios-test.sh` 的正式流程執行；安裝成功不視為 UI／定位驗收通過。

## 共同驗收紀錄

- 淺色／深色各核對適用的 B1、B5、B8、B8.a、R01 與 C2 畫面；若新版 Figma 缺少對應變體，記為未定義，不推測設計。
- 將視覺核對、狀態轉換核對與外部 App 定位效果分開記錄。
- 不以 commit 存在、模擬器截圖或安裝成功宣稱真機 UI 已通過。
- 實作差異已回寫相關 iOS UI 規格；本計劃記錄的實作仍須建置及真機驗收。
