# 16: 語言、外觀及裝置資訊設定

**Status:** verification-pending

**Implementation:** complete

**Blocked by:** 01。

**What to build:** 在設定即時切換語言／明暗外觀並保存，查看實際權限、裝置資訊與操作說明。

**Design reference:** 07 C01／C03–C07、Q01／H06、偏好設定參考框。

**Acceptance criteria:**

- [ ] 語言 system／en／zh-Hant／zh-Hans、外觀 system／light／dark，預設跟隨系統；原生單選立即套用／保存／關閉，取消不改，重開保留。
- [ ] 英文 fallback；使用者標籤、地點及檔名不翻譯。全 App 與地圖套用同一外觀，Uber 風格維持可讀對比；變更不重啟服務／任務、不重送。
- [ ] 外部設定返回讀實際權限／背景狀態；裝置資訊及簽名日期未知如實顯示，C06 常駐 Mac 更新簽名說明，操作說明區分手動與漫步。

**Verification:** 偏好保存／取消／系統變更測試；當前已交付畫面三語、深色與 VoiceOver 驗收。

**Implementation record（實作／離線驗證完成）：** 基準 c606081／build18；[核准 v2](../decisions/16-settings.md) 經 Advisor 第2輪核准，P16-01 同步重置訊號已納入。先執行公開邊界與真實 UI 的行為 RED，再實作；手機驗收仍依使用者安排留最後。

**Software verification:** 完整Swift406（Core397／46 suites＋Transport9）、雙SDK27.1未簽署build18、414key三語／格式／實際bundle、native verifier與最後Standards／Spec零finding通過。實際UI已覆蓋原生選項／取消／fallback／重開保存、兩種OS外觀、相同地圖實體／鏡頭、六頁三語最大字級、標籤與目前路線草稿保留、實際缺少LocalDevVPN的開啟失敗；focused結果與先前失敗分開保留。完整60個不同UI案例已成功覆蓋：初次24通過／1測試快照競態失敗／1取消；修正throwing單一快照helper後單項1通過，其餘35／35通過，零skip／runtime warning。原run未改稱全通過，無重疊／遺漏的案例集合及來源51b8fb8／binary雜湊已由Root讀回。修正後測試以獨立封存產品來源＋唯一helper差異執行，M1未編譯來源不混入本票證據。所有實機條件仍未驗。
