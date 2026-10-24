# 01 · 對齊 E 區靜態線框與狀態語意

**Status:** implemented; static-design-verified

**Blocked by:** None.

**Scope:** 核對 04 · iOS Redesign 的 E1/E1.a/E2/E2.a/E3/E4/E5 淺深色渲染；修正錯誤角色、E4「確認」雙入口與候選 Pin，核實 E5 深淺結構；同步 iOS 與 Figma 對照規格及驗收。只做必要靜態 wireframe，不新增 prototype wiring 或狀態排列組合。

**Acceptance:** 淺深色畫面結構、控件、展開/收合行為一致，差異只在主題 tokens；E1 保留搜尋、tabs、150 pt 搖桿、速度 pill、自動漫步按鈕；E2 保留完整搖桿和停止/更換地點；E2.a 為收合；E3 背景反映來源實際狀態；E4 Pin 與卡片 CTA 都是純文字確認且共用重規劃語意；E5 使用恢復列與 tabs。渲染需讀回並檢視。

**Evidence / changes:** Figma Desktop Bridge 讀取 E 區 14 張渲染與圖層。E1.a 淺深色重畫為搜尋列＋地圖＋收合搖桿列＋tabs；E3 Light/Dark 狀態標籤改為「啟動」；E4 Light/Dark 卡片 CTA 改成純文字「確認」並移除播放 icon；刪除孤立 CandidatePin。修後 E1.a、E3、E4 淺深色截圖均讀回且可視結構一致。同步更新 `docs/IOS-UI-DESIGN.md`、`docs/FIGMA-UI-RECONCILIATION.md` 與正式方案票單狀態。`git diff --check` 通過；正式 Core、native boundary 及 iOS Simulator build 由票 02 的整體檢查通過。

**Not verified:** App 行為、Simulator、裝置及動態字級/觸控驗收。
