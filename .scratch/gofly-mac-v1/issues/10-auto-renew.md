# 10 · 自動延長簽名

**Status:** implemented; software-verified; visual-design-verified
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

**Evidence**
- Mac App 開啟時啟動排程，先等待唯讀環境與網路狀態，再執行一次檢查；之後每 24 小時檢查。檢查時間先落到本機偏好，避免失敗或重開後快速重試。Policy 覆蓋 4 天門檻、24 小時週期；裝置開關逐裝置保存，預設開啟；候選裝置優先使用 USB。
- 執行狀態驅動 D10／D11、macOS 通知與 IOPM sleep assertion；成功／失敗／取消會釋放 assertion。GoFlyMac Swift suite 65 tests passed，包含門檻、週期、裝置開關、USB 優先、操作中不觸發與 Wi‑Fi transport 規則。
- D08 開關及 D10、D11 淺／深色 App 截圖位於 `work/gofly-mac/v1/screens/`，已與 Figma V1 並排核對；D10／D11 本輪重新擷取與核對。

**Not verified**
- 未以真實長時間運行驗證 24 小時喚醒／排程；macOS 通知權限與送達、實際 IOPMAssertion 睡眠抑制，以及自動續簽的實機 receipt 仍待使用者操作驗收。
