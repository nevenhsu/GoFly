# 票09窄研究（非正式執行核准）

08執行期間由Advisor讀現有prototype／正式持久化邊界，未開始09程式。待08完成提交後提出正式方案。

可移植prototype GPXCodec的2MiB前置、10,000點解析總數、invalid-coordinate整份失敗、DTD／entity雙層拒絕、external resolution關閉、escaping／POSIX數字與bounded output；LocalGoFeatureModel的security-scoped defer與read(max+1)可沿用。不可搬stopIfNeeded／匯入即改draft／FileDocument先完整read／寬泛data信任。

現有codec缺陷：多track/segment攤平且track>route>waypoint隱式優先；只驗root名稱未驗version1.1／namespace／合法parent；無depth/element count限制；DTD byte scan須encoding aware並配合所有entity/DTD callback拒絕。正式建議depth64與elements100,000，上限前abort。

待正式定案：GPXDocument(kind,segments,filename)保存全部原點／segment邊界；預覽／保存／匯出不去重，執行derived PlannedRoute直接採GPX且不MapKitreplan／不50m道路吸附。執行不能默默跨segment gap或選第一條；多track/route／混合type與exactnamespace規則須明文。可依資料完全相接才執行，gap保留原資料並有明確不可執行原因；是否允許import後只預覽待方案核准。

持久化沿正式FavoritePlaces nofollow／regularfile／bounded read／0700/0600／iOS protection／fsync+rename write-first-publish-after，來源檔永不修改。Advisor建議UUID immutable canonical GPX payload＋atomic versioned manifest，payload先落地、manifest成功才publish，失敗孤兒不得誤認成功；manifest損壞／未知schema封鎖不覆寫。delete先commitmanifest、保留payload單筆undo，原UUID/index復原但不改selection／draft；cleanup失敗不回報commit失敗。待正式定record100／aggregate64MiB上限及cleanup／undo生命週期。可討論單一bounded archive較小transaction面積與大檔成本，尚未選定。

這是研究紀錄，無新增App功能、手機／Figma證據，不能當09Advisor正式執行核准。
