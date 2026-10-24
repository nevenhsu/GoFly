# 04: 三模式箭頭在正常送點期間維持穩定

**Status:** implemented; software-verified

**Blocked by:** 01：建立三模式共用狀態投影與刷新基準。

**What to build:** 固定定位補送、路線行進與搖桿／漫步送點共用最後確認位置的顯示規則，消除正常 pending 導致的週期性明暗跳動。

- [ ] 有有效 ACK 的同一 owner 正常 pending 不把箭頭在 100%／50% 間往返；未 ACK 目標不成為已確認位置。
- [ ] 路線與漫步 GPS 模擬位置更新均有補間移動及最短角度平滑轉向；新 ACK 從當前可見位置接續，路線轉彎沿路段幾何、不切角。搖桿方向、地圖旋轉與來回方向仍正確。
- [ ] 正常 pending、probe、pill 刷新不重啟或打斷動畫；固定定位同座標補送不製造位移。顯示動畫不改變核心確認座標、進度或送點時間。
- [ ] 逾時、unconfirmed、斷線、Stop、clear、owner／epoch 改變使視覺保留立即失效；晚到 ACK 不復活舊任務。
- [ ] 停止或完成後，歷史模擬位置不被誤讀為仍在執行；GPS 與模擬位置來源維持可辨識。
- [ ] 底層 proof、dispatch、按鈕 admission、背景資格與已確認進度完全維持真實結果；保留既有 pending 不等同 ACK 的安全測試。
- [ ] 淺深色、VoiceOver、Reduce Motion 與三模式均驗證；實作前核對目前 iOS Figma 頁，將「正常刷新中」與「真正未確認」的規格及驗收同步更新，不假稱缺少的變體已設計。

實作及測試證據：`work/gofly-ios/flicker-optimization/RESULT.md`。最終文案／泛用錯誤定義依目前 `docs/IOS-UI-DESIGN.md` 與 `docs/IOS-STATUS-ERRORS.md`，取代票內較早連線專用用詞。手機／Figma待同步項不宣稱完成。
