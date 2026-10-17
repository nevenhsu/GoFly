# 04: 準備重試、任務交接與位置待確認

**Status:** verification-pending

**Implementation:** complete

**Device verification:** deferred-by-user（全部實作完成後，由使用者統一用 iPhone 驗收）。

**Development policy:** 依序持續開發至全部實作完成；開發期間不要求使用者連接 iPhone、不等待 USB、不安裝或操作實機。先完成本票實作、建置、自動化／模擬器驗證及必要審查，再繼續下一票；所有實機項目交由使用者最後依[集中手機驗收清單](../DEVICE-ACCEPTANCE.md)測試。前置票實作完成即可解除開發依賴，deferred-by-user 不阻擋後續實作；實機未驗不標 done。

**Blocked by:** 03（實作／自動驗證完成，0379d10；手機驗收集中延後）。

**What to build:** 新操作可有界重試準備；結果不明時保留候選並安全修復，不讓新舊任務交錯送點。

**Design reference:** 08 O11／O12／O14／O16、09 H11。

**Acceptance criteria:**

- [x] 只有送點前準備可自動嘗試三次（首次＋兩次）；同時一筆新要求，取消／全失敗保留原來源、模式與資料。
- [x] 健康舊任務在新準備期間維持原狀；準備成功決定交接時先終止舊送點，再啟新任務。中斷舊任務不冒充健康，未知新結果不復活舊任務。
- [x] O16 返回地圖仍鎖原 Go，Pin 詳情仍可用；只有真實能力可確認結果，未確認不重送、不新增假查詢按鈕；停止後可明確建立新操作。
- [x] 票 05 已補 O16 模擬器整合複驗：明確 unconfirmed 注入後，返回地圖仍可開詳情／收藏，Go 保持鎖定；不當作真機效果證據。

**Verification:** 準備 1／2／3 次及全失敗測試；兩筆操作交接順序、取消／停止／遲到 ACK 故障注入。

## Implementation record

2026-10-17：前置 03 已完成實作、自動驗證與雙軸審查並提交 0379d10。Advisor 已核准準備重試、取消新要求與同步任務權限交接邊界（decisions/04-preparation.md），開始以公開 controller／gate／authority seam 先紅後綠實作。所有測試機與接收 App 驗收延後，不等待 USB。

最終來源驗證：Core 47 項／8 suites＋Transport 9 項／1 suite，共 56 項完整 Swift 通過；完整 simulator UI 11／11 通過，最後僅強化測試對按鈕完整 frame 的判斷，再補驗 AX 最大字級 1／1 通過，產品來源未再變更。build 6 未簽署 iPhoneOS build-for-testing 成功；三語 96 keys 一致／無重複、plist parser、完整 native verifier 與 git diff --check 通過。Standards／Spec 皆零剩餘 finding。

新 lease 在 ACK 前為 unknown；相同健康證據不改版本，避免健康舊任務 ACK 阻擋交接。送點前 watchdog 保留舊 ready／位置／authority，並等真正返回；異常未 claim 結果保守撤銷權限且關閉準備面板。上述重要分支均有實際 red→green 記錄；UI 實際失敗／取消／新 round 沿用原來源亦通過。舊任務權限的 public seam 供 06／11 正式排程接入，未製造假舊任務 UI。

本票實作完成可繼續下一票；真機／接收 App 效果仍如實待驗；05 收藏整合已以模擬器錯誤注入複驗。未連接、安裝或操作手機，沒有 native ACK 或 GPS 成功 fixture。
