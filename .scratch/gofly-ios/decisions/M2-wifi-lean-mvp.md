# M2 Wi-Fi 續傳：瘦身 MVP 方案

狀態：**proposed / not-implemented**（2026-10-19 記錄，尚未取得實作核准）。此文件只記錄建議選項，不改動任何程式；現有 `reinstall_protocol.py` 仍為 `PROTOCOL = 3`，沒有 Wi-Fi 續傳能力。

背景：完整設計見 `work/gofly-ios/research/m2-wifi-plan-v3.md`。v3 的嚴格度（4096 筆 effect ledger、容量預留代數、32 版連線修訂、legacy 遷移矩陣…）遠超單人單機產品的 MVP 需求，且正式碼 0 行。本方案把範圍縮到「先做一個可實測的 Wi-Fi 續傳」，v3 降級為未來罕見邊界的參考。

## 目標場景

Mac 對同一支 iPhone，經 USB 或 Wi-Fi，在一次重裝／匯入**中斷之後**安全續傳：不重做已完成階段、不重送未知結果、不覆寫已完成的檔案。

## 最小安全設計

1. **傳輸**：重用既有 pinned adapter（USB／Network）。只在既有 reinstall 交易上加一個「通道」欄位。**不新增 protocol6、不加 connectionRevision／selectionID 域。**
2. **冪等來源**：以**逐檔內容雜湊**為唯一冪等依據。完整且雜湊相符 → 跳過；缺少或前綴相符的部分檔 → 只補傳缺的部分；**絕不覆寫已完整檔**。
3. **待續狀態**：一份 pending 記錄即可（交易 ID、通道、已完成清單摘要、待傳清單摘要）。**不做 revision 陣列、不做 effect ledger。**
4. **使用者閘**：流程只有「重新檢查原手機」→ 顯示實際狀態 → 使用者按「繼續」。**不做自動續跑。**
5. **未知結果**：一律**不重送**，回到「要求使用者介入」。**不做 lost-PID 自動證明、不做逐次 provenance。**
6. **legacy 舊紀錄**：**不做遷移矩陣**，直接明確提示「請重新走一次流程」。
7. **容量**：只保留單一「檔案數／位元組」上限檢查。**不做序列化最壞情況預留代數。**

## 明確不做（相對 v3）

- protocol6／connectionRevision／selectionID 域
- effectAttempts ledger、reservation 代數、每筆 8192 bytes、journal 16 MiB
- legacy 遷移矩陣
- embedded M1 逐次 launch／stop provenance、lost-PID 證明
- 每個 action 的對稱 response binding

## 驗收（MVP）

- 中斷後重開 → 顯示待續 → 檢查原手機 → 按繼續 → 只補缺檔 → 完成。
- 已完成的完整檔不被覆寫；未知結果不被重送。
- 實機由使用者集中驗收（不在開發期接手機）。

## 與 v3 的關係

v3 保留為完整設計參考，但**不作為 MVP 實作範圍**。若日後真的遇到罕見崩潰邊界，再從 v3 取用對應段落。
