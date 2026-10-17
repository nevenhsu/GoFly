# 票10：完整最愛路線（Advisor核准；09提交後才執行）

本票依03 R02/R03/R06、PRODUCT-SPEC「最愛路線」及10-ticket。09完整30UI回歸期間只做研究／方案；不得先改production。真機仍全部延後，無Figma回寫。09安全檔案契約不可削弱，手動Start仍拒絕無效Current。

Advisor已核准，無架構blocker；以下兩項API凍結條件已納入。

## 儲存／來源

新增獨立Application Support/FavoriteRoutes，versioned manifest＋UUID衍生immutable payload，與ImportedRoutes/FavoritePlaces完全分離。每次Save新UUID，允許同內容／標籤，不查重。FavoriteRouteRecord存id、可空label、sourceKind、count、精確start/end、bytes及SHA256，GPX另有bounded immutable displayFilename（manual為nil）；標籤只在manifest，改標籤不改payload/hash。manual payload為有界JSON v1，保存2…27個有序MapPlace的身分／名稱／地址／精確座標；GPX payload用plain canonical GPX（不另套JSON wrapper），保留完整GPXDocument種類／track／segment及點序，不縮成兩點。讀回／選取／Load重驗hash、metadata、每個MapPlace欄位／identity及全GPX，未知schema／損壞封鎖mutation保留原bytes。限制100筆、實際所有final／orphan／undo payload共64MiB、manifest1MiB，單payload2MiB；字串沿FavoritePlaces有界規則，label空白normalize為nil。最多一筆短暫delete undo，以原UUID／index恢復，失敗保留token可重試，不改草稿／其他duplicate。

抽取package-internal SecureArchiveDirectory，只分享pinned no-follow directory FD、regular boundedread、O_EXCL 0600 write／fsync／同目錄atomicreplace、安全stat/list/unlink及0700／iOS protection primitives；05與09 domain的schema、ownedname、quota、undo、cleanup／checkpoints保留原actor或原publicboundary。不得抽generic database。先用05／09既有fault/symlink/FIFO/commit測試characterize，抽取後完整重跑。FavoriteRoutes用09同樣write-first manifest publication、single actor同步不可重入transaction、actualquota及committedreceipt；parse/encode在非MainActor，storebusy／revision隔離selection與mutation，所有失敗不publish虛假成功。

RouteDraftSource.gpx改依賴storage-neutral GPXRouteSource(document,displayFilename)；不依賴ImportedRouteRecord，更不能為favorite偽造import record。ImportedRouteSnapshot提供source，保持loadImportedRoute public行為及既有09測試相容。FavoriteRouteSource.manual([MapPlace])／gpx(GPXRouteSource)。Controller新loadFavoriteRoute只在canEdit，保存speed／roundtrip，不nativeadmit；manual生成新draft RouteNodeID但保留MapPlace身分／全部metadata與順序，GPX直接驗PlannedRoute並保持完整map preview。來源替換清除舊plannedRoute與pickerrevision；進行／暫停不能載入。

## Save當下的有效節點

App在實際Save tap讀service.currentRouteOrigin值交Core純builder；只用此public有效來源，絕不positionMarker／lastdisplaycache。manual把可用Current解析成確切MapPlace；無法解析時只排除該節點、保留其他已確認有效place順序，在副本重新派角色；剩餘≥2才可存。不能修改live draft，也不改Start stricter Current規則。modal顯示Save eligibility／omittedUnavailableCurrent提示，Save當下重新計算：晚到有效GPS可納入，過期GPS不能使用。0／1有效節點維持modal／label並顯示具體原因，沒有diskcommit。GPX存原snapshot完整document，不需要GPS／planner。保存速度／來回不屬紀錄。成功才dismiss，取消／swipe dismiss不寫入、不改草稿或native。

## UI

初始路線star固定新增入口，開label modal，沒有實心狀態／mode tabs／查重。最愛路線導覽入口沿現有wireframe樣式，清單卡片標籤及起終點、右44pt獨立刪除。短按validate後立即載入正確snapshot並回初始路線，仍需Start；長按只編輯該ID標籤、Cancel不改、Save原ID更新不新增或改其他duplicate。mutation／validation中具體busy，blocked archive不能Save/Delete/Undo/Load。delete小型undo保持草稿與位置。三語／dark／AX，真實hitarea≥44pt、長清單與modal鍵盤可達，空清單有返回。UI不使用fake成功native／GPS。DEBUGsim只允許明確data-only valid draft與隔離store namespace，實際store／file path同正式來源。

## 分工與驗證

Advisor核准且09commit後，A先read-only凍結FavoriteRoute模型／artifact／receipt／store／builder API；B先讀共用source整合API，再各自TDD。A擁有FavoriteRoute/FavoriteRoutesStore/FileFavoriteRoutesPersistence與新tests、SecureArchiveDirectory及05/09 file primitive抽取與對應既有測試；B擁有RouteDraft／GPXRouteSource／ImportedRouteSnapshot source adapter／PlannedRoute／RouteExecutionController及execution tests。A不改ImportedRoute.swift（除非與B先協調），B不改A檔案。Root擁有Appfactory／currentGPS valueclosure與source summary適配，UI Executor待API凍結後擁有RoutePanel／FavoriteRoutesView／modal／locales／UITests；不超4slots，皆不得revert其他人、不得spawn descendants。

必要public TDD：Current有／無／late／expired，0/1/2+explicit節點與不改draft、不用displaycache；manual27／GPX10k完整relaunch；duplicate UUID隔離；label僅manifest且bytes/hash不變；delete／undo原ID順序及失敗token；stale select／load、busy/cancel／commitreceipt；unknownschema／corrupt/hash/metadata／symlink/FIFO／size/quota邊界／所有write checkpoints與cleanup不能刪inflight。Load保留settings、不admit／GPX不planner、running拒絕／manual恢復全metadata。UI實際Cancel不存、重複新增、短按load、長按label、刪除undo、重開讀回及AX三語；完整Swift/UI、unsignedbuild、localeparser/nativeverifier/diffcheck、Standards及Spec雙軸後提交。實機項目集中最後，不假稱已驗。

## Advisor核准時必要API條件

1. Controller公開favoriteLoadAdmissionRevision與明確invalidating request邊界，短按開始驗證前取得新token，loadFavoriteRoute(snapshot, expectedAdmissionRevision:)同步檢查token／canEdit／沒有active picker。新favorite選取、dismiss／離開清單、accepted source/node edits、picker open/confirm/clear/cancel、explicit Start／Load／Clear作廢token。速度／來回不作廢，Load保留最新設定。必測dismiss後edit／picker replacement／Start→finish後舊結果與新選取先完成；不能只靠store selectionrevision。
2. 純builder回FavoriteRouteSaveCandidate(source, omittedUnavailableCurrent)，只捕捉實際Save tap當下單一currentRouteOrigin及draft值。Persistence只收candidate。成功而omitted=true時明確呈現「已儲存，未包含尚無有效位置的目前位置」結果，再由Done回原畫面，不能靜默dismiss／不能讓第二次Save重複commit。少於2仍保留modal／label顯示error、沒有commit。modal平常eligibility提示不取代Save當下authoritative結果。
3. Securehelper atomicreplace在authoritative rename後不得throw；05/09所有原checkpoint順序／故障意義不得改，既有file suites是抽取必要gate。

## 公開API凍結（read-only提案核可；09提交後才實作）

B：GPXRouteSource(document:displayFilename:)throws，只驗已valid document＋bounded filename，初始化不在MainActor做完整encode/hash；ImportedRouteSnapshot.source提供中立來源。RouteDraft.source.gpx用它，保留既有import convenience並適配App summary，不能造fake importrecord。Controller.beginFavoriteLoad()->UInt64?（canEdit且picker=nil，產生新token）、invalidateFavoriteLoadAdmission()（dismiss/newrequest）及loadFavoriteRoute(_:expectedAdmissionRevision:)->Bool；其餘edit／picker／Start失效依上述條件。成功Load後token消耗，不能同token再載入。

A：FavoriteRouteSource.manual([MapPlace])/.gpx(GPXRouteSource)；FavoriteRouteSaveBuilder.build(draft:currentRouteOrigin:)throws->FavoriteRouteSaveCandidate(source,omittedUnavailableCurrent)，candidate公開只讀且constructor internal。FavoriteRouteArtifact(candidate:)throws offMainActor產payload，record(id:label:)throws。FavoriteRouteRecord(id,label,sourceKind,count,start,end,displayFilename?,byteCount,sha256) checked；Snapshot(record:source:)throws完整metadata/hash驗證、fixture convenience(source:label:id:)throws。

Persistence async read()->FavoriteRoutesReceipt(records,canUndo)、save(candidate,label)->FavoriteRouteSaveReceipt(archive,result)、validate(id)->Snapshot、updateLabel(id,label)->Receipt、delete(id)->Receipt、undoDelete()->Receipt。SaveResult(record,omittedUnavailableCurrent)只來自實際commit。Store published records/selectedID/selectedSnapshot/isBusy/isValidatingSelection/loadState/error/canUndo、canMutate、load/select/updateLabel/delete/undoDelete/clearError與save(candidate,label)->SaveResult?。sameID select重驗、select(nil)失效；UI另用Controller token防遲到Load。save不改選取或live draft，receipt發布須保留較新選取語意。

FavoriteRoutesLimits：100records、64MiB總payload、1MiB manifest、2MiB單payload、manual27；label120/title512/address2048characters、identity2048UTF8。Failure localizationKey favoriteRoutes.error.<case>：corruptArchive/unsupportedSchema/unsafeFile/unavailable/writeFailed/limitExceeded/invalidLabel/invalidPlace/tooFewValidPlaces/notFound/metadataMismatch/hashMismatch/noSelection/busy/nothingToUndo，gpx(GPXFailure)forward既有key。LoadState loading/ready/blocked(reason)，Unavailable fallback；checkpoints對齊09 payloadSecured/Written/Flushed、manifestSecured/Written/Flushed、beforeManifestCommit/cleanup（05原既有名稱意義保留）。

B整合補充已凍結：GPXRouteSourceFailure.invalidFilename屬中立domain，A在archive boundary轉FavoriteRoutesFailure，不外溢ImportedRoutesFailure。RouteDraft公開gpxSource取代誤導的import-record getter；保留init(imported:)／loadImportedRoute／clearImportedRoute既有行為，UI摘要改source displayFilename/document。canEdit後明確Start／ImportLoad即使validation失敗亦作廢舊favorite token；過期picker ID不影響新token。issued token初值nil，不可用revision0自行授權，成功Load消耗。B負責09Core tests source適配；App summary交UI，不與Root/File worker交叉改檔。

Card metadata補足：Record加immutable startTitle/endTitle:String?，manual必須非空／≤512且由first/last MapPlace.title衍生，Snapshot與payload exactcrossvalidate；GPX必須nil並用座標備援。MapPlace既有constructor已將空title依address／coords備援，不另加mutable顯示metadata，也不eager讀所有payload。此為保存現有名稱及lazy列表的必要補足，標籤仍唯一可修改欄位。

UI eligibility使用Root傳入的currentLocationAvailable Bool，只計可用Current及explicit有效places；實際origin closure只在Save tap讀一次。已知<2顯示具體原因並停用Save；若tap前剛過期，authoritative builder仍拒絕、保留modal/label/error，不因舊eligibilitycommit。≥2explicit而Currentnil則允許存，實際receipt明示omission後Done。


## 最終交付紀錄

2026-10-18：完整Swift231、完整simulator UI35／35（1537.711s）、未簽署iPhoneOS build12、285key三語parser／native verifier／diffcheck及Standards／Spec零finding。原生鍵盤測試先確認整欄清空再精確比對，無diagnostic／forcedDone／fake ACK/GPS；footer完整文字與native44pt已實測。Core含05／09共用file primitives回歸與O_EXCL staging ownership紅綠證據，兩軸無剩餘finding。Implementation complete；手機deferred-by-user，不以離線結果外推實機。
