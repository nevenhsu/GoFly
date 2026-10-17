# 13: 連線修復、前景返回與冷啟動

**Status:** verification-pending

**Implementation:** complete

**Blocked by:** 08、12（4a0d9b3）實作及離線驗證完成；依序開始。

**What to build:** 中斷後顯示原模式的正確狀態；同process修復後明確繼續健康保留任務，冷啟動只還原資料與待確認摘要。

**Design reference:** 09、10 N04／N05、06 J03、08 O16。

**Acceptance criteria:**

- [x] VPN 中斷停止繼續送點；恢復只更新通道、不自動續跑，配對／開發者模式／缺少裝置準備分別提供具體 Mac 處理路徑。
- [x] 健康返回還原同一任務、方向及進度；中斷用路線／來回或漫步自己的暫停 UI，手動搖桿不捏造可續跑方向。
- [x] 冷啟動保存草稿、最愛與最後已知位置，不自動送點；現有native無任務查詢時不重建lease或舊Resume，移動／未決狀態只顯示待確認摘要並等待實際clear ACK；已停止／取消不復活，不補算中斷經過時間。

**Verification:** 重啟／切 App／VPN 斷復線／任務失效測試與實機生命週期驗收。

## Implementation record

2026-10-18：以4a0d9b3為實作／審查基準，configuredAdvisor第5輪核准Root v5；P13-01／02／03／04全部INCORPORATED，見decisions/13-recovery.md。build15開始，先模型／validated draft constructor再store與Service／Controller／coordinator；不操作手機，冷啟動不捏造native task proof或舊Resume。

整合讀回：first-route native claim在ACK之前獨立保存uncertainty，Stop待clear優先GPS待確認且active=nil，手動installed owner在settling保留directionless marker，前景fresh probe也封鎖wander Retry／suspended手勢續跑。上述公開回歸先行為RED後GREEN；僅compile／環境RED與舊來源已GREEN的monitor tracer另列。最新完整SwiftCore335／40suites＋Transport9／1suite，共344PASS；完整simulator回歸42／43（2017.930s，唯一失敗為舊RT預設值預期），test-only改成先明確設定live速度2／RT0再Load後，受影響單項1／1通過（210.374s）；其餘42項不重跑，合計43案例覆蓋，不將原run稱43／43。未簽署iPhoneOS build15、332key三語parser／格式／plutil、native mapper及personalized branch等3項邊界檢查、native verifier與diffcheck通過，Standards／Spec最後readback均0finding。實際裝置、接收位置與VoiceOver仍deferred-by-user；沒有連接／安裝／操作手機。 affected UI5／5的前置修正驗證亦通過228.360s。
