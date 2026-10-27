# 08 · 中斷「重新開始」，移除接續

**Status:** implemented; software-verified; visual-design-verified
**Blocked by:** 07
**Spec:** MAC-INSTALLER-SPEC §5.4；`AGENTS.md`「iOS 實機測試安裝」（2026-10-26 已改成不接續）；Figma D14。

**Figma:** 照 `FIGMA-NODES.md` 的 D14（淺色＋深色）製作，先截圖並讀畫面下方說明；完成後 App 截圖存 `work/gofly-mac/v1/screens/` 並與 Figma 並排比對，見 TRACKER「UI 準據：Figma」。

**Scope**
- producer 新增「重新開始」：同一支手機有未完成交易時，封存舊交易，再重新觀察手機並建立新交易；已有 GoFly 時用 renew 覆蓋（保留資料），USB 時重新產生配對。不套用舊交易的配對，不刪除 App 或使用者資料。iOS 消費者先原子 rename `incoming.plist` 為 `.consuming` 才讀取／匯入；Mac restart 將未認領的 envelope 原子隔離到舊交易專屬路徑，再核對交易 ID、裝置 ID、pairing bytes 與 SHA-256 後只移除該隔離檔。iOS claim、替換或不明狀態會 fail closed；活動配對 store、activation receipt、舊 journal、App 與使用者資料均保留。
- 目前 `transaction-conflict` 只在「同 setupID 重送」時保留；同機未完成交易改走重新開始。
- GUI 移除「繼續原交易／查詢原交易」；重開 App 有未完成交易時顯示 D14，只有「重新開始」。
- `scripts/install-ios-test.py`：移除 `resume`，`apply` 遇到未完成交易時走同一重新開始路徑；`status` 可保留為唯讀查詢或移除，與 `AGENTS.md`、`docs/AI-INSTALL.md` 一致。
- iOS 端：確認舊交接資料被作廢後，App 不會套用舊的 incoming／activation。

**Delete:** `MacSetupContinuation`、`canResume`、`resume()`、接續 UI，bridge 與腳本的 `resume` action，只為接續存在的 journal 欄位與測試。直接 `git rm`／刪除，不留相容入口或舊副本；見 TRACKER「舊代碼與舊 UI：該刪就刪」。

**Acceptance**
- 離線測試：各階段中斷（artifact、pairing、install unknown、support、handoff）後重新開始都會建立新交易、建立新的 pairing candidate、不重送舊 input；handoff 中斷透過 Mac／iOS 原子 rename 仲裁，只移除完全匹配的未消耗 incoming envelope。另驗證 active pairing store、activation receipt、App 與使用者資料不動；已完成交易仍照舊封存。
- 文件同步：`app/GoFlyMac/DEVELOPMENT.md`、`Bridge/PROTOCOL.md`、`AGENTS.md`、`docs/AI-INSTALL.md` 說明新交易重啟與精確作廢 envelope 規則，沒有接續流程。

**Evidence**
- `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s app/GoFlyMac/Bridge/Setup/Tests -p 'test_*.py'`: 63 ran, 2 skipped；log: `work/gofly-mac/v1/ticket08-python-tests.log`。
- `xcrun swift test --package-path app/GoFlyMac --scratch-path work/gofly-mac/v1/swift-test --disable-sandbox`: 61 passed；log: `work/gofly-mac/v1/ticket08-swift-tests.log`。
- `bash app/GoFly/scripts/check.sh`: passed, including Swift package suites, five local handoff host scenarios, native-service boundary cases, and iOS Simulator build; summary log: `work/gofly-mac/v1/ticket08-ios-check.log`.
- Rollover tests cover iOS claiming first, a replacement at the well-known path, restoration of mismatched quarantined input, same-setupID replay with a disconnected device, and preservation of active pairing/receipt/App/user data.
- 離線案例覆蓋 artifact、pairing、install、support、handoff 未完成階段：以新 setup ID 與新 pairing candidate 開始；handoff 僅在舊交易、裝置、bytes、SHA-256 全部吻合時作廢未消耗的 `incoming.plist`。測試保留 active pairing、receipt、GoFly App 與使用者資料。
- 已搜尋 GoFly Mac bridge／UI／腳本的舊接續入口；resume action 僅留在負向測試中，確認 wire decoder 拒絕它。
- Figma D14 light `239:12269`、dark `239:13547` 與下方行為說明 `239:12331` 已截圖核對；App 截圖：`work/gofly-mac/v1/screens/D14-light.png`、`D14-dark.png`。D14 以明確 `wifi-device-not-found` 呈現 Wi-Fi 中斷，其他不明傳輸錯誤使用一般中斷說明。
- `plutil -lint` 通過三語 `.strings`，`git diff --check` 通過。

**Not verified**
- 未連接或寫入實體 iPhone；實際 USB 配對 rollover、安裝結果、activation receipt 與跨裝置 House Arrest rename 仲裁仍待實機驗收。
- D14 是離線交易 fixture；真實安裝中斷後以新 setup ID 從頭重做尚未在裝置驗證。

**Stop if:** 作廢配對需要刪除手機上已啟用（active）的配對或使用者資料。
