# 10 · 自動延長簽名

**Status:** todo
**Blocked by:** 09
**Spec:** MAC-INSTALLER-SPEC §5.3；Figma D10、D11、D08 開關。

**Figma:** 照 `FIGMA-NODES.md` 的 D08（開關）、D10、D11（淺色＋深色）製作，先截圖並讀畫面下方說明；完成後 App 截圖存 `work/gofly-mac/v1/screens/` 並與 Figma 並排比對，見 TRACKER「UI 準據：Figma」。

**Scope**
- 排程：Mac App 開著時，啟動時檢查一次，之後每 24 小時一次。
- 條件：已安裝 GoFly、簽名剩不到 4 天（含過期）、USB 或 Wi‑Fi 連得到（兩者都有用 USB）、Mac 能連網、沒有其他操作、該裝置的自動開關開啟（預設開）。
- 執行：自動顯示 D10「正在自動延長簽名」並發 macOS 通知；警告「不要關閉 Wi‑Fi、不要拔 USB、不要讓 Mac 睡眠或關閉 GoFly」；執行期間以 IOPMAssertion 保持喚醒；可取消。完成發通知並顯示 D11。
- 失敗或找不到手機：顯示 D14／D13，不立即重試，等下一次 24 小時檢查。

**Acceptance**
- 以可注入的時鐘測試：剩 4 天以上不觸發、剩不到 4 天觸發、過期觸發、有操作進行中不觸發、失敗後 24 小時才再試、開關關閉不觸發。
