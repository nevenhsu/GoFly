# 16: 語言、外觀及裝置資訊設定

**Status:** ready-for-agent

**Blocked by:** 01。

**What to build:** 在設定即時切換語言／明暗外觀並保存，查看實際權限、裝置資訊與操作說明。

**Design reference:** 07 C01／C03–C07、Q01／H06、偏好設定參考框。

**Acceptance criteria:**

- [ ] 語言 system／en／zh-Hant／zh-Hans、外觀 system／light／dark，預設跟隨系統；原生單選立即套用／保存／關閉，取消不改，重開保留。
- [ ] 英文 fallback；使用者標籤、地點及檔名不翻譯。全 App 與地圖套用同一外觀，Uber 風格維持可讀對比；變更不重啟服務／任務、不重送。
- [ ] 外部設定返回讀實際權限／背景狀態；裝置資訊及簽名日期未知如實顯示，C06 常駐 Mac 更新簽名說明，操作說明區分手動與漫步。

**Verification:** 偏好保存／取消／系統變更測試；當前已交付畫面三語、深色與 VoiceOver 驗收。
