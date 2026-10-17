# 票14：背景持續工作的候選與離線生命週期（Advisor核准v5）

## Scope and execution gate

2026-10-18。基準1b6dcd6ddd40d55cc83c81c2134fabc7a753ac0d；票13實作／離線驗證及雙軸審查完成後依序開始build16。Root v5經configuredAdvisor第5／5輪PLAN_APPROVED；P14-01有效sealed finish outcome、P14-02自足版本／輪次、P14-03 terminal winner後expiry不得另送loss均INCORPORATED，無剩餘finding；不再開14架構審查。

14交付可重用Core生命週期、實際iOS候選adapter、離線驗證與集中實機腳本。App不建立／register／submit這個adapter、不改plist、不啟用背景移動；既有Service／Authority／Route／Joystick／Recovery不變。15另核准native claim admission與正式App接線。所有iPhone／USB／簽署／安裝及實際scheduler／receiver驗證deferred-by-user，不能由編譯或controlled driver外推實機可行。

## Evidence and product semantics

Read14-background-research.md,14-indeterminate-progress-addendum.md and14-root-option-notes.md. Actual Xcode27.1 iPhoneOS/Simulator27.1 SDK headers are available with DEVELOPER_DIR; no26 SDK is installed. BGContinuedProcessingTask is an iOS26+ foreground-human-started CPU/network candidate, requires progress, may expire/cancel, and presents system UI. SDK27 introduces async submitTaskRequest to capture all error conditions; keep an availability branch for legacy throwing26 submission. Registration, wildcard permitted IDs, real runtime duration and receiver position on26/27 remain unknown until the final experiment. API/source/controlled tests cannot prove them.

Finite one-way route uses actual acknowledged-distance goal and actual finite-arrival event. Unlimited roundtrip/wander keep their product semantics: one experimental indeterminate system task, totalUnitCount=-1, actual ACK count and cumulative ACK distance, no invented percentage, completion, finite-journey replacement, per-leg reset or automatic renewal. Foundation indeterminate semantics do not prove BGC will accept/retain useful runtime for it. User Pause/Stop, expiry or cancellation ends unlimited framework work unsuccessfully. No GPS/Always/audio/timer keepalive, catchup, refresh-as-runtime, GPU resource or queued strategy.

## Public Core models and grant

Use a narrow immutable request with ephemeral requestID UUID, movementID UUID, existing MovementTaskLease, kind finiteRoute/roundTrip/wander, goal finiteDistance or experimentalIndeterminate, caller-localized bounded title/subtitle. A public failable initializer enforces positive finite distance for finiteRoute only, indeterminate for unlimited kinds only, trimmed nonempty/noNUL title<=128UTF8bytes/subtitle<=512. No Codable, native handles, credentials or cold execution restoration.

Progress is public immutable validated actual acknowledgedWrites Int64>=0 and cumulativeAcknowledgedDistanceMeters Double finite>=0. The producer15 must consume actual same-owner ACK receipts once per sequence. Rendering, GPS, requested coordinates, walltime and replay cannot produce it. Controller checks current requestID, nondecreasing count/distance, finite distance<=immutable goal and nonterminal state. Zero-distance ACK increments count only. Before launch, retain only the newest legitimate progress; forward to the real system task only after matching launch.

Finite presentation has fixed1,000,000 units and floor(distance/total*1,000,000), capped999,999 below actual goal. Avoid distance-to-Int64 multiplication and add no route-length product cap. Indeterminate completed units are actual ACK count and total remains-1. Progress reaching total does not itself finish a task; a matching explicit actual-arrival event is mandatory.

ContinuedProcessingGrant is final Sendable through a narrow NSLock close-only implementation. Public identity initializer serves the real App adapter and controlled-driver tests; immutable requestID/movementID/lease, read-only isValid and idempotent revoke, no callback underlock. Only the real adapter's matching actual BGContinuedProcessingTask launch may mint a production grant. UI/fixtures never construct one. Submission acceptance never grants runtime, native health or authority.15 must separately read matching valid grant at inactive authority install/native dispatch;14 does not implement that fence.

## Atomic completion and effective finish result

Public ContinuedProcessingCompletionOutcome is success/expired/cancelled/invalidated/failed. Public ContinuedProcessingTaskCompletion.init(grant:ContinuedProcessingGrant?) and claim(_ proposed:Outcome)->ContinuedProcessingCompletionClaim are used by every actual App taskbox. Claim returns public immutable outcome and isFirst fields; callers need no internal constructor. One lock guards an optional sealed outcome. First claim selects proposed success only if grant is nonnil and valid, otherwise invalidated; unsuccessful proposals keep their reason. It synchronously revokes the optional grant, seals the result, and returns isFirst=true. Later claims return the identical sealed outcome/isFirst=false. Nil grant supports actual unknown-task disposal without synthetic movement identity.

Expiry proposes expired on its callback queue before queueing MainActor work. Fixed order completion-lock→grant-lock; grant never calls completion, authority or arbitrary callbacks.15's future authority→grant read has no reverse-lock path. Framework methods/callbacks run outside all locks. A sealed outcome describes ownership and the effective argument of a framework completion request; it is not an OS completion ACK or native movement proof.

The actual taskbox expiry handler queues expired(requestID), framework-delivery work and runtime-loss notification ONLY if claim.isFirst AND claim.outcome==.expired. If success, cancelled, invalidated or failed was already sealed, late expiry emits no event/loss and performs no second framework completion. A repeat expiry observing an already-expired seal also emits nothing. If expiry won first, its one queued event may run after normal finish has synchronously consumed/delivered that expired result; controller generation/identity makes that notification idempotent. Normal finish must never emit an expiry event merely because it observes an old outcome; it returns the sealed outcome to its caller. Every taskbox terminal path uses this same first-claim ownership rule.

Updates also require the current matching unsealed/valid grant at the actual box. Its validity read is an admission boundary: an update admitted before revocation may finish outside locks; no new update may be admitted after synchronous expiry closes it, even while the MainActor notification is delayed. Controller rejects updates when its matching grant is closed. Late actual native ACK truth belongs to Service/15 receipts and does not reopen the candidate. This adds no timer-generated progress.


Driver.finish(requestID:success:) synchronously returns ContinuedProcessingCompletionOutcome? from the owned actual sealed box; nil means no matching actual task. Real and controlled drivers obey this contract. Controller.finishFiniteArrival can return/publish success only for .success. If expiry already sealed .expired before its MainActor event, arrival instead enters expired and emits runtime loss once; the queued expiry event is idempotent. Other unsuccessful outcomes take unsuccessful terminal paths. Nil cancels pending work without inventing system expiry/completion. Actual native route arrival is independent truth in15.

For valid finite finish, privately invalidate controller callback generation first, invoke synchronous driver.finish before controller's final idempotent grant.revoke, then publish its returned terminal outcome. Revoking first would force all successes false. Expiry/cancel/rejection close permission before published terminal state. If arrival precedes any actual launch, cancel pending work and never report framework success. Unlimited modes never request success.

## Driver and actual framework taskbox

MainActor ContinuedProcessingDriving supports explicit register()->Bool, async submit(request,onEvent), update owned request progress/title/subtitle, synchronous finish returning sealed outcome, and cancel owned request. Events are launched(grant), expired(requestID), invalidated(requestID). Register exactly once per adapter instance; no cancelAll or automatic submissions. Controller registration is explicit/idempotent and begin requires registration plus explicit foreground input. The real adapter is compiled but unused14;15 separately approves singleton/configuration and actual per-request registration wiring plus plist; continued tasks have no ordinary launch-time registration deadline.

Real request identifier com.neven.gofly.movement.<UUID>; v5 selected literal wildcard registration com.neven.gofly.movement.* as an unverified experiment, separate from the permitted wildcard plist form. Later official-source readback shows dynamic suffixes belong in both registration and submission; literal wildcard handler dispatch is not established and must be corrected under15 before App activation. Explicit .fail strategy and default CPU/network resources. Use async submitTaskRequest on27+, legacy throwing overload on26. Do not silently report success on simulator/unavailable platform. Typed errors are small (unsupportedSystem,registrationFailed,notForeground,submissionRejected,cancelled,invalidProgress), no raw NSError description/userInfo or credentials.

Handle launch before submit return, reject after launch, expiry before event delivery, cancellation/supersession while submit is suspended, wrong IDs/type, old/duplicate callbacks and old submission completion. Only one current request. An incoming actual object is matched before grant creation. Unknown/retired/wrong-task-type objects get nil-grant false-completion boxes. A second actual object with the same identifier is disposed false without replacing the current task. A duplicate callback for the same actual object reuses its box and never fails the valid current object or emits a new grant.

Use a MainActor weak-key actual-object→box registry. Box holds actual BGTask strongly only until its sealed completion is delivered once on MainActor; then clear that reference. The weak key remains usable for duplicate callbacks while system/caller still holds the object, without a strong retired-task array or unsafe pointer reuse. Expiry seals/closes synchronously, then queues delivery; normal MainActor finish may deliver the previously sealed expired result but cannot change it. Box delivery/framework setTaskCompleted happen outside locks once. No unbounded per-progress Tasks; only owned submission/event delivery work.

## Controller ordering and receipts

Controller states idle/submitting/accepted/running/rejected/expired/finished distinguish accepted submission from matching valid runtime. It owns one private generation/current request and exposes actual grant/progress/terminal outcome. Launch must match requestID/movementID/lease and be valid. A same current grant duplicate is ignored; a different extra grant is revoked without replacing current runtime. Already-closed launch cannot enter running. A late submit success only changes submitting→accepted, never overwrites running or terminal state. A rejected-after-launch result revokes grant and owned driver work. Superseding/cancelling closes the old grant and cancels only its request; late old callbacks cannot pause/newly grant the current job.

Runtime-loss callback to15 is identity conditional and once per generation. It runs on MainActor after immediate grant closure. A completion outcome expired supplies the same notification even if the original event is delayed. Native work is never called by14. No auto renew/retry or cold runtime restoration.

Diagnostic receipts are bounded256 oldest-first, in-memory only: candidate API version, requestID/kind, boundary timestamps, actual ACK count/distance and events. Narrow date-provider(default Date) is diagnostics only. Name completionRequestedOutcome accurately; no OS completion receipt exists here. No coordinates, UDID, pairing, rawFFI, credentials or durable export14.15 may plan a separately reviewed protected bounded export if required.

## Tests, ownership and final evidence

After13 commit, current approval and exactAPI freeze, configured Executor A owns new Core lifecycle models/controller/completion and public tests. A second bounded Executor may own only the new real App driver after the Core API is coherent; Root owns formal ADR/issue/research-summary/device experiment, integration, final checks/review/commit. No descendants/commit/phone by children, no cross-file ownership or changes to existing movement writers14.

Use public Core/framework-adapter seams, one behavioral tracer at a time; missing API/compile/environment RED is separate. Cover accepted!=launched, launch-before-return, rejection-after-launch, close-before-delayedMainActor expiry, concurrent once-only completion, expiry-sealed-before-finite-arrival (false/expired/loss once, later event idempotent), valid finite winner followed by late expiry (no expired event/loss; framework completion true once), cancellation/invalidated/failed seals followed by late expiry (no false expiry or second completion), duplicate expiry (one event), no progress forwarding after close before delayed event, pending arrival without grant, invalid/closed/wrong/duplicate grants, stale/superseded generations, monotonic/invalid/stale progress, no indeterminate success or renewal. Tests use controlled driver, never actual App-native success fixtures.

Public completion helper tests prove portable synchronization; SDK/source checks inspect actual registry/box/resource/availability wiring. Do not claim they execute real system callbacks. Compile actual iOS adapter for simulator/device unsigned, focused tests then full Swift once held, appropriate native verifier/locales/diffcheck, Standards/Spec review then main commit.14 experiment completion never equals hardware-supported background movement.15 must separately approve authority-side grant checks and real App integration.

Final26/27 manual matrix records actual registration/grant vs native attempted/ACK cadence vs two receiving apps independently: foreground Start, background/lock, BGRefresh on/off/restricted, finite arrival, multi-leg RT and auto-next wander on same request, slow/no progress/expiry/LiveActivity cancel, VPN loss/recovery, manual override, Stop/clear, foreground return and kill/cold hold. Receipts are14/15 separate runs, never inherited prototype proof. Unlimited feasibility may remain not-proven/unsupported-under-tested-conditions; finite evidence cannot be generalized. No device action now.


## 精確公開API與執行ownership

## Core public value types

- ContinuedProcessingKind: String,CaseIterable,Equatable,Sendable {finiteRoute,roundTrip,wander}.
- ContinuedProcessingGoal: Equatable,Sendable {.finiteDistance(meters:Double),.experimentalIndeterminate}.
- ContinuedProcessingRequest: immutable Equatable,Sendable public lets requestID:UUID,movementID:UUID,lease:MovementTaskLease,kind,goal,title:String,subtitle:String. Public init?(requestID:UUID=UUID(),movementID:UUID,lease:MovementTaskLease,kind:Kind,goal:Goal,title:String,subtitle:String). Validate kind/goal and bounded trimmednonempty/noNUL title128/subtitle512UTF8bytes; finitepositiveDouble only, no arbitrary distance cap.
- ContinuedProcessingProgress: immutable Equatable,Sendable public lets acknowledgedWrites:Int64,cumulativeAcknowledgedDistanceMeters:Double; public init? with those labels, >=0/finite. Public static zero. Equal updates can be accepted without forwarding another system update or receipt; neither field may regress.
- ContinuedProcessingFailure: Error,Equatable,Sendable cases unsupportedSystem,registrationFailed,notForeground,submissionRejected,cancelled,invalidProgress. No raw NSError/userInfo/message.
- ContinuedProcessingState: Equatable,Sendable {idle,submitting,accepted,running,rejected,expired,finished}. Error and sealed completion outcome are separate published data; accepted/running are distinct.
- ContinuedProcessingRuntimeLoss: Equatable,Sendable {expired,invalidated,submissionRejected,cancelled,superseded}.
- ContinuedProcessingEvent: Sendable {.launched(ContinuedProcessingGrant),.expired(requestID:UUID),.invalidated(requestID:UUID)}. Tests compare matching identities, not arbitrary string descriptions.

## Grant and once-only completion

- ContinuedProcessingGrant final @uncheckedSendable justified by one NSLock, immutable public requestID/movementID/lease; public init(requestID:UUID,movementID:UUID,lease:MovementTaskLease), read-only isValid:Bool, revoke()->Void. Close-only/no callbacks; actual App constructs only in matching real framework launch, never UI/fixtures/submission return.
- ContinuedProcessingCompletionOutcome: String,Equatable,Sendable {success,expired,cancelled,invalidated,failed}. success means effective success argument owned for the actual framework completion request, never OS ACK/native truth.
- ContinuedProcessingCompletionClaim: Equatable,Sendable immutable public outcome:Outcome,isFirst:Bool. Constructed by the completion object; no public initializer solely for tests.
- ContinuedProcessingTaskCompletion final @uncheckedSendable with one lock, public init(grant:Grant?), claim(_ proposed:Outcome)->Claim. First proposal success requires nonnil valid grant, else invalidated. Other first proposals retain their reason. Revoke optional grant and seal inside the lock. Later calls return same outcome/isFirst=false. Fixed completion→grant lock order; no callbacks/framework calls under locks.
- Actual expiry queues expired/delivery/loss only for isFirst && outcome==expired. All late/duplicate expiry after any seal is silent. If expiry wins first and normal finish delivers the pending false before its queued event, event remains once and controller loss is idempotent. Nil-grant boxes dispose unknown actual tasks once without minting synthetic grant/lease.

## Public MainActor driver

ContinuedProcessingDriving: AnyObject, global MainActor isolation:

- register()->Bool explicit/idempotent.
- submit(_ request:Request,onEvent:@escaping @MainActor @Sendable(Event)->Void) async throws.
- update(requestID:UUID,progress:Progress,title:String,subtitle:String)->Void.
- finish(requestID:UUID,success:Bool)->Outcome? synchronous sealed actual owned-box result; nil=no matching actual task. It must deliver any alreadysealed pending outcome once, not convert an expiry loser into success.
- cancel(requestID:UUID)->Void ownedrequestonly, no cancelAll.

Real and controlled drivers share this contract. Taskbox completion/expiry uses the public completion helper. Real App driver stores one pending/current request and weak-key actualBGTask→privatebox identity registry, no strong completed-task retention. Same object duplicate ignored; different extra object sameID disposedfalse. Expiry callback seals/revokes synchronously on its queue, MainActor delivers framework completion/events outside locks once. Progress admission checks matching valid/unsealed grant; pre-close admitted update may finish outside locks, no new update admitted after close.

## Public MainActor controller

ContinuedProcessingController: ObservableObject, init(driver:any ContinuedProcessingDriving,now:@escaping @Sendable()->Date={Date()},onRuntimeUnavailable:@escaping @MainActor @Sendable(UUID,ContinuedProcessingRuntimeLoss)->Void={_,_ in}).

Published privateSet state:State=.idle,currentRequest:Request?,grant:Grant?,progress:Progress=.zero,completionOutcome:Outcome?,error:Failure?,receipts:[ContinuedProcessingReceipt]. Computed hasRuntime requires running + matching allthreeidentity fields + grant.isValid. A background revoke closes computed runtime immediately, even before event delivery can update phase.

- register()->Bool explicit/idempotent; no implicit activity in initializer.
- begin(_ request:Request,isForeground:Bool) async->Bool submission acceptance only. Reject missingregistration/notForeground without replacing an existing valid current request; with no active request publish rejected/error. Only a valid new foreground request supersedes old work. Private monotonic generation protects every callback, submit result and cancellation. No generation wrap/reuse. Caller Task cancellation must cancel only its still-current generation, even if submit ignores cancellation. Valid launch before submit return stays running after late accepted return. Rejected-after-launch closes/cancels before terminal publish.
- update(requestID:UUID,progress:Progress,title:String,subtitle:String)->Bool validates bounds/monotonicity/current/nonterminal. Retain newest legitimate prelaunch progress; never forward before actual grant. While running, reject a closed grant even if expiry event is delayed. No Task per update, no timer, no fake progress or walltime percentages.
- finishFiniteArrival(requestID:UUID)->Bool consumes only current finite request with actual provided progress at its immutable goal. Do not return early solely because grant is now closed: query synchronous driver.finish to learn sealed expiry. Invalidate callback generation privately, then call driver.finish(success:true), finally idempotently revoke. Publish/return true only .success. .expired yields expired/loss once; other outcomes unsuccessfulfinished/loss; nil cancels pending and finishes without invented completion outcome/expiry. Actual native arrival is separate15 truth. Unlimited calls rejected, no request mutation/success.
- cancel(requestID:UUID)->Bool only current matching request. Close grant before publication; owned driver.cancel, terminal finished, loss once. Cancel request receipt is not claimed sealed framework outcome (driver.cancel returns none). Supersession is same close/cancel discipline with superseded reason.

Same matching grant duplicate is ignored; distinct extra grant revoked without replacing current. Invalid/wrong/old launch cannot run. All terminal states reject later progress/callback resurrection. No native owner/writer calls. Runtime-loss callback identity conditional, once/generation after actual permission closure. A new begin resets current data; old callbacks/results/cancelhandlers cannot touch it.

## Bounded diagnostic receipts

ContinuedProcessingReceipt immutable public timestamp:Date,requestID:UUID,kind:Kind,event:ContinuedProcessingReceiptEvent,acknowledgedWrites:Int64,cumulativeAcknowledgedDistanceMeters:Double,candidateVersion:Int=1. Public event enum submitted/accepted/launched/rejected(Failure)/expired/invalidated/cancelRequested/superseded/progressUpdated/completionRequested(Outcome?). Receipt construction can remain module-private; public tests observe controller.receipts. Cap256 oldest-first, synchronous bounded append. No coordinates, titles/subtitles, UDID, pairing, rawFFI or credentials; date provider only timestamps observations, no work evidence. No persistence14.

## App adapter and verification ownership

One new App/GoFlyContinuedProcessingDriver.swift (name may be GoFlyContinuedProcessingDriver, MainActor) implements real driver but is not instantiated14. Import BackgroundTasks/Foundation/GoFlyCore. iOS26 legacythrowing vs27async submit, .fail/defaultCPU+network, register wildcard com.neven.gofly.movement.*, actualrequest suffixUUID. No availability/platform fake success; compile actual device/simulatorSDK27.1, final26/27 runtime/receiver experiment remains deferred.

Executor A owns only new Core continuedprocessing files and public unit tests; after coherent API, Executor B owns only new App driver and any narrow offline verifier/harness agreed by Root. Both preserve others/no descendants/phone/commit. Root owns formal14 docs/buildnumber/integration/finalchecks/review/maincommit.14 does not alter existing Service/Authority/Route/Joystick/Recovery/App initialization/plist.

Required public tracers: accepted!=launched; launch-before-return; rejected-after-launch; maxone current generation/ignoredcancel late callbacks; wrong/duplicate/closed grants; completion concurrency once; expiryseal before deferredevent thenfinitearrival false/expired/loss once; validfinitewinner thenlateexpiry no event/loss, trueonce; cancelled/invalidated/failed→lateexpiry silent; duplicateexpiry once; no progress admitted afterclose; validfinitearrival vsindeterminate nofakepercentage/success; invalid/regression/staleupdates. MissingAPI/compiler/environmentRED are recorded separately, not behaviorRED. Actual identityregistry/frameworkcallbacks get SDK/source checks plus final hardware, not fabricated system objects in UI. FullSwift onceheld, unsignedSDKbuilds, nativeverifier/diffcheck, twoaxisreview thencommit.


## 後續唯讀證據與候選限制（不啟用14；15接線前必須解決）

2026-10-18核對[Apple WWDC25](https://developer.apple.com/videos/play/wwdc2025/227/)13:16–14:28及SDK27.1：permitted IDs採wildcard，動態任務以完整具體ID註冊／提交，BGC註冊不受didFinishLaunching期限。v5的literal-wildcard handler dispatch沒有官方建立保證，14保留為未啟用的實驗adapter，不稱SDK已證實或實機可行；15須先經其獨立架構審查處理具體ID一次註冊／bounded history與舊callback，再啟用App。此項是新的接線證據及明確限制，不追認14已支援背景；14第5輪已核准，不額外啟動第6輪。UIBackgroundModes processing只在BGProcessingTask有明確要求，15不為BGC CPU/network任意加入該mode或GPUentitlement。


## 最終離線交付結果

完整SwiftCore355／41suites＋Transport9／1suite，共364PASS；final public focused20／20PASS；未簽署iPhoneOS／iPhoneSimulator SDK27.1 build16皆成功（simulator含arm64／x86_64）；native verifier／diffcheck通過，Standards0／Spec0。App初始化、plist、既有送點／生命週期及三語資源未變，本票未重跑UI；332key三語的13既有驗證仍適用。沒有手機／USB／簽署／安裝／實際scheduler或接收App測試。 Core初版source先於首次10項行為執行，無歷史RED聲稱；20項最終公開矩陣／actualSDKsource與typecheck／build是真實離線證據，沒有呼叫實際system callback或native成功fixture。本票Implementation complete／verification-pending；15另整合及修正上述註冊接線，手機最後集中。
