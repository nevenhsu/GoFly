# 05 · 環境步驟頁 E01–E09

**Status:** todo
**Blocked by:** 04
**Spec:** MAC-INSTALLER-SPEC §4 表格；Figma E01–E09（含畫面下方說明）。

**Figma:** 照 `FIGMA-NODES.md` 的 E01–E09（淺色＋深色）製作，先截圖並讀畫面下方說明；完成後 App 截圖存 `work/gofly-mac/v1/screens/` 並與 Figma 並排比對，見 TRACKER「UI 準據：Figma」。

**Scope**
- 照 Figma 做 E01 總覽、E02 macOS 更新、E03 App Store 取得 Xcode、E04 等待 Xcode 安裝（不顯示假百分比，提示先在 iPhone 安裝 LocalDevVPN）、E05 首次開啟 Xcode、E06 iOS 平台、E07 登入 Apple 帳號（含「免費建立 Apple 帳號」開 Apple 官方網頁）、E08 選擇 Team（1 個時自動選取並略過）、E09 檢查結果（從側欄開，可重新檢查、更換 Team、返回裝置）。
- 按鈕只開啟 App Store（`macappstore://apps.apple.com/app/id497799835`）、Xcode、系統設定軟體更新、Xcode Settings、網頁；不代替使用者點擊或輸入。
- 系統視窗示意圖用 SwiftUI 繪製（不放截圖），文案指明是哪一種密碼。
- 三語字串（en／zh-Hant／zh-Hans）。

**Delete:** 舊環境頁與舊引導卡片的殘留字串、資源。直接 `git rm`／刪除，不留相容入口或舊副本；見 TRACKER「舊代碼與舊 UI：該刪就刪」。

**Acceptance**
- 每頁淺深色截圖與 Figma 對照；更換 Team 會提示「iPhone 上會變成另一個 GoFly」。
