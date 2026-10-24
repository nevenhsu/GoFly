# 05 · 確認目的地、更換地點與手動接管回路

狀態：已實作並完成軟體驗收。依賴：04。

## 本票變更

- E4 Pin「確認」與卡片「確認」共用重規劃命令；漫步候選 Pin 使用 DestPin。候選僅在道路規劃成功、起點仍為最新確認模擬座標時才替換現有目的地與路線。
- E2「更換地點」沿用相同重規劃流程，按目前速度選新終點；頂部卡不顯示第二個更換動作。
- 到達路段 ACK 後若使用者確認 DestPin，從該 ACK 座標規劃明確選定的新終點，沿用暫停中的 lease 接續，不要求再走一般 `.paused` 分支。
- 重規劃時暫停既有 ACK lease；成功後沿用同一 intent/lease 一次替換道路與目標再繼續。失敗保留舊目的地資料並停留在最後 ACK，透過規劃 Retry 重建。
- 手動接管期間以 ACK 提交位置；放開後中止舊折線取樣並重規劃到原目的地，不接回舊折線，不插入直線 connector。
- 手動搖桿模式的候選 Go 仍呼叫共用瞬移命令，成功後保留搖桿模式；E4 漫步確認不呼叫瞬移。

## 驗收

- Core：`manualTakeoverRequiresAReplacementRoadBeforeAutomaticMovementResumes`、`realArrivalWithoutNextTargetPausesAuthorityAndGoThenRetryUsesTheSameLease` 與 `failedRouteResumeKeepsThePriorDestinationAndRoute` 通過；確認保留原目的地、終點ACK後安裝下一段、接管後不送舊路線、沿用相同 owner，以及 resume 被拒時不提交新路線。背景失活時同一 resume gate 拒絕路線替換。
- Figma：票開始時讀取 E4/E2 Light/Dark；最終全畫面截圖又發現 E4 Light 缺候選 Pin、Dark 使用實心 CandidatePin。已在 Light/Dark 對應位置補上／替換空心 DestPin，與原路線目的地區分，修正後兩張畫面已重新截圖讀回。
- iOS Simulator build 與 native boundary 13情境通過；Core 275 tests通過。官方 check 的 Transport target有兩個 loopback `.socket` 失敗，見 tracker。
- `git diff --check` 通過。
- 未驗證：MapKit 真實道路服務、UI test與實機 ACK；本輪不操作實機。

補充已確認行為：漫步地圖 Pin 的地點卡出現時，panel 收至最小高度並保持；使用者可拖曳 grabber 拉高或點「搖桿」tab 展開，關閉卡片不自動恢復較高高度。淺深色共用行為。E4 Light/Dark 原渲染已呈現最小 panel，無需修改 Figma；App detent 行為已實作，iOS Simulator build通過。
