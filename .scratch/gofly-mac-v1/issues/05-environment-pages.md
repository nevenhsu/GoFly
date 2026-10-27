# 05 · 環境步驟頁 E01–E09

**Status:** implemented; software-verified
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

## Evidence
- E01–E09 已完成並與 Figma V1 淺／深色節點及各節點下方說明逐頁比對；E00 啟動畫面列於票 04。App 截圖：[`E01-light.png`](../../../work/gofly-mac/v1/screens/E01-light.png)／[`E01-dark.png`](../../../work/gofly-mac/v1/screens/E01-dark.png) 至 [`E09-light.png`](../../../work/gofly-mac/v1/screens/E09-light.png)／[`E09-dark.png`](../../../work/gofly-mac/v1/screens/E09-dark.png)。E09 深色圖已於 2026-10-27 重擷取，檔案可正常讀取。
- E06 保留「設計待驗證」標記；操作步驟已寫入 `work/gofly-mac/v1/E06-VERIFY.md`，不宣稱需求已由乾淨 Mac 證實。
- Swift 離線測試：60 tests / 4 suites 全過；三語 `.strings` plist lint 通過。系統設定、App Store、Xcode 與 Apple 網頁按鈕使用開啟動作，未實際操作使用者帳號。
- Mac 色彩由 Mac 專屬語意 token 提供，淺／深外觀相符；不依賴 iOS 色彩實作。

## Not verified
- E06 是否可從必要建置流程移除，需依 `E06-VERIFY.md` 在乾淨 Mac 實測；未下載 iOS SDK 或操作 Apple 帳號。
- 實際 App Store/Xcode 安裝偵測、軟體更新、Apple 登入與不同數量 Team 狀態仍需在乾淨 Mac 操作驗收；未連接實體 iPhone。最小視窗與鍵盤操作未人工驗收。
