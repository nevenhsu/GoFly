# 04 · App 外殼、E00 啟動畫面與啟動路由

**Status:** todo
**Blocked by:** 03
**Spec:** MAC-INSTALLER-SPEC §4、§5 開頭；Figma E00、Flow · 啟動流程、D01（側欄）。

**Figma:** 照 `FIGMA-NODES.md` 的 E00、Flow · 啟動流程、D01（側欄與底部 Mac 環境狀態）（淺色＋深色）製作，先截圖並讀畫面下方說明；完成後 App 截圖存 `work/gofly-mac/v1/screens/` 並與 Figma 並排比對，見 TRACKER「UI 準據：Figma」。

**Scope**
- 新的 `MacAppModel` 路由：啟動 → E00 啟動畫面（GoFly 圖示＋「GoFly for Mac」＋進度條＋「正在檢查 Mac 環境…」，500 ms 內完成不顯示）→
  - 全部通過 → 裝置頁；
  - 第一次開啟且 Xcode 未安裝 → E01；
  - 其他 → 第一個未完成的步驟（E02 → E03／E04 → E05 → E06 → E07 → E08）。
  - 檢查本身失敗 → 停在 E00 顯示「重新檢查」。
- 每個步驟頁自動偵測完成（App 回到前景時、加上步驟頁開著時低頻輪詢，例如 5 秒），完成就前往下一個未完成步驟，最後到裝置頁。
- 新側欄：環境流程顯示 6 個步驟（✓／目前／待做）；裝置頁顯示裝置清單、「↻ 重新搜尋」、底部「Mac 環境已就緒 · Team 名稱」（點擊開 E09）。
- 移除舊導覽（首頁／Mac 環境／首次安裝／裝置管理／備份）與舊頁面；不保留舊版首頁。
- 共用元件依 Figma 重做：StatusBanner、卡片列（圖示＋標題＋副標＋右側值）、步驟列、底部按鈕列、系統視窗示意圖容器＋「點這裡」標示。深淺色跟隨系統。

**Delete:** `MacEnvironmentGate.swift`、`MacPages.swift`、`MacRootView` 舊導覽、`MacPage` 舊頁面列舉與不再使用的資源。直接 `git rm`／刪除，不留相容入口或舊副本；見 TRACKER「舊代碼與舊 UI：該刪就刪」。

**Acceptance**
- Model 測試覆蓋四種啟動結果與自動前進。
- 每個畫面與 Figma 淺色、深色並排截圖比對（存 `work/gofly-mac/v1/screens/`），1000 × 700 可捲動、按鈕可達、鍵盤可聚焦。
