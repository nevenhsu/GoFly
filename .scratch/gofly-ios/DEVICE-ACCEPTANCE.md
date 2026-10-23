# 集中手機驗收清單
全部項目待手機驗收；開發期間不接手機、不安裝。逐項勾選並記錄 build。
## 安裝與首次流程
- [ ] Mac App 建置並開啟 Setup 頁；首次安裝（install）完成，iPhone 先顯示 Logo，設定檢查超過約 0.5 秒才顯示細進度；准入後顯示歡迎頁。
- [ ] 已安裝後在 Mac 裝置頁按「重新簽名」或重新選取裝置；renew 以同 Bundle 覆蓋，App 資料保留。
- [ ] renew 完成顯示 `expiresAt`（讀不到時為 null）；中斷後 resume 不會重送 install。
- [ ] 首次流程只要求定位權限與 VPN 可達；Start 不移動位置。
## 冷啟動與連線

- [ ] 上次在模擬位置時終止 App，重開：自動送一次 clear；成功後提示消失，session 的 active／uncertainty 清空。
- [ ] 冷啟動時 VPN 未連線或 native 未就緒：clear 失敗但**不彈錯誤、不顯示服務錯誤**，地圖保留「上次模擬位置可能還在」提示。
- [ ] 冷啟動 clear 失敗後直接 Start：Start 可正常進行，不被 pending 卡住。
- [ ] 冷啟動成功或失敗後按 Restore／Stop 並成功：提示消失、session 紀錄清空；失敗後不自動重試。
- [ ] 切 App、VPN 斷復線、前景返回：狀態與提示一致，不復活舊任務。

## 單點／路線／搖桿

- [ ] 選點後 Go：兩個接收 App 位置一致；取消／Stop 後不再送點。
- [ ] 送點回覆不明：Go 鎖住，有效 GPS 不解鎖，只有明確 Stop 完成後可再操作。
- [ ] 兩點與多點路線：開始、暫停、取消、自然完成；路徑與接收端位置一致。
- [ ] 來回與漫步：抵達換點、手動接管、放開；漫步只取一個隨機方向，可能靠近最近去過的地點。
- [ ] 手動搖桿方向／力度／速度與回中。

## 背景最小 driver

- [ ] 有終點路線在背景自然完成：背景任務結束，回前景不再顯示執行中。
- [ ] 來回／漫步在背景：不確定進度仍可持續；系統到期時任務暫停，回前景提示。
- [ ] 背景任務 ID 與 Info.plist 一致；啟動只註冊一次。

## 儲存與復原

- [ ] 最愛地點、最愛路線、匯入 GPX 重開 App 都讀回；舊版 favorites.json／session.json 可原樣讀回。
- [ ] 刪除最愛路線或匯入路線後按復原：最近的刪除回來，重開 App 後復原入口消失。
- [ ] 手動移除某一筆 payload 檔後重開：該筆顯示不可用原因，選取停用，manifest 不被自動改寫。

## UI／字級／語言

- [ ] 底部三個等寬 tab（瞬移／路線／搖桿）在最大字級下每個至少 44×44，可點且不重疊。
- [ ] 小螢幕與最大字級：地圖面板不震盪、不遮住 Pin／Go。
- [ ] 三語切換、深色模式、VoiceOver 基本操作。

## 2026-10-20 UI 改版裝置驗收

步驟 1–8 已實作；本節全部仍待真機。離線建置、測試與選取的 3 個視覺樣本結果見 `work/gofly-ios/redesign/RESULT.md`，不以模擬器結果替代以下驗收。

- [ ] 冷啟動 Logo 深淺色一致，快檢查不閃進度，超過約 0.5 秒才顯示進度；已完成引導直接進地圖，真正等待 Mac／失敗狀態仍可辨識。
- [ ] 定位尚未設定可請求使用期間或略過；已允許顯示綠色與下一步、不重跳授權；已拒絕顯示 warning、前往設定及略過。使用期間不標 warning，沒有「永遠」升級。
- [ ] 引導及設定連線說明為同頁；開 LocalDevVPN 未安裝時改開 App Store，兩者均無法開啟才提示手動搜尋。實際 Wi‑Fi／VPN 狀態與下一步門檻一致。
- [ ] 搜尋全螢幕與鍵盤不遮輸入，標籤可找到最愛；最近搜尋最多 8 筆且不承諾重啟保存。點結果回地點 sheet，路線欄位點一次即回填，返回保留原值。
- [ ] 點圖候選 Pin 不自動置中，遮住時僅最小平移；Pin 與地點 sheet 的 Go 相同行為，位置待確認時皆停用。
- [ ] 路線／漫步執行或暫停時隱藏一般搜尋與 tabs，深色指示卡及底部控制可觸及；結束需確認。取消漫步保留最後模擬位置，設定 Stop／Restore 才清除。
- [ ] 一般與漫步搖桿均為 150 pt，拖曳、高亮、回彈與觸覺符合設定；隨機目的地次要按鈕不重啟任務。箭頭方向 #15 另記結果，不視為本輪已修復。
- [ ] 最愛星號 0.5 秒內再點可取消；逾時刪除及多選刪除均可復原，標籤與順序保留。底部搜尋僅查最愛，⋯ 開編輯 sheet。
- [ ] GPX 資料夾入口、匯入成功載入 snackbar、失敗 banner；點列動作選單可查看全部點位／分享／刪除復原，載入後不出現編輯控制。新匯入分享保留來源 bytes；舊版正規化來源不承諾還原 metadata。
- [ ] 標準與最大字級、深淺色及 VoiceOver 可操作搜尋、sheet、結束確認、狀態嚴重度及語言／外觀 Picker；底部動作與地圖控制不被 safe area 遮住。
- [ ] 設定 › 裝置與簽名仍可匯出診斷 JSONL；移動停止階段 B 依 `work/gofly-ios/debug-movement-stops/DEVICE-STEPS.md` 蒐證，未據推測修根因。

建置與離線證據（2026-10-20）：`check.sh` 196 tests、`check.sh --device` 建置、`GoFlyUITests` 12 tests
全過；代表性截圖 `work/gofly-ios/redesign/step-3/`～`step-8/`。執行模式（路線／漫步）與附近地點
清單尚未有模擬器截圖，列入待真機或後續補強。

## 驗收用 build

準備（實際產物已用 `ls` 確認）：

```bash
bash app/GoFly/scripts/check.sh --device
bash app/GoFlyMac/build-app.sh
ls -ld work/gofly-mac/GoFly.app \
  work/gofly-ios/iphoneos/Build/Products/Debug-iphoneos/GoFly.app
```

- Mac App：`work/gofly-mac/GoFly.app`。
- iOS：AI 實機測試改用 `bash scripts/install-ios-test.sh`（先 preflight，再於授權內 apply）；與 Mac GoFly 共用 producer，必須取得配對／支援及 App 精確回報。Mac GUI 從 `app/GoFly/GoFly.xcodeproj` 建置並簽署；**不要用 Xcode 直接安裝**，否則會繞過首次安裝與配對交接。
- `work/gofly-ios/iphoneos/.../GoFly.app` 只是 device build 驗證產物，不是安裝來源。

驗收順序：
1. 手機已有 main 版 GoFly：Mac 裝置頁選取手機，應自動觸發 renew。驗證完成、到期日、原本最愛／匯入路線／最愛路線／設定仍在，且能開到地圖。
2. 照上方勾選表驗收；冷啟動測法：路線執行中直接從 App 切換器滑掉 GoFly，再重開。VPN 已連上時應自動清除模擬位置；VPN 未連上時不彈錯誤、地圖有提示，按 Restore 可清除。
3. 選做：刪除手機上的 GoFly，從 Mac 重跑首次安裝（M1）。**這一步會清除 App 資料。**

## 2026-10-23 瞬移狀態 pill（真機待驗）

- [ ] 瞬移 ACK 成功後，地圖與設定 session pill 均顯示 Running／執行中；固定位置週期補送待 ACK 時不跳成 Limited。
- [ ] 無真實 GPS 但模擬定位正常時仍顯示 Running；實際斷線、服務錯誤、暫停與本次操作後位置未確認時，分別保留對應狀態。
- [ ] 瞬移後關閉並重開 App：本次尚未操作且沒有真正錯誤時，連線檢查前後地圖與設定 pill 均為 Standby；不因載入舊模擬座標變成 Limited，不自動恢復任務或將舊座標當成有效 ACK。

## 2026-10-22 瞬移假成功回歸（真機待重驗）

- 裝置日誌確認 build 20 在 session 建立失敗時仍 ACK，且配對資料夾為空；本輪修正錯誤傳遞，不宣告外部地圖已恢復。
- [ ] 無配對時按 Go：顯示配對修復指引、保留候選，不移動模擬箭頭、不顯示瞬移成功；Stop／恢復 GPS 也不能假成功。
- [ ] 由正式 Mac 交接恢復配對後，Wi-Fi／LocalDevVPN 就緒，選擇與原位置明顯不同的座標按 Go；Apple 地圖及 Google Maps 按目前位置後皆移至目標，記錄時間及診斷。
- [ ] 恢復 GPS 後確認外部地圖回到原定位；錯誤或未知回覆維持待確認，不盲目重送。
- [ ] 不刪除 App 或資料；透過正式 Mac 更新及配對流程操作。

- [ ] 更新／重新簽名後偏好、最愛與路線均保留；完整配對及支援回報通過。再執行一次相同腳本更新，核對已完成交接控制檔可安全封存，不碰使用者資料。
