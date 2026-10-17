# 08: 來回走動、即時改向與最後一段收尾

**Status:** verification-pending

**Implementation:** complete

**Blocked by:** 06（9057718）、07（d98f8c7）實作／自動驗證完成；手機集中驗收。

**What to build:** 沿同一路線往返，可從目前位置改向，取消來回後走到下一端點結束。

**Design reference:** 04 L02／L03、REF04。

**Acceptance criteria:**

- [ ] 固定起點 0%、終點 100%；改向、途經點、端點折返及暫停都不跳位置或重設座標軸。
- [ ] 勾選來回時同列無框方向切換；改向沿原路徑反向，保持速度、草稿及任務；暫停改向仍暫停。
- [ ] 關閉來回不改向，維持原位置軸到下一端點結束；依最新 REF04 收起方向切換控制，頂部仍顯示實際目標；下次新單次任務才用一般進度。

**Verification:** 順逆向／端點／中途取消來回／暫停改向的距離與命令測試；實機往返。


## Implementation record

2026-10-17：實作／審查基準d98f8c7。Advisor核准decisions/08-roundtrip.md及lease-scoped control revision／未claim watchdog抑制／既有timeout隔離細節，開始Core公開邊界TDD與UI整合。未操作手機；實作及自動驗證完成後直接繼續下一票。


已完成Core／App實作並凍結：focused64／5與完整Swift Core141／16＋Transport9共150通過，未簽署iPhoneOS build10成功。三語198keys／parser、native verifier與diffcheck通過，Standards／Spec最後source均零finding。最大字級的Back命中36pt及英語截字均經實際UI失敗修正，最後三語AX實測與Root目視完整可讀，沒有以單純frame斷言掩蓋ellipsis。完整25／25 UI通過（688.876s，/private/tmp/gofly-ui-final08.xcresult），Implementation complete；手機仍deferred-by-user，無安裝或操作。


以上為host／模擬器／編譯證據，沒有native成功／GPS fixture冒充實機。實際接收App往返、即時改向與最大字級active方向手感仍待最後手機批次，維持verification-pending而不標done。依安排直接繼續09。
