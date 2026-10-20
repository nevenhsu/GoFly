# GoFly 總重構：執行順序與共同規則（先讀這份）

你在 repo `/Users/neven/Documents/projects/ianygo` 工作。這份文件決定**做事的順序**與**何時才停下**。各任務的細節在同目錄的子 prompt：

| 檔案 | 任務 |
| --- | --- |
| `01-ui-ux-redesign.md` | iOS UI／UX flow 重構 |
| `02-debug-movement-stops.md` | iOS「模擬位置突然停止」除錯（A 本機 → B 手機 → C 修復） |
| `03-mac-redesign.md` | Mac UI／UX 改版，加上備份／還原／重置／更新簽名／取消接續 |
| `work/gofly-planning/MAC-RESET-BACKUP-PLAN.md` | 03 引用的 Mac 開發計畫（Phase 0–3，含兩處 iOS 改動） |

開始前讀 `AGENTS.md`，以及這份文件之後要執行的子 prompt 全文。

---

## 一、執行順序（iOS → Mac）

| 順序 | 任務 | 內容 | 完成條件 |
| --- | --- | --- | --- |
| 1 | 02 階段 A | iOS 診斷（`os.Logger`＋App 內診斷檔匯出）、能用單元測試重現的失敗測試、給使用者的手機重現步驟 | `check.sh` 通過；手機步驟寫在 `work/gofly-ios/debug-movement-stops/DEVICE-STEPS.md` |
| 2 | 01 步驟 0–9 | iOS UI 重構 | 每步 `check.sh` 通過、截圖、驗收條件勾選 |
| 3 | 02 階段 C | 使用者回傳手機證據後才做；在 01 某一步完成後的空檔插入，不要中斷進行中的步驟 | 依證據修復；給使用者修正後的驗證清單 |
| 4 | 檢查點 | 更新 `.scratch/gofly-ios/DEVICE-ACCEPTANCE.md`，列出 iOS 需要真機驗收的項目 | 清單完成即可繼續，不必等使用者驗收 |
| 5 | 03 步驟 0–4 | Mac UI 改版（環境、首次安裝、裝置管理、Wi‑Fi 限制、重新搜尋） | 建置與測試通過、截圖 |
| 6 | 計畫 Phase 0 | 取消接續：中斷即從頭重新開始 | 計畫第 9 節離線驗收 |
| 7 | 計畫 Phase 1 | iOS 偏好設定鏡像檔、bridge `backup`、備份管理頁、更新前備份 | 同上 |
| 7b | 計畫 Phase 1.5 | 更新簽名：版本比對＋不一致時的確認步驟（沿用 renew） | 同上 |
| 8 | 計畫 Phase 2 | 重置 GoFly | 同上 |
| 9 | 計畫 Phase 3 | 還原（bridge `restore`＋iOS `RestoreIngress`） | 同上 |
| 10 | 收尾 | 更新 `.scratch/gofly-ios/DEVICE-ACCEPTANCE.md`、`.scratch/gofly-ios/MAC-DEVICE-ACCEPTANCE.md`；整理所有文件 | 文件中「已實作／離線已驗證／待真機」標示正確 |

**順序理由**
- 1 先做：改動小，而且讓使用者盡早拿到可抓日誌的 build，手機測試可以和 2 平行。
- 2 與 1 的檔案範圍不同：2 主要改 `App/`；1 改 `Device/`、`Sources/GoFlyCore/` 與診斷匯出入口。
- 01 重構「設定 › 裝置與簽名」頁時，要保留 1 加入的「匯出診斷記錄」入口。

---

## 二、何時才停下（只有這些情況）

1. **需要使用者在手機或 Mac 上操作**：安裝、開關 App、拔插 USB、輸入密碼、在系統視窗點按、抓裝置日誌。把步驟寫清楚後，這個任務暫停，**改做順序中下一個不依賴它的任務**。
2. **會違反不變量**：`app/GoFly/ARCHITECTURE.md`「命令與送點」，或 `app/GoFlyMac/DEVELOPMENT.md` 的交易、完成判定、到期日規則。例外：計畫 Phase 0「中斷即重新開始」已核可。
3. **需要改原生 patch、FFI header 或重建 NativeBridge**。
4. **會刪除使用者資料，且條件與開發計畫不同**；或要改變備份／還原的資料範圍。
5. **需要憑證、簽署身分、Apple 帳號、付費服務**，或需要提交、推送到遠端。

**其他情況一律不停**，包括：
- 版面細節、文案、命名。
- 測試寫法、檔案拆分。
- 規格沒寫到的小狀態。
- 文件之間的小矛盾。
- comment #17 這類待外部確認的項目。

做法：照子 prompt 或計畫的建議做；沒有建議時，選最保守、最小、可逆的做法。把決定寫進 `work/gofly-dev/DECISIONS.md`（日期、任務、問題、選擇、理由、之後如何改），然後繼續。

---

## 三、共同規則

- **commit**：在目前分支，每個步驟一個 commit，只 `git add` 自己改的檔案。工作樹中原本就有使用者未提交的修改（onboarding、transport、文件），不要加入你的 commit，也不要還原。不推送、不開 PR。commit 前先跑該步驟的檢查。
- **驗證**：
  - iOS：`bash app/GoFly/scripts/check.sh`；改到原生邊界時加 `--device`。
  - Mac：`bash app/GoFlyMac/build-app.sh`、`swift test --package-path app/GoFlyMac`、bridge 的 Python 測試。
  - 失敗要修到通過；修不好時記在進度檔，並說明影響範圍。
- **進度檔**：`work/gofly-dev/PROGRESS.md`，每完成一步追加一段：
  - 任務與步驟、commit hash。
  - 改了哪些檔案、測試結果。
  - 截圖路徑、未完成項、待真機項。
- **文件同步**：規格有變就在同一步更新 `docs/IOS-UI-DESIGN.md`、`docs/MAC-UI-DESIGN.md`、`work/gofly-planning/GLOSSARY.md`、`app/GoFly/ARCHITECTURE.md`、`app/GoFlyMac/DEVELOPMENT.md`、`PROTOCOL.md`，直接改掉被取代的舊規則。
- **誠實標示**：模擬器、單元測試通過不等於真機通過。所有真機項目寫成「待真機驗收」，並集中到驗收清單。
- **禁止**：跑 Prettier、提交 `work/` 產出／憑證／配對檔／原始裝置日誌、修改 Figma、操作手機。

---

## 四、整體完成時交付

1. `work/gofly-dev/PROGRESS.md`：全部步驟的紀錄。
2. `work/gofly-dev/DECISIONS.md`：所有自行決定的事項。
3. 更新後的兩份真機驗收清單，給使用者一次性驗收。
4. 一段總結：
   - 完成了什麼、各任務的 commit 範圍。
   - 待使用者處理的事：手機步驟、待確認的設計問題。
   - 已知限制。
