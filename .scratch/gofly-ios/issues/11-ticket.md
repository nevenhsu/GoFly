# 11: 手動搖桿與可選起點

**Status:** verification-pending

**Implementation:** complete

**Blocked by:** 04（91d0188）實作完成；依序於10（f039a95）提交後開始。

**What to build:** 設定有效起點後，用方向、力度與時速控制移動，放開停止該次手勢。

**Design reference:** 06 D05／F02。

**Acceptance criteria:**

- [x] 已確認模擬位置優先，再用有效 GPS；完全無位置顯示小型設定起點，共用 02 選點／Go 後回搖桿，未授權不阻擋。
- [x] 方向、力度、速度與箭頭一致；放開結束手動送點、保留最後模擬位置，不等同停止服務／clear。
- [x] 只有一個送點擁有者；暫停、停止、通道中斷、進背景都釋放輸入；遲到手勢／回覆不重啟或回放。

**Verification:** 方向／力度／速度／取消競態測試；實機搖桿與回中操作。

## Implementation record

2026-10-18：以f039a95為實作／審查基準，依Advisor已核准decisions/11-joystick.md與read-only凍結API執行。A負責JoystickCommanding／ServiceController preparation、FIFO最新origin及release settlement；B負責純vector／球面位移及clock/controller public TDD；Root負責Map／mode／scene／起點Go整合，UI待Core可編譯後接Panel／三語／UITests。沿既定public interface／device-adapter seams，不測private implementation。build13正式實作及離線驗證完成，真機集中最後驗收。

正式結果：完整SwiftCore260／30suites＋Transport9／1suite，共269PASS；完整simulator UI38／38 PASS（1713.531s）；未簽署iPhoneOS build13、304key三語parser／native verifier／diffcheck通過，Standards及Spec最後readback零finding。涵蓋世界方向／力度／速度／poles／日界、FIFO最新origin／CAS、prepare／release／claimedunknown／Stop、Pause→Resume neutral／舊neutral在新preclaim背景退休、已installed後續notSent可新手勢重試。App三mode／可選起點實際失敗保留候選、三語AX／keyboard及路線Pin無Go回歸均在同held run通過。沒有native ACK／GPS成功UI fixture；真實手勢、位置接收與VoiceOver仍deferred-by-user。Figma Console重試仍Transport closed，無雲端回寫。
