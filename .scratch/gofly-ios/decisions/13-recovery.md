# 票13：連線修復、前景返回與冷啟動（Advisor核准v5）

2026-10-18。基準4a0d9b3；票12完整Swift302／UI39／39、unsigned build14與兩軸零finding後提交。票13build15依序開始，不操作手機／USB／簽署／安裝，實機集中最後驗收。Root撰寫方案，configuredAdvisor逐輪審查，無Planner；第5／5輪PLAN_APPROVED，P13-01至04均INCORPORATED，無剩餘finding。

## 核准行為與證據界線

- 連線失敗先同步關閉Service／MovementTaskAuthority的原子派送門檻，撤回所有available工作，再要求Controller暫停／退休；已claim仍只結算真實ACK或unknown。成功TCP只恢復連線准入，不改健康／lease或自動繼續。Stop／clear／reset始終可用。
- 同process健康已安裝route／roundtrip／auto保留同一intent、lease、ACK進度／方向／目標；手動held input不恢復。未安裝的準備退休，待明確新要求。前景即時檢查，最多一個probe，完成後fresh2s，不追補中斷時間。
- Native沒有任務身分／目前點查詢，冷啟動不重建健康owner或提供舊Resume。草稿／顯示快取／歷史ACK摘要都是data-only；箭頭等待50%，不能作有效origin。saved active／uncertainty或既有checkpoint無法讀取時，獨立cold hold禁止新移動，只有明確操作後的實際clear ACK解除；discard／TCP／reset／GPS不能解除。真的不存在檔案則正常fresh default。
- SessionRecoveryStore在Map建立前同步bounded讀回一次，只有一份App store與穩定route/js／Coordinator實例。獨立uncertainty涵蓋firstclaim-beforeACK、manual兩ACK間、Stop／Cancel pending清理；terminal active=nil，遲到ACK不可恢復舊任務。沒有held方向／手勢／native handle／credentials持久化。
- Store新版record4MiB；manual27、GPX與active path各10,000點、history100。GPX完整意指既有支援的kind／track及route群組／segments／原點序／精確座標與顯示檔名，不新增或宣稱保存高程、時間或XMLmetadata。共享來源僅可在同一record內去重，不截斷／道路重算。節點UUID保留但不是執行權限。
- Actor writer只有一筆inflight＋一筆最新pending；revision單調、terminal優先、舊結果不蓋最新durability。capture只代表接受，flush等待呼叫時revision或更新commit／failure，取消flush不假稱取消底層寫入。失敗保留舊檔；損壞／unsafe／未知schema禁止自動覆寫，不刪舊資料。只用私有no-follow FD／0600／0700／保護／fsync＋原子rename。
- Native exact24/sub0映射DeveloperModeRequired；24其他sub保留generic，20唯一not-mounted false，109timeout、103/5pairing。personalized-image實際branch也走central numeric helper，不留rawFFI文字；不加C/Rust API或捏造constructor timeout。
- 三語短原因／原模式waiting與paused UI；不改Uber風格、44pt、鍵盤／AX、無圓圈箭頭或路線編輯Pin回填無Go。無新Figma讀回／回寫宣稱。背景持續另依14／15，不以本票安全inactive暫停當背景支援。

## 累積審查處理

P13-01 Service原子authority派送門檻；P13-02實際DDI lookup numeric mapping；P13-03獨立uncertainty／coldhold；P13-04對齊既有GPX資料與10k active cap。Round1 revise、2approve、3approve、4revise、5approve；完整工作版本保留ignored research，這份ADR與下列精確API是正式實作來源。

## 凍結API／ownership／波次


## A owned models/store

- SessionMapMode: String, CaseIterable, Sendable {teleport,route,joystick}; App replacesprivateenum withtypealias/localizedextension, no .id rebuild.
- SessionDisplayPosition: immutable coordinate:GeoCoordinate,source:PositionSource; nofreshness/timeproof.
- SessionSavedTaskState: running/paused/uncertain (historicaldataonly).
- SessionRouteRecovery: immutable draft:RouteDraft,route:PlannedRoute,progress:RouteProgress,roundTripEnabled:Bool,usesPositionAxis:Bool,heading:RouteHeading,state:SessionSavedTaskState.
- SessionWanderRecovery: target:WanderTarget,speed:RouteSpeed,history:[GeoCoordinate],lastAcknowledgedCoordinate:GeoCoordinate,lastAcknowledgedBearingDegrees:Double?,state:SessionSavedTaskState.
- SessionActiveRecovery: .route(SessionRouteRecovery)/.wander(SessionWanderRecovery)/.manual(noinputpayload).
- SessionUncertaintySource: point/route/joystick/wander/gpsRecovery/unverifiedPreviousMovement.
- SessionMovementUncertainty: source:SessionUncertaintySource,requestedPlace:MapPlace? (requestedgoal notcurrentposition).
- SessionRecoverySnapshot: mode:SessionMapMode,draft:RouteDraft,roundTripEnabled:Bool,joystickSpeed:RouteSpeed,position:SessionDisplayPosition?,activeMovement:SessionActiveRecovery?,uncertainty:SessionMovementUncertainty?. All Equatable+Sendable immutablepubliclet, publicinitializers withnaturallysafe defaults. Headinglivesonlyinactivedescriptor (newStartkeepsforwardrule). BoundsvalidatedthroughStore/codec, invalidlatestcannotappearSaved. ExactDuration components/finitebounds validated, no walltimeadded.
- SessionRecoveryFailure: Error,String,Equatable,Sendable rawlocalizationkeys:unavailable/unsafeFile/writeFailed/corruptArchive/unsupportedSchema/limitExceeded/invalidSnapshot/revisionExhausted; UI3langs later.
- SessionRecoveryLoadState .ready/.blocked(SessionRecoveryFailure).
- SessionRecoveryPersistence Sendable read()throws->Data?;replaceAtomically(with:Data)throws.
- FileSessionRecoveryPersistence init(directory:URL,checkpoint: @Sendable(SessionRecoveryWriteCheckpoint)throws->Void = {_ in}), protocolread/replace; privatepathsession.json。checkpoint僅觀察staging secured／written／flushed／beforeCommit供公開檔案邊界故障注入，正式預設無動作，與既有私有archive adapter相同。
- @MainActor SessionRecoveryStore ObservableObject init(persistence: anySessionRecoveryPersistence); immutablepublicinitialSnapshot; privateSetpublished loadState,error,isSaving,hasUnsavedChanges. capture(_ snapshot)->Bool syncACCEPTANCE only; flush()async->Bool revisioncutline;retrySaving()->Bool;clearError() cosmeticnotunlock. Models/codec/store/fileadapter publictracers. No newmutabletaskproof.
- RouteDraft narrow publicinit?(nodes:[RouteNode],speed:RouteSpeed=.standard), preservesUUID/order andvalidates27/current≤1/uniqueIDs. OthermodelAPIs unchanged.

GPX persistence fidelity is the current supported domain representation only: kind, track/route grouping, segment boundaries, coordinate order, exact coordinates, and display filename. Existing GPXCodec stays unchanged; no elevation/time/XML-metadata preservation is claimed. GPX documents and active PlannedRoute each cap at10,000 points; inputGPX2MiB, complete checkpoint4MiB. Round-trip all supported content and filename without truncation.

## B owned Service/controllers/coordinator/native

- Service publicrestoreColdRecovery(position:SessionDisplayPosition?,requiresConfirmation:Bool)->Bool one-shotstopped/noactualproofguard, waitingcache+optionalhold; read-onlypubliccoldRecoveryHeld:Bool, movementConnectionAvailable:Bool; setMovementConnectionAvailable(_ available:Bool) coordinatoronlymeaning (trustedApp), noleasehealth/runstateupdates. AtomicAuthorityfencederivedbothreasons; package-onlyAuthoritysetter.
- Service publicrecoveryUncertainty:SessionMovementUncertainty? derivedactualgate/pending/unknown/clear, no nativequery/mutation, lateclaimcallbackdoesnothideactualgateproof. clearACKreleasescoldholdonly; safetycleanupalwaysallowed.
- Route APIs sceneDidBecomeActive()/releaseForInactiveScene()/connectionDidBecomeUnavailable()/connectionDidBecomeAvailable(); JS addsconnectionmethods, retainexistingSceneones; availabilitycomputedpublicseamsrespectServicefence too. AddRouteSuspensionReason.sceneInactive/connectionUnavailable (publishedoptional), WanderSuspensionReason.connectionUnavailable. Userpause vsinternalreasonsdistinct. NativefailurestringsnotrewrittenbyTCP.
- Runtime capture helpers canstaypackage-only: Coordinator knowsServiceauthority/currentController andbuildsAimmutablemodels. No serializedintent/lease/heldmanualinput. Newpublichelpers onlyifactuallyneededbyApp/testpublicflow; no speculativehook.
- @MainActor MovementRecoveryController ObservableObject init(service:ServiceController,route:RouteExecutionController,joystick:JoystickMovementController,probe:anyTunnelProbing,clock:anyRouteClock=ContinuousRouteClock(),retainedColdSnapshot:SessionRecoverySnapshot?=nil). privateSetpublished connectionState:VPNCheckState,isChecking:Bool,checkpointRevision:UInt64; computedrequiresColdConfirmation,unverifiedMovement:SessionActiveRecovery?,unverifiedUncertainty:SessionMovementUncertainty?,noticeKey:String?,canCheck:Bool. sceneDidBecomeActive()/releaseForInactiveScene();checkConnection() merges;discardUnverifiedMovement() forgetsummarybutholdremains;snapshot(mode:SessionMapMode)->SessionRecoverySnapshot. eligiblemonitoronlyactualpreparedservice/knownblocked, neverinitialfakepreflightNativefixture. CheckpointRevisioncoalescedaftercompletedMainActorstates; noautostart/coldResume.
- B NativeDeviceSession personalizedimage helper usesNativeErrorMappingnumericbranch(code/subcode beforefree),20false/24/0specific109timeout103/5pairing genericfallback;DeviceServiceFailure.developerModeRequired. Updateexistingnative-error-mappingofflineharness. NoC/Rust change/FFImessage retention.

## Frozen sequencing

12finalcommit gate first. A models+validatedRouteDraftctor publictracer→coherent types thenB Servicefence/runtime/helpers/evidence/native mapping publictracers whileAstore/filecodec. Avoidbreakingoldpublicprotocolexhaustiveswitch withoutsamewavecompat. Root coldAppcoordinator/API readback afterBcoherent; UIrecoveryviews/locales/tests later. NoA/Bcrossfileedits; noagentsdescendants/commit/phone. Rootfinalchecks/reviews/commit.

## 驗證與提交

沿既定public Core／Device-adapter及持久化seams，逐一RED→GREEN（缺API的RED單獨記錄）；先A模型及validated RouteDraft ctor，再B runtime／Service fence／evidence／coordinator同時A codec/store/fileadapter，Root App整合，UI在Core coherent後接recovery views／三語／UITests。彼此保留變更，不越ownership／不descendants／不自行commit。

追蹤檔案roundtrip／invalidschema／no-follow／atomicfault、coalescing／terminal／flushcutline／cancel／dirtyretry；firstclaimunknown／manualbetweenACK／terminalpending coldhold與實際clear；Service queue head／available claim／oldCAS fence競態、claimedtruth／Stop generation、samelease pause／noautoresume；DeveloperMode exact numeric branch。App不造GPS／ACK，正向命令由controlled-device public seam驗證。最終完整Swift／held fullUI一次、unsigned device／simulator build、三語parser／native verifier／diffcheck與Standards／Spec雙軸後commit main；全部手機與實際接收位置仍deferred-by-user。
