# GoFly Mac V1 重構

日期：2026-10-26。依 [`docs/MAC-INSTALLER-SPEC.md`](../../docs/MAC-INSTALLER-SPEC.md)（設計已確認 v1）與 Figma「05 · Mac Redesign（新版）」的 V1 section 建立 12 張票。取代 `.scratch/prompts/03-mac-redesign.md` 與 `work/gofly-planning/MAC-RESET-BACKUP-PLAN.md`（備份／還原／重置／接續第一版不做）。逐票實作與驗收；軟體驗證不等於實機驗收。

| 票 | 狀態 | 依賴 | 驗收記錄 |
|---|---|---|---|
| 01 App 自給自足（內建 Python、iOS 專案、原生函式庫） | todo | — | |
| 02 依 Team 產生 Bundle ID | todo | 01 | |
| 03 全新 Mac 環境檢查（bridge `environment`） | todo | 01 | |
| 04 App 外殼、E00 啟動畫面與啟動路由 | todo | 03 | |
| 05 環境步驟頁 E01–E09 | todo | 04 | |
| 06 以裝置為中心的側欄與裝置頁狀態 | todo | 04 | |
| 07 首次安裝流程 D04–D07 | todo | 02、06 | |
| 08 中斷「重新開始」，移除接續 | todo | 07 | |
| 09 Wi‑Fi 延長簽名 | todo | 08 | |
| 10 自動延長簽名 | todo | 09 | |
| 11 DMG 與 install.sh | todo | 01、02 | |
| 12 文件與驗收清單收尾 | todo | 全部 | |

Figma 節點 ID 見 [`FIGMA-NODES.md`](FIGMA-NODES.md)。逐票證據、未驗證事項記在 `issues/` 對應票單。
