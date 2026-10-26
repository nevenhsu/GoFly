# 07 · 首次安裝流程 D04–D07

**Status:** todo
**Blocked by:** 02、06
**Spec:** MAC-INSTALLER-SPEC §5.1；Figma D04–D07、D05 鑰匙圈示意。

**Figma:** 照 `FIGMA-NODES.md` 的 D04–D07（淺色＋深色）製作，先截圖並讀畫面下方說明；完成後 App 截圖存 `work/gofly-mac/v1/screens/` 並與 Figma 並排比對，見 TRACKER「UI 準據：Figma」。

**Scope**
- D04「安裝 GoFly」→ 自動 preflight → apply（mode install），使用 Team 與 01／02 的 bundle 內 iOS 專案。
- D05 進度列：建置 → 簽名 → 安裝到 iPhone → 交付配對 → 準備裝置支援，依 bridge 實際回報更新；簽名等待鑰匙圈超過數秒時在右側顯示鑰匙圈示意（Mac 登入密碼、點「永遠允許」）。
- D06 等待 activation receipt：列出信任開發者（免費 Team 才顯示）、安裝 LocalDevVPN、開啟 GoFly；讀到 receipt 才進 D07。
- D07 顯示實際讀回的到期日；讀不到寫「未取得」。
- 完成判定沿用 DEVELOPMENT.md：部署、本次配對匯入、同機支援、activation receipt 全部確認。

**Delete:** `MacSetupPage.swift` 舊安裝表單、4 步首次安裝頁、I08「已安裝 GoFly」頁。直接 `git rm`／刪除，不留相容入口或舊副本；見 TRACKER「舊代碼與舊 UI：該刪就刪」。

**Acceptance**
- 離線以假 bridge 跑完整流程與各階段失敗；截圖對照 Figma。實機首次安裝列入 `.scratch/gofly-ios/MAC-DEVICE-ACCEPTANCE.md`，不宣稱已驗。
