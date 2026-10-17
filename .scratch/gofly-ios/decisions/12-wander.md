# 票12：自動漫步、手動接管與Go更換目標（Advisor核准v3）

票11已於57565c7提交（完整Swift269、UI38／38、unsigned build13及雙軸零finding）；12以此為實作／審查基準，依既定publicseam逐條TDD。原始研究在ignored work，核准方案與凍結API移入本ADR。來源為issues/12-ticket、PRODUCT-SPEC06及research12。延續使用者不接手機、最後集中驗收；Console前次Transport closed，只用既有真實cache，不冒新讀回。無第四mode、無路網要求、無nativequeue/API/header變更。Root寫方案，Advisor只讀回Root，無Planner或descendants。

## 用戶行為與唯一loop

漫步是搖桿checkbox，勾選時有效origin為confirmed sim優先／≤15s有效GPS，不用displaycache。選出第一target才啟用；必要prepare沿11最多3次/Retry/Cancel。既有manual intent正在preparing/moving或paused時沿用同intent/lease，paused保持paused；phase.neutral無activegesture則新intent prepare，保留resumed-neutral舊owner到firstclaim。checkbox不是位置ACK，不先安裝lease。

JoystickMovementController仍只有一個clockloop，manualoverride輸入優先，否則target recipe；ACK後fresh500ms、max1 pending、不追補。自動呈現的input不呼叫gesture方法。手動接管不換intent/lease/target/speed/勾選；放手只revision中和manual，已claim等真實結果後freshcadence回auto，不release整個owner。Pause中放手/Go/random不自動Resume。關閉auto清target/candidate/history、停止auto不clear；若仍有有效手指輸入，繼續同owner手動，之後放手依11退休；沒有手指則endGesture/settle。被另一明確Go/Start實際claim的ended才關auto/清候選，純瀏覽另一mode不移動或換owner。

## Service公有相容擴充

保留11既有manual sendJoystickStep(displacement:)及outcome.coordinate API，內部轉同一個private recipe executor，不能複製另一套native writer。新增public validated JoystickTargetStep(targetID:UUID,coordinate:GeoCoordinate,maximumDistanceMeters:Double positivefinite≤125/9)、JoystickStepRecipe.manual(displacement)/.target(targetStep)；新增帶receipt的sendJoystickStep(recipe:) overload，使用獨立新enum JoystickRecipeStepOutcome，其failurecases與11對應，但acknowledged(JoystickStepReceipt)。既有JoystickStepOutcome及.acknowledged(GeoCoordinate)完全保留；manual wrapper把新receipt.actualCoordinate映回舊outcome，不能改舊enum associated value。receipt包含actualCoordinate、actualBearingDegrees:Double?、targetID:UUID?、arrived:Bool。manual receipt有capturedbearing、無targetID/arrival；target receipt是FIFOhead實際解析的coordinate/bearing/targetID/arrival，不由controller重算實際送點。

Service沿既有owner/sequence/inputRevision/stopgeneration/watchdog/FIFO，在head通過舊health/owner驗證、讀最新origin，再由純Core target geometry讀取greatcircle距離和bearing、clamp最後一步，捕獲fresh CAS snapshot建同gate。尚有舊ownerACK時，必須先完成truth publication才算target方向；無await夾在origin/geometry/snapshot。coordinate與receipt存入同tick，claim/unknown/availablecancel語意不變；ACK只發布這份實際coordinate。recipe切換先revise，available舊recipe撤回不耗sequence；claimed舊recipeACK更新truth，但若其targetID不等currenttargetID，不完成新target。

target geometry沿6371000m球面，shortest greatcircle、跨日界與poles可用；exact antipodal用來源longitude的localnorth定義確定方向，無NaN。距離≤stepmax則送exacttarget；距離0仍明確送相同target座標並等ACK才到達，bearing nil保留先前顯示方向，不虛構角度。最大step由合法speed m/s×0.5與共用maximum constant產生，避免100 rounding。manualconstructor仍拒max.nextUp。

新增resumeJoystickStream(executionID,lease)->Bool只可對已paused/installed/healthy/actualidle owner原子更新runState.running、neutral=false、paused=false、新inputgeneration後publish；既有resumeJoystick仍neutral、新gesture/newlease語意不變。不新增通用功能flags。Controller將nextSequence從run local提升為該intent的ACK-only狀態，auto Resume同intent保留next，manual新intent重設1；各run帶generation，舊結果不能推進新intent。

## Selector與抵達

純同步selector public seam，輸入validorigin/speed/currenttarget/history和可注入最多32個bearing樣本，產生valid target或noCandidate。production使用SystemRandomNumberGenerator的uniform[0,360)32次；ring距離speed m/s×600秒。只要求有效球面座標，不引入道路／陸地／MapKit阻擋。排除距origin/currenttarget/最近history≤1m的候選。history明定為同次checkbox session最近100個成功套用目的地的FIFO（包括Go/random/autoarrival），只記commit，不含failed/cancelled候選；disable清session，不持久化，也不恢復執行。

首次選取失敗不啟用／不prepare；明確random選取失敗保留原target/phase/candidate，原位可關error；抵達後選不到下一站則停止auto ticker並保留最後ACK、勾選與error，提供明確Retry，不空轉、不假已到新點。隨機是同步bounded，沒有async latest-selector覆寫；reverse metadata如需補名仍依targetID世代僅補資料。

auto target ACK的arrived只在capturedtargetID==currenttargetID時觸發下一站；manualoverride ACK另以capturedcurrenttargetID和actualcoordinate距target≤1m判定接管期間已抵達，不能用GPS或渲染位置。接管期間抵達會更新保存target/history但manual仍控制，放手朝最新target。已claim舊target或手動recipe的遲到ACK不誤算新target到達；Go換target與arrival都在MainActor串行更新revision/ID。

## 暫停／背景／失敗

auto已installed才允許Pause；保留target/勾選，neutralize manual並settle actualclaim，Resume用resumeJoystickStream同lease且freshcadence。準備或firstclaim前的pause不假稱authoritypaused。scene非active：manual仍沿11end；auto若installed且healthy則pause並清override，原已paused保持；未installed則取消prepare/retire實際step，local phase.suspended（新增，與devicepaused分開），保留勾選/target/速度，前景無自動送點。explicitResume才newintent prepare；如果有效origin/authority不可用則顯示具體原因，不用cache。已claimed等待真實ACK再退休/本地suspended，unknown仍需Stop。

已抵達無下一站採下面明定的「有效installed owner實際pause」不變量，不留下running authority卻永久沒有ticker的未定狀態。disable/Stop/新owner交接清這個localcontinuation；不可被遲到selector/ACK復活。13再接恢復證據，12不預先假設14背景權限，無前景觸發的背景續跑。

## Candidate／Pin／App

auto啟用時獨立wander CandidateController，Map tap只建precisecoordinate candidate、反查只補同ID metadata，不送點/不改target/不移鏡頭。另一次tap/新query/離開auto取消遲到補名。Go只捕捉candidate、同步套target＋revision，保留pause/override/speed/intent/lease，不調teleport/prepare。成功clearMatching(candidateID)，失敗保留candidate與原target。autoarrival保留待Go candidate；random成功清candidate、失敗保留；disable/另一任務actualhandoff清candidate。

currenttarget outline landmark icon無Go，candidate blackdot/thinline icon有Go，皆無caption、各44pt；再次點各自開穩定place snapshot共用details/star，查看收藏不Go。projection分別傳兩點；相近重疊時可做最小視覺offset/leader保持兩個44pt可點，不能改實際座標或強制平移。maptap不含既有Pin/controls/joystickdrag。全域candidate camera observer在joystick分支明確不自動focus；explicitrecenter仍可用。

底部同列checkbox至少44與右側126×44無框random，未啟用只隱藏random；無origin仍小SetStart，checkbox不得用假origin啟用。長英文/AX允許同一區合理換行或捲動，不縮字、不第四mode。UI thumb在manualoverride跟手，auto用實際receiptbearing轉cameraheading；首次ACK前可置中，不能用渲染方向啟用manual。marker維持arrow+outline/no circle和等待50%。新文案三語同票交付，沒有pad下文字。

## 執行與驗證

11commit後A擁ServiceController/JoystickCommanding recipe與resumeStream及service publictests；B擁selector/targetgeometry/controller/clock與realService integrationpublictests；Root App/Canvas/currenttarget/candidate/lifecycle；UI slice後續另安排Panel/locales/UITests，≤4slots。A/B精確API先read-only凍結供Root確認，不自行重設計；無descendants/commit/phone。

逐條publicseam RED→GREEN：selector32bounded/history/distance/invaliddraw；head latestorigin/zero/finalclamp/dateline/pole/antipodal與同gate; auto singlelease/sequence/ACKarrival-next; override available/claimed/paused; Go/random oldtargetACK/revision與noCandidate原狀；inactive installedpause vs未installedlocalsuspended；Stop/watchdog/unknown/actualhandoff不復活；所有11/route原tests。UI不造native成功/GPS，正向loop由publiccontrolledDevice測試；可驗無origin/realfailedGo/Pinbrowse/star/noGo/三語AX/keyboard/基本mode回歸，完整UI一次於最後held。適當host/typecheck、最後fullSwift、unsignedbuild、locale/native/diff與雙軸review後commit，真機由使用者最後集中驗收。

範圍不含13恢復持久化/14背景機制/15正式背景runner/M1M2Mac交付。所有公開安全不變量保留，不為減重抽取route lifecycle。

## v2修正：P12-01與P12-02累積ledger

- P12-01 INCORPORATED：獨立JoystickRecipeStepOutcome，不改11的JoystickStepOutcome或manual方法；同一private recipe executor只產生內部receipt，wrapper映射，舊publictests必須原樣相容。
- P12-02 INCORPORATED：選擇實際pause installed stream，而非保留running-without-ticks。下列完整interaction是本v2正式不變量。

目前target已ACK抵達但selector找不到下一站時，保存wanderNeedsTarget=true與noCandidate error、原target/history/checkbox/最後ACK，不假新target。若無manualoverride，立刻停loop並沿releaseJoystick(.pause)等待actualidle，成功後local movement.phase.suspended(reason:targetUnavailable)，底層確實healthy paused同lease；release不成功或settlementunknown沿Stop/repair，不能偽造suspendedhealthy。若manualoverride仍按住，只停止auto recipe選擇，manual input/loop繼續同owner；放手後若wanderNeedsTarget仍true，才按相同流程pause/suspended。manual期間Go/random成功取得新target會清wanderNeedsTarget但不搶input，放手正常回auto；失敗保留原狀態。

Go或random在local.suspended或user.phase.paused時只換target（新ID/history/controlrevision），保留暫停，不自動resume；成功可clear wanderNeedsTarget，但suspension直到明確Resume/Retry。Retry作為明確操作：若已有Go/random選好的未抵達有效target就使用它，否則先selector；成功且scene active、healthy paused lease實際仍有效，才resumeJoystickStream同intent/lease並freshcadence；失敗保留paused/error，不新建intent或prepare。user主動Pause的普通.paused不被random/Go/純關error解除，只有既有Resume。

若在targetUnavailable suspended時明確新manualgesture：它可作為使用者新的手動要求，先resumeJoystickStream同healthy pausedowner再用manualrecipe；只允許此內部暫停原因，不繞過userPause或sceneInactive。保持wanderNeedsTarget，放手仍pause/suspended；手動途中成功Go/random則回正常override規則。service拒絕resume時不送點、不改lease/phase，顯示具體錯誤。因noCandidate需要ACK才成立，這條必有installedowner，不可用newintent假resume。

scene inactive時：若原為targetUnavailable suspended，底層已paused，維持，不因返回自動Retry；若manual正在繼續但needsTarget，釋放input並實際pause，仍suspended；其他auto健康installed沿原方案pause，未installed才retire/localsuspended需明確newprepare。disable無論上述何態皆end/retire同owner並清auto/candidate/history，不clear位置；新任務actualclaim或Stop作廢所有suspension/Retry授權。Go/random/Retry/override與可用authority/scene世代綁定，舊結果無法恢復。

新增必要public矩陣：arrival noCandidate→actualpausedlease→Retry同lease/sequence；Go/random suspended只換target不resume；manual-held arrivalfail仍只manual送點、release才pause；internal-suspended manualgesture可明確resume但userpaused不可；inactive/disable/Stop/newclaim從各分支不復活。


## 精確API凍結（Root核可）

Root依Advisor已核准planv2核可A/B read-only提案。這是實作形狀對齊，不改singlewriter／samelease／ACK-only／foreground等核准語意。

## A ownership

JoystickCommanding.swift保留全部11方法/enum；新增：

```swift
public struct JoystickTargetStep: Equatable, Sendable {
  public let targetID: UUID
  public let coordinate: GeoCoordinate
  public let maximumDistanceMeters: Double
  public init?(targetID: UUID, coordinate: GeoCoordinate, maximumDistanceMeters: Double)
}
public enum JoystickStepRecipe: Equatable, Sendable {
  case manual(JoystickDisplacement), target(JoystickTargetStep)
}
public struct JoystickStepReceipt: Equatable, Sendable {
  public let actualCoordinate: GeoCoordinate
  public let actualBearingDegrees: Double?
  public let targetID: UUID?
  public let arrived: Bool
  public init(actualCoordinate: GeoCoordinate, actualBearingDegrees: Double?, targetID: UUID?, arrived: Bool)
}
public enum JoystickRecipeStepOutcome: Equatable, Sendable {
  case acknowledged(JoystickStepReceipt), notSent(JoystickFailure)
  case unconfirmed(DeviceServiceFailure), inputCancelled, cancelled
}
// @MainActor JoystickCommanding新增
func sendJoystickStep(executionID: UUID, lease: MovementTaskLease, sequence: UInt64,
  expectedInputRevision: JoystickInputRevision, recipe: JoystickStepRecipe) async -> JoystickRecipeStepOutcome
func resumeJoystickStream(executionID: UUID, lease: MovementTaskLease) -> Bool
```

TargetStep finite>0且≤共用125/9；receipt由actualACK才返回，manualwrapper映回既有GeoCoordinate，failurecases一對一。resumeStream只installed/healthy/paused/actualidle+generation/quarantine通過，更新running/neutralfalse/pausedfalse/newinputgeneration，不重設intent/lease/lastSequence，不prepare/送點。A ownsServiceController、JoystickCommanding及servicepublictests；不改B/App。

## B ownership

採A提案的純resolution避免把計算當ACK，不採早先B直接回receipt的形狀：

```swift
public struct JoystickTargetStepResolution: Equatable, Sendable {
  public let coordinate: GeoCoordinate
  public let bearingDegrees: Double?
  public let arrived: Bool
}
extension JoystickGeodesy {
  public static func resolveTarget(from origin: GeoCoordinate, step: JoystickTargetStep) -> JoystickTargetStepResolution
  public static func distanceMeters(from origin: GeoCoordinate, to target: GeoCoordinate) -> Double
}
public struct WanderTarget: Identifiable, Equatable, Sendable {
  public let id: UUID
  public let place: MapPlace
  public var coordinate: GeoCoordinate { place.coordinate }
  public init(id: UUID = UUID(), place: MapPlace)
}
public enum WanderSelectionFailure: String, Error, Sendable {
  case noCandidate = "joystick.error.noCandidate"
  public var localizationKey: String { rawValue }
}
public enum WanderSuspensionReason: String, Sendable { case targetUnavailable, sceneInactive }
public enum WanderTargetSelector {
  public static func select(origin: GeoCoordinate, speed: RouteSpeed, currentTarget: WanderTarget?,
    history: [GeoCoordinate], bearingSamples: [Double]) -> WanderTarget?
}
```

Resolution只表示本步計算，A存進tick並配captured targetID；ACK才receipt。Zero stillsetexacttarget/bearingnil/arrivedtrue；最後步clamp，shortestgreatcircle／antipodal localnorth。Ring共用internal球面helper，不能放寬manual displacement最大值。Selector只32samples，skipnonfinite，normalizefinite，history suffix100，10minring／1m exclusion；首合格newUUID+exactMapPlace，無async。

Controller init新增 `wanderBearingSamples: @Sendable () -> [Double]` default32uniform；原參數sourcecompatible。published新增wanderEnabled/wanderTarget/wanderNeedsTarget/wanderError/suspensionReason；phase新增.suspended保留原rawvalues。displayInput manual優先，auto只最後actual receiptbearing（首次可nil，zero保留）。input仍manual-only；nextSequence移至intent scope ACK-only。

```swift
@discardableResult public func setWanderEnabled(_ enabled: Bool) -> Bool
@discardableResult public func randomizeWanderTarget() -> Bool
@discardableResult public func applyWanderTarget(_ place: MapPlace) -> Bool
@discardableResult public func retryWander() -> Bool
public func sceneDidBecomeActive() // gate only, noresume/prepare
public func clearWanderError()
public var canSetWanderEnabled: Bool
public var canRandomizeWanderTarget: Bool
public var canApplyWanderTarget: Bool
public var canRetryWander: Bool
public var displayInput: JoystickInput?
```

userPause.phasepaused/reasonnil；targetUnavailable.suspended/reasontargetUnavailable且實際pausedlease；inactiveinstalled.paused/reasonsceneInactive，inactiveuninstalled.suspended/scenInactive已retire、Resume新prepare。v2noCandidate interactions完整保留（manualheld先只manual、releasepause；Go/random suspended只換target；Retry同lease；internaltargetUnavailable明確manual可resume但userPause/sceneInactive不可繞過）。

## Root/UI ownership與依賴

Root App/Canvas/獨立wanderCandidate/兩種Pin/details／noautomaticcamera／sceneactivehook；Bool成功才clearMatchingGo／random成功resetcandidate，arrival不碰candidate。UI slice在Core可編譯後接Panel/三語/UITests，不造nativeACK/GPS，不改model。11完整驗證＋commit門檻已滿足，Root依下列波次明確releaseA/B。所有人不revert他人、不descendants、不commit、不操作手機。


## 執行波次（11提交後）

Root依已核准v2／精確API凍結作routine分工，不變更行為：

1. 11完整驗證／commit後Root明確release A：先擁有新JoystickStepRecipe.swift的四種command models（validatedtargetstep/recipe/receipt/separateoutcome）及publicmodel tracer RED→GREEN；此時不先把新protocol requirements掛上造成全package不相容。A報models可編譯並held波次。
2. B在Amodels存在後擁有JoystickTargetStepResolution／JoystickGeodesy的targetdistance/resolve及internal球面ring helper、WanderTarget／WanderTargetSelector；公開pureseam垂直RED→GREEN。B也擁現有Joystick controller mock的新增recipe/resumeStream方法（先額外方法不破壞舊protocol，等A新增requirement時不缺conformance）。B報geometry/coherenttypes可編譯波次。
3. A在Bgeometry存在後才同一coherent波次新增protocolmethods、單一private recipe executor/legacywrapper、resumeStream及servicepublictracers。保留舊route與manual矩陣，無第二writer/nativequeue／header變動。A方法必須透過真正Coregeometry，不能temporaryfakeACK/constantcoord來讓compilegreen。
4. B等A新coherentconformance後才完成Controller singleloop auto/manual/paused/suspended/targetID/sequence及realServiceintegration publicTDD。可以先處理不依新method的selector公有tracers，不做bulkimaginarytests。Root App在Bpublicsurfacecoherent後整合兩Pin/candidate/camera/lifecycle；UI slice再接Panel/三語/UITests。

Ownedfiles：A JoystickCommanding/ServiceController/newJoystickStepRecipe/service+newmodelcommands tests；B JoystickGeodesy/newTargetStepResolution/WanderTarget/Selector/JoystickMovementController及Btests/mocks；Root App/Canvas/issue/ADR/spec/docs/build；UI slice只Panel/locales/newUITests及必需既有helper，需Root後續明確release。所有agent不revert他人、不互改ownership、不descendants、不commit、不phone；Rootfinalreview/verification/commit。

若A/B遇到交叉依賴或凍結API缺口，只向Root報告，不自行加placeholder成功／新writer／重設計。11fullUI已38／38通過，Root按波次分別授權，不以未凍結API造placeholder成功。


## v3 amendment P12-03：retired local continuation 的實際控制權邊界

v2 的 sceneInactive 未安裝 owner 會真的 retire/remove Service owner，再保留 Controller local suspended continuation。此時舊 owner 已無法在後續 Stop／另一 Go 或 route actual claim 時發 ended(oldID)。不能拿 movementAdmissionRevision 或 availability 當 actual claim，因 failed preparation 也改 admission。

選定最窄擴充：JoystickCommandEvent 新增 `case movementBoundary(MovementTaskLease?)`。MainActor Service 僅在 (a) stop() guard canStop 通過、Stop generation 已作廢並 revokeAll 之後 publish nil；(b) 既有 endSupersededRoutes() 的 actual dispatch-proven path，snapshot.lease 非 nil 時 publish該 lease。此 helper 目前僅被 pointDidDispatch、routeDidDispatch、joystickDidDispatch 的 hasDispatched 證據路徑呼叫。可重複發布，Controller 必須 idempotent；不加新 writer、不公開可寫 authority、不做 native 或持久化 proof。Stop guard false 不改既有回傳/phase、不發布偽 accepted Stop；真正沒有可停止服務時 UI 也無 Stop 動作，使用者可取消 checkbox。已 stopped local continuation 遇到新 actual movement 仍會失效。

Controller 收到 nil accepted Stop 或 nonnil lease 不同於目前 continuation/intent lease 時，即作廢 wander local continuation：遞增自身 generation、取消未 claim 的 task/transition、清 manual input/gesture、target/history/checked/error/intent 等回到 neutral，App 由 checked false 清 wander candidate。若有舊 actual claimed command 仍回覆，Service 依原流程刊登 truth；Controller 舊generation不能回 auto。相同 lease 的 actual claim 不得自我停用；pure prepare／failed prepare／available cancel／ordinary release 不 emit movementBoundary，舊 local suspension得保留。nil Stop 對所有 auto continuation 一視同仁，不依 owner仍在字典。既有 ended/unknown/interrupted 行為保留，事件只補缺少實際owner時的授權撤銷證據。

精確API由 A 擁有 JoystickCommanding enum + Service producer + Service公共tracer；B 擁有 consumer及 realService Controller public tests。Advisor核准後 Root先 release A、新case時 B同 coherent波次加 exhaustive case，避免編譯缺口；如需 B可先接受無新case的私有 consumer helper，A case 與 B switch 一起整合。不可用 default 忽略未識別安全事件。

新增必要public tracer：uninstalled inactive suspended→Stop accepted→checked false/neutral/Resume不送；同狀態→別的 point/route真正 claim即失效（即使 ACK unknown）；另一操作 prepare失敗或 available cancel不失效；自己 samelease claim 不失效；late old ACK及重複boundary不復活。不擴張到13恢復或14背景產品選擇。


Advisor round3/5：PLAN_APPROVED；P12-01/02/03 全部INCORPORATED，無剩餘finding。12原v2獨立工作持續，P12-03由Root於核准後另release A producer與B consumer。
