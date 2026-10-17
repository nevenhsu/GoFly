# 票09：GPX完整資料與匯入清單（Advisor已核准）

08完整回歸期間預先設計；Advisor已最後讀回核准，無剩餘blocker。08實作／驗證／提交完成後才執行09，Executor之前先凍結共用GPXDocument／loaded snapshot／persistence receipt API。研究依09-gpx-research.md。手機全部延後，無Figma回寫。

## 資料及解析

正式GoFlyCore新增GPXDocument，其content為sum type：tracks([GPXTrack(segments:[[GeoCoordinate]])])／routes([GPXRoute(points:[GeoCoordinate])])／waypoints([GeoCoordinate])；kind與依序segments為衍生accessors，不以攤平模型丟失多track分組。所有座標經GeoCoordinate建構。保留原點序、所有重複點及segment邊界，保存／預覽／匯出不套手動節點過濾。多個同類track或route保留文件順序及segment，混合種類以明確unsupported錯誤拒絕，不能默取track忽略route或waypoint。root必須GPX標準namespace及version1.1，point必須合法parent；extensions外來namespace內容不收為GPX point，仍受完整資源上限。非法point整份失敗，不能跳過。lat/lon依GPX decimal詞法解析，拒絕NaN／Infinity／科學記號／尾隨字元；輸出用可回讀相同Double的非指數十進位字串，不以固定小數位靜默捨入。至少2個原始有效點才可匯入。多trk逐一保留track分組及各trkseg；每個rte是一個獨立segment且保留route順序；root wpt明確按文件順序作單一ordered segment，沿該點序直接走原軌跡（不MapKit）。空trk／空trkseg／空rte整份拒絕並明確報unsupported empty group，不悄悄忽略。單點非空segment可保存，整體是否可執行仍按連接及正距離規則。匯出roundtrip保留track分組／route分組／segment及點序；不宣稱保留未解析的任意GPX XML metadata。

讀檔在security-scope defer內，advisory size後以max+1 decisive boundedread，2MiB上限先於XML解析。解析另設10,000點總上限、depth64、100,000 elements；超限立即abort。採encoding-aware bounded DTD／ENTITY token拒絕＋禁止external resolution＋所有DTD/entity callbacks拒絕，不能只信副檔名或UTType。需明文安全支援UTF8/UTF16及必要BOM，未支援encoding拒絕而非降級繞掃描。輸出canonicalGPX1.1，escaping名稱／POSIX可roundtrip座標、保留type／segments／點序與精確Double值，不使用6位displayText；格式需不受使用者locale改變，大小也≤2MiB。若無法符合輸出上限，整份匯入／匯出失敗不截斷。附加XML時間／海拔不是prototype既有解析資料，本票保留完整座標軌跡與類型，不擴為通用XML編輯器。

segment gap不默默補直線或瞬移：合法GPX可匯入保存／預覽全部segments，若相鄰segment末首不精確相同或全路徑零長度，顯示明確不可執行原因、Load停用。相接時建立獨立derived PlannedRoute，只移除執行用相鄰重複點及共用界點，保存原文件不變。GPX執行直接用該完整軌跡、不MapKit replan、不套50m道路吸附。原始總點數限制先於執行正規化。多track/route採相同段連接規則，不憑座標近似跨gap。

## 路線來源與執行

RouteDraft變為單一來源sum type：RouteDraftSource.manual([RouteNode])／gpx(loaded immutable document+source display metadata)。既有draft.nodes對GPX為空且所有節點mutation拒絕，UI依source選清單或摘要，不構造假節點；speed仍屬草稿獨立設定。手動constructors與default current不變，GPX載入明確替換來源而不是隱藏另一份可誤啟動的節點草稿。RouteExecutionIntent照樣凍結完整draft／path／speed，roundtrip選項仍由08另管。

Imported list選卡片只選取，不改draft／任務／位置；按Load才將已再次驗證且可執行的完整GPX帶回初始路線模式，保留速度與來回選項，仍要Start。Load只允許controller.canEdit，不結束健康任務。Start的GPX分支先驗完整path及admission revision，直接交既有同owner preparation／第一精確起點ACK0／scheduler／Pause／Cancel／roundtrip；不經planner、不分拆成手動waypoints。失敗沒有native admission。

Root map canvas新增獨立segment預覽，逐段polyline不連gap；camera bounds可涵蓋全部點。已載入GPX初始面板只有「GPX路徑」檔名／點數摘要與完整地圖軌跡，不展開逐點inputs／drag／新增waypoint，不提供轉手動。操作入口可清除已載入GPX回到預設手動編輯（僅canEdit、需明確操作），不影響import清單原紀錄。

## 匯入持久化與檔案保護

新增ImportedRoutesStore，正式私有Application Support/ImportedRoutes與FavoritePlaces／配對分離。採versioned manifest＋UUID命名immutable canonical GPX payload；manifest只存驗過且UUID唯一的id／display filename／kind／pointCount／精確start-end座標／payload byteCount及SHA256，不用來源檔名構造路徑。每次成功匯入新UUID，允許同檔／同內容獨立紀錄。最多100筆，包含staging／final／undo與可識別孤兒的實際payload總量≤64MiB，manifest≤1MiB。來源檔只讀，永不修改／刪除。

沿正式FileFavoritePlacesPersistence的no-follow regularfile、0700/0600、iOS completeUntilFirstUserAuthentication、boundedread及fsync+同目錄rename pattern。payload先安全落地，再單次原子manifest commit；manifest成功才publish record／selection。payload成功但manifest失敗不發布、不動舊manifest，只留下可安全辨識孤兒。manifest損壞／未知schema封鎖mutation且不cleanup；healthy manifest才可清理不被manifest或undo引用的自有UUID payload，未知路徑保留。cleanup失敗不把已commit的transaction宣告失敗，且下次admission仍按實際總量上限，不無界堆孤兒。

啟動只讀bounded manifest與安全metadata／總量核對；選取／Load／Export前以boundedread重驗payload hash、GPX與manifest metadata一致，避免startup一次配置64MiB。耗時解析／編碼放非MainActor邊界；store對單筆import／selection validation用request revision，UI顯示檢查中，遲到結果不得覆蓋新選擇／刪除。所有payload O_EXCL落地、quota／目錄scan、manifest commit、delete／undo與orphan cleanup由同一persistence actor的序列transaction統一管理，transaction內檔案操作同步且不await；禁止cleanup從旁路或可重入窗口刪除in-flight UUID。耗時parse／encode在actor外準備immutable artifact，進commit時重新讀取／驗證目前manifest與實際quota，依最新archive套UUID mutation，不採舊proposal。MainActor store使用busy狀態限制同時mutation，selection validation可取消且以revision隔離，只有實際commit receipt才publish。

刪除先commitmanifest，成功才移除該UUID／清selection，保留payload及原index作單筆undo。undo以原UUID與原index（必要時clamp）第二次原子commit；commit失敗保留原undo token／payload供明確重試，不publish恢復。不恢復selection、不改draft／任務；其他同內容紀錄不受影響。新的成功刪除替換undo token，舊payload可cleanup；重開App不承諾恢復短暫undo。當前已載入GPX是獨立完整snapshot，刪除import紀錄不使draft失效。寫入失敗保留原bytes／observer／selection，損壞資料不默默換健康空清單。

## UI／分工／驗證

路線細項只新增「已匯入路線」入口；GPX匯入／匯出集中清單。無選取或仍檢查payload不可Load／Export；失敗可見具體原因、取消不新增。檔案Importer限GPX/XML選擇器，但內容仍完整驗證。Exporter只導出目前選取的完整資料，顯示原檔名／type／點數。清單刪除可undo，空狀態與每控制≥44、三語／dark／AX。當前schema新增須不讀prototype資料。

Executor A擁有Core GPX模型／codec／ImportedRoutesStore／File persistence與tests；Executor B擁有Core RouteDraftSource／PlannedRoute GPX initializer／Controller Load/Start及tests（介面先凍結，避免同檔）；Root擁有App file adapters／factory／map preview，UI Executor擁有RoutePanel／importlist與locales／UITests（可在A完成後再啟動以≤4slots）。所有人不得revert他人，無descendants。正式分工須Advisor核准後再交付，08未完成不執行。

必要TDD：XML合法parent／version／namespace／DTD/entities各encoding／depth/element/size/points exactboundary／invalidpoint整份失敗；三kind、多segment/gap/duplicates、localeindependent encode→decode資料相等及10k保留。檔案regular/symlink/oversize／schema／duplicateUUID／衍生filename／hash／metadata mismatch、precommitfail/in-flight orphan cleanup排除／actual quota含staging/final/undo/orphan／duplicate record／deleteundo isolation與undo fail token保留／restart以及遲到select/import不改新狀態。GPXLoad不admit、不改速度/roundtrip；Start不調MapKit、原精確path/ACKaxis、10k、不canonical改保存、Cancel/Stop/unknown沿既有契約。Simulator真實namespace文件清單／輸入檔fixture／load摘要與完整preview、cancel／export重匯、AX/dark/3語，不偽造native ACK/GPS。最終完整Swift/UI、unsignedbuild、native verifier、diffcheck與雙軸；手機全部集中最後驗收。


API凍結（08提交1e5835d後）：GPXDocument(content:)throwing validates完整tracks/routes/waypoints；ImportedRouteRecord含start/end座標與filename/kind/rawcount/bytes/hash，Snapshot(record:document:)throws交叉驗證、Snapshot(document:filename:id:)產生canonical有效metadata。Store async read/import/select/delete/undo/exportSelected共用單一persistence actor receipts（orderedrecords/canUndo）；error以GPX／imports localizationKey。PlannedRoute(imported:)為唯一executioneligibility來源，ImportedRouteExecutionFailure.disconnectedSegments／zeroDistance，Controller統一RouteExecutionFailure.imported，Load/Clear保留speed及roundtrip。詳情GPX清單可直接從manifest顯示真實原起終點，選取再verifyhash／payload；不必啟動時解碼所有文件。
