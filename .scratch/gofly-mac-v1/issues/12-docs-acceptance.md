# 12 · 文件與驗收清單收尾

**Status:** implemented; static-design-verified; pending user confirmation for Figma archive deletion
**Blocked by:** 01–11

**Scope**
- 改寫 `app/GoFlyMac/DEVELOPMENT.md`、`app/GoFlyMac/README.md`、`Bridge/PROTOCOL.md`，移除舊流程（首頁／首次安裝頁／裝置管理頁、接續、備份規則）。
- 更新 `.scratch/gofly-ios/MAC-DEVICE-ACCEPTANCE.md`：列出需要實機驗收的項目（全新 Mac 環境、USB 首次安裝、Wi‑Fi 延長簽名、自動延長、中斷重新開始、過期後延長的資料保留、免費 Team capability）。
- `docs/MAC-INSTALLER-SPEC.md` 與 `docs/MAC-UI-DESIGN.md` 標註實作現況；本 TRACKER 每票更新狀態與證據。

**Delete:** 文件中已取代的舊規則、`.scratch/prompts/03-mac-redesign.md`；Figma `Archive ·` section 在使用者確認 V1 後刪除。直接 `git rm`／刪除，不留相容入口或舊副本；見 TRACKER「舊代碼與舊 UI：該刪就刪」。

**Acceptance**
- 文件中「已實作／離線已驗證／待實機」標示正確，沒有證據的項目維持未驗。
- Mac 色彩集中在 Mac 專屬語意 token；色彩稽核確認 UI View 沒有散落的原始色值，且未共用 iOS 色彩程式。

**Evidence**
- 已改寫 Mac README／DEVELOPMENT／Bridge protocol、安裝與 UI 規格、三語 README、AI install 指引及 Mac 裝置驗收清單；文件把軟體證據與乾淨 Mac／實機驗收分開。已刪除被取代的 `.scratch/prompts/03-mac-redesign.md`。
- Swift 色彩稽核未在 `MacColorSystem.swift` 以外的 Mac SwiftUI source 找到原始 hex／RGB／NSColor／基礎 Color 色值；Mac token 集中於獨立的 `MacColorSystem.swift`，未匯入 iOS 色彩程式。`git diff --check` 通過。
- TRACKER 與 01–12 票單已依最新證據更新；E00–E09、D01–D14 淺／深色 App capture 存於 `work/gofly-mac/v1/screens/`，不代表實機操作證據。

**Not verified**
- Figma 頁面右側 68 個 `Archive ·` sections（34 淺色＋34 深色）依票單要求，待使用者確認 V1 後才刪除。
- 乾淨 Mac／其他帳號下載驗收及 USB、Wi‑Fi、自動續簽、交易中斷、資料保留與免費 Team capability 等實機項目列在 `.scratch/gofly-ios/MAC-DEVICE-ACCEPTANCE.md`，尚未操作手機。
