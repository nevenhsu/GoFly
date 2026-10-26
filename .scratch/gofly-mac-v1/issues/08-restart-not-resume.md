# 08 · 中斷「重新開始」，移除接續

**Status:** todo
**Blocked by:** 07
**Spec:** MAC-INSTALLER-SPEC §5.4；`AGENTS.md`「iOS 實機測試安裝」（2026-10-26 已改成不接續）；Figma D14。

**Figma:** 照 `FIGMA-NODES.md` 的 D14（淺色＋深色）製作，先截圖並讀畫面下方說明；完成後 App 截圖存 `work/gofly-mac/v1/screens/` 並與 Figma 並排比對，見 TRACKER「UI 準據：Figma」。

**Scope**
- producer 新增「重新開始」：同一支手機有未完成交易時，先把舊交易標成 abandoned 並封存、作廢舊的未消耗配對，再重新觀察手機並建立新交易；已有 GoFly 時用 renew 覆蓋（保留資料），USB 時重新產生配對。不套用舊交易的配對，不刪除 App 或使用者資料。
- 目前 `transaction-conflict` 只在「同 setupID 重送」時保留；同機未完成交易改走重新開始。
- GUI 移除「繼續原交易／查詢原交易」；重開 App 有未完成交易時顯示 D14，只有「重新開始」。
- `scripts/install-ios-test.py`：移除 `resume`，`apply` 遇到未完成交易時走同一重新開始路徑；`status` 可保留為唯讀查詢或移除，與 `AGENTS.md`、`docs/AI-INSTALL.md` 一致。
- iOS 端：確認舊交接資料被作廢後，App 不會套用舊的 incoming／activation。

**Delete:** `MacSetupContinuation`、`canResume`、`resume()`、接續 UI，bridge 與腳本的 `resume` action，只為接續存在的 journal 欄位與測試。直接 `git rm`／刪除，不留相容入口或舊副本；見 TRACKER「舊代碼與舊 UI：該刪就刪」。

**Acceptance**
- 離線測試：各階段中斷（artifact、pairing、install unknown、support、handoff）後重新開始都會建立新交易、作廢舊配對、不重送舊 input；已完成交易仍照舊封存。
- 文件同步：`app/GoFlyMac/DEVELOPMENT.md`、`Bridge/PROTOCOL.md`、`AGENTS.md`、`docs/AI-INSTALL.md` 不再出現接續規則。

**Stop if:** 作廢配對需要刪除手機上已啟用（active）的配對或使用者資料。
