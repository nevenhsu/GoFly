# iOS 文字樣式規範：字級與文字顏色（2026-10-25）

App 內所有文字只用 `GoFlyFont`（字級，13 個 token）與 `GoFlyTextColor`（文字顏色，9 個角色），都定義在 `App/GoFlyStyle.swift`。它們都是 iOS 文字樣式，所以 Dynamic Type 仍然有效；只用兩種字重（Regular、Semibold），不用 Medium、Bold、Light。Figma 的原始字級沒有精修（10／11／12／13／14／15／16／17／18／20），統一對應到下表。

## 字級表

| Token | 樣式 | 預設大小 | 字重 | 用在 |
| :-- | :-- | :-- | :-- | :-- |
| `display` | `.title` | 28 | Semibold | 首次引導、設定準備頁的主標題 |
| `title` | `.title3` | 20 | Semibold | 所有 mode panel 標題（瞬移位置、路線、搖桿／漫步、恢復列）、導航卡標題、地點卡標題 |
| `headline` | `.headline` | 17 | Semibold | 頁面標題（導覽列）、dialog 標題、區段標題 |
| `body` | `.body` | 17 | Regular | 清單列、輸入欄、一般內文 |
| `bodyEmphasis` | `.body` | 17 | Semibold | 主要按鈕（開始、完成設定） |
| `subheadline` | `.subheadline` | 15 | Regular | 次要文字、dialog 說明 |
| `subheadlineEmphasis` | `.subheadline` | 15 | Semibold | 精簡按鈕（toast／snackbar／恢復列的按鈕）、toast 標題、chip |
| `footnote` | `.footnote` | 13 | Regular | 副標、toast 說明、地址、百分比 |
| `footnoteEmphasis` | `.footnote` | 13 | Semibold | 狀態 pill、小 chip |
| `caption` | `.caption` | 12 | Regular | 角色小標（起點／終點）、座標、軸線標籤 |
| `captionEmphasis` | `.caption` | 12 | Semibold | 需要強調的小標 |
| `micro` | 固定 10 | 10 | Semibold | TabBar 標籤、羅盤方位字母（不隨 Dynamic Type 放大） |
| `metric` | 固定 36 | 36 | Semibold | 時速大字 |

## 規則

1. 文字一律寫 `.font(GoFlyFont.xxx)`；不可直接寫 `.font(.footnote)`、`.font(.body)` 等原生樣式，也不可用 `.weight(.medium)`／`.bold`。
2. `.font(.system(size:…))` 只給圖示（SF Symbol）與圖形幾何（羅盤、指北箭頭、onboarding 大圖示），不給文字。
3. 同一個角色在不同畫面用同一個 token：panel 標題一律 `title`（20）；toast 標題 `subheadlineEmphasis`、說明 `footnote`；toast／snackbar 按鈕 `subheadlineEmphasis`；主要按鈕 `bodyEmphasis`。
4. 輔助字級（Dynamic Type 的 accessibility sizes）下面板改為內容定高；`micro` 與 `metric` 固定不放大，其餘 token 隨系統放大。
5. 新增文字先在此表找角色；表裡沒有的角色，先改這份文件與 `GoFlyFont`，不要在畫面裡自訂字級。

## 共用灰階色票

App 的中性灰集中定義於 `GoFlyGrayScale`。元件依語意選 token，不在畫面裡各自寫近似灰值；`GoFlyTextColor` 的 `secondary`、`message`、`disabled` 角色也由此引用。

| Token | 淺色 | 深色 | 用途 |
| :-- | :-- | :-- | :-- |
| `iconButtonSurface` | `#F2F2F7` | `#2C2C2E` | 啟用的灰底 icon button／次要控制底 |
| `iconButtonBorder` | `#E5E5EA` | `#38383A` | 啟用 icon button 邊線 |
| `routeControlSurface` | `#FFFFFF` | `#2C2C2E` | D6 來回／方向 icon button |
| `routeControlBorder` | `#C7C7CC` | `#38383A` | D6 來回／方向 icon button 邊線 |
| `disabledSurface` | `#EEEEF0` | `#2C2C2E` | 停用控制底 |
| `secondaryLabel` | `#8A8A8E` | `#98989F` | 次要文字與圖示 |
| `disabledLabel` | `#9999A0` | `#6B6B72` | 停用文字與圖示 |
| `messageLabel` | `#3C3C43` | `#D1D1D6` | Toast／dialog 說明文字 |
| `pasteSymbol` | `#6B6B6B` | `#FFFFFF` | 搜尋列系統貼上控制圖示 |
| `fieldSurface` | `#F2F2F7` | `#3A3A3C` | 搜尋欄與對話框取消底 |
| `fieldBorder` | `#8E8E93` | `#8E8E93` | 一般輸入欄外框 |
| `tabBarSurface` | `#F9F9F9` | `#1C1C1E` | 底部導覽列（另套 96% 不透明度） |
| `tabInactive` | `#999999` | `#999999` | 未選取 Tab 標籤 |
| `startSecondarySurface` | `#EEEEF0` | `#2C2C2E` | 最愛路線星號與次要開始按鈕；保持 Figma 無邊線外觀 |
| `dialogMessage` | `#6B6B73` | `#D1D1D6` | Dialog 補充說明 |
| `directionInactive` | `#C7C7CC` | `#C7C7CC` | D6 方向控制中未啟用的箭頭 |
| `checkboxOffBorder` | `#C7C7CC` | `#8E8E93` | 未選 checkbox 邊線 |
| `checkboxOffFill` | `#FFFFFF` | `#2C2C2E` | 未選 checkbox 底色 |
| `progressTrack` | `#E5E5EA` | `#2C2C2E` | Progress 軌道 |
| `durationWheelSurface` | `#F9F9FB` | `#242426` | 時長選擇 wheel 底色 |
| `durationWheelBorder` | `#E5E5EA` | `#38383B` | 時長選擇 wheel 邊線 |
| `hairline` | `#C6C6C8` | `#38383A` | 分隔線與一般細邊 |
| `pillBorder` | `#C6C6C8`（45%） | `#545458` | Status pill 邊線 |
| `toastDismiss` | `#8C8C94` | `#99999E` | Toast 關閉圖示 |
| `toastActionSurface` | `#FFFFFF` | `#2C2C2E` | Toast action 底色 |
| `toastActionBorder` | `#C6C6C8` | `#48484A` | Toast action 邊線 |
| `snackbarSurface` | `#1C1C1E` | `#2C2C2E` | Snackbar／執行提示卡底色 |
| `snackbarActionSurface` | `#FFFFFF` | `#3A3A3C` | Snackbar action 底色 |
| `snackbarActionBorder` | `#C6C6C8`（45%） | `#FFFFFF`（18%） | Snackbar action 邊線 |
| `snackbarBorder` | 透明 | `#FFFFFF`（12%） | Snackbar 外框 |

透明度只用於表內標記的邊線 token。icon-only disabled variant 尚未出現在 Figma 04；App 以 `iconButtonSurface` 表示一般啟用按鈕，停用改用 `disabledSurface`、`disabledLabel` 並移除邊線。Figma 明確指定無邊線 `#EEEEF0` 的最愛路線星號會保留其啟用底色，停用時仍以停用圖示色區分；依本文件的 App 狀態規格驗收。

## 文字顏色

文字（以及跟文字同角色的圖示）只用 `GoFlyTextColor`；深色模式由 token 內部切換，畫面不判斷 `colorScheme`。

| Token | 淺色 | 深色 | 用在 |
| :-- | :-- | :-- | :-- |
| `primary` | `#000000` | `#FFFFFF` | 標題、清單文字、主要標籤、一般按鈕文字 |
| `secondary` | `#8A8A8E` | `#98989F` | 副標、座標、placeholder、角色小標、未選的 TabBar 標籤、關閉 ✕ |
| `message` | `#3C3C43` | `#D1D1D6` | toast 與 dialog 裡補充標題的說明文字 |
| `disabled` | `#9999A0` | `#6B6B72` | 停用的按鈕、不可用的清單列 |
| `inverse` | 頁面底色（白） | 頁面底色（黑） | 主要色（黑／白）填滿上的文字（主要按鈕、選中的 chip） |
| `onDark` | `#FFFFFF` | `#FFFFFF` | 固定深色面上的文字：snackbar、頂部導航卡、危險（紅色）按鈕 |
| `danger` | `#D70015` | `#FF6961` | 錯誤文字（不可用原因、刪除） |
| `warning` | `#C93400` | `#FFB340` | 警告文字 |
| `success` | `#248A3D` | `#30D158` | 成功文字 |

規則：

1. 不直接寫 `Color.black`／`.white`／`.secondary`，也不用 `GoFlyStyle.primary`／`secondary` 當文字色；一律 `GoFlyTextColor.xxx`。
2. 狀態圖示（toast 的警示圖示、pill 圓點）用狀態色（`tone.tint`、`GoFlyStyle.danger` 等），不算文字色。
3. Figma 的灰色（`#8A8A8E`、`#8C8C94`、`#999999`、`#6B6B73`、`#3C3C43`）分別併入 `secondary`、`secondary`、`secondary`、`message`、`message`；停用色與深淺色對應沿用同一組。
4. 新增文字角色時先改本表與 `GoFlyTextColor`；新增中性灰先改 `GoFlyGrayScale`，不要在畫面裡自訂顏色。

## 由舊字級對應

| 舊用法 | 新 token |
| :-- | :-- |
| 28 Bold／Semibold、`.title` | `display` |
| 18／20 Semibold／Bold、`.title2`、`.title3` | `title`（panel 與卡片標題）或 `headline`（dialog 標題、頁面標題） |
| 16／17 Semibold、`.headline` | `headline` |
| 17、`.body`；17 Medium／Semibold | `body`；`bodyEmphasis` |
| 14／15 Regular | `subheadline` |
| 14／15 Medium／Semibold | `subheadlineEmphasis` |
| 13 Regular、`.footnote` | `footnote` |
| 13 Medium／Semibold | `footnoteEmphasis` |
| 11／12、`.caption`、`.caption2` | `caption`（強調時 `captionEmphasis`） |
| 10 | `micro` |
| 36 Bold | `metric` |

## 驗證

`TypographyStandardTests`（`Tests/GoFlyCoreTests`）掃描 `App/*.swift`：不可出現原生文字樣式直接當 `.font(…)` 參數、不可出現 Medium／Bold 字重、`.system(size:)` 只能出現在圖示附近；`.foregroundStyle`／`.foregroundColor` 不可用原始顏色，只能是 `GoFlyTextColor` 角色（或狀態色）。新增文字樣式要同步更新本文件與該測試的白名單。
