# 集中手機驗收清單
全部項目待手機驗收；開發期間不接手機、不安裝。逐項勾選並記錄 build。
## 安裝與首次流程
- [ ] Mac App 建置並開啟 Setup 頁；首次安裝（install）完成，iPhone 顯示歡迎頁與 loading。
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

- [ ] mode 切換按鈕（瞬移／路線／搖桿）在最大字級下每個至少 44×44，可點且不重疊。
- [ ] 小螢幕與最大字級：地圖面板不震盪、不遮住 Pin／Go。
- [ ] 三語切換、深色模式、VoiceOver 基本操作。

## 驗收用 build

準備（實際產物已用 `ls` 確認）：

```bash
bash app/GoFly/scripts/check.sh --device
bash app/GoFlyMac/build-app.sh
ls -ld work/gofly-mac/GoFly.app \
  work/gofly-ios/iphoneos/Build/Products/Debug-iphoneos/GoFly.app
```

- Mac App：`work/gofly-mac/GoFly.app`。
- iOS：一律由 Mac GoFly 從 `app/GoFly/GoFly.xcodeproj` 建置並簽署；**不要用 Xcode 直接安裝**，否則會繞過首次安裝與配對交接。
- `work/gofly-ios/iphoneos/.../GoFly.app` 只是 device build 驗證產物，不是安裝來源。

驗收順序：
1. 手機已有 main 版 GoFly：Mac 裝置頁選取手機，應自動觸發 renew。驗證完成、到期日、原本最愛／匯入路線／最愛路線／設定仍在，且能開到地圖。
2. 照上方勾選表驗收；冷啟動測法：路線執行中直接從 App 切換器滑掉 GoFly，再重開。VPN 已連上時應自動清除模擬位置；VPN 未連上時不彈錯誤、地圖有提示，按 Restore 可清除。
3. 選做：刪除手機上的 GoFly，從 Mac 重跑首次安裝（M1）。**這一步會清除 App 資料。**
