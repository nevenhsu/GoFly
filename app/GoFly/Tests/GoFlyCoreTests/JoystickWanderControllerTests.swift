import Foundation
import Testing
@testable import GoFlyCore

@Suite @MainActor
struct JoystickWanderControllerTests {
    @Test func enablingWanderPreparesOnceAndUsesOneACKSequencedTargetStream() async throws {
        let commands = ControlledJoystickCommands(), clock = RouteTestClock()
        let controller = JoystickMovementController(commands: commands, clock: clock, wanderBearingSamples: { [0] })
        #expect(controller.setWanderEnabled(true))
        let operation = try #require(controller.intent), target = try #require(controller.wanderTarget)
        #expect(controller.wanderEnabled && controller.input == nil && controller.activeGestureID == nil)
        #expect(controller.phase == .preparing && controller.lastAcknowledgedCoordinate == nil)
        await wait { commands.preparationWaiting }; commands.finishPreparation(.prepared)
        await wait { clock.sleepingCount == 1 }
        clock.advance(by: .milliseconds(500)); await wait { commands.recipeStepWaiting }
        let first = try #require(commands.recipeSteps.first)
        #expect(first.sequence == 1)
        guard case .target(let step) = first.recipe else { Issue.record("Expected auto target recipe"); return }
        #expect(step.targetID == target.id && step.coordinate == target.coordinate)
        #expect(controller.lastAcknowledgedCoordinate == nil && controller.displayInput == nil)
        let actual = GeoCoordinate(latitude: 25.00001, longitude: 121)!
        commands.finishRecipeStep(.acknowledged(JoystickStepReceipt(actualCoordinate: actual,
            actualBearingDegrees: 12, targetID: target.id, arrived: false)))
        await wait { clock.sleepingCount == 1 && controller.canPause }
        #expect(controller.lastAcknowledgedCoordinate == actual && controller.displayInput?.bearingDegrees == 12)
        #expect(controller.intent == operation)
        clock.advance(by: .milliseconds(500)); await wait { commands.recipeStepWaiting }
        #expect(commands.recipeSteps.last?.sequence == 2)
        #expect(controller.setWanderEnabled(false))
        commands.finishRecipeStep(.inputCancelled)
        await wait { controller.phase == .neutral }
        #expect(!controller.wanderEnabled && controller.wanderTarget == nil)
    }
    @Test func manualOverrideWithdrawsAvailableAutoWorkAndReturnsToTheSameTargetStreamOnRelease() async throws {
        let commands = ControlledJoystickCommands(), clock = RouteTestClock()
        let controller = JoystickMovementController(commands: commands, clock: clock, wanderBearingSamples: { [0] })
        #expect(controller.setWanderEnabled(true))
        let operation = try #require(controller.intent), target = try #require(controller.wanderTarget)
        await wait { commands.preparationWaiting }; commands.finishPreparation(.prepared)
        await wait { clock.sleepingCount == 1 }; clock.advance(by: .milliseconds(500))
        await wait { commands.recipeStepWaiting }
        let finger = UUID(), east = JoystickInput(bearingDegrees: 90, strength: 1)!
        #expect(controller.beginGesture(id: finger, input: east))
        #expect(controller.intent == operation && controller.wanderTarget == target)
        #expect(commands.revisions > 0 && controller.displayInput == east)
        commands.finishRecipeStep(.inputCancelled)
        await wait { clock.sleepingCount == 1 }; clock.advance(by: .milliseconds(500))
        await wait { commands.stepWaiting }
        #expect(commands.steps.first?.sequence == 1)
        #expect(controller.endGesture(id: finger))
        #expect(controller.wanderEnabled && controller.input == nil && commands.releases.isEmpty)
        commands.finishStep(.acknowledged(GeoCoordinate(latitude: 25, longitude: 121.00001)!))
        await wait { clock.sleepingCount == 1 }; clock.advance(by: .milliseconds(500))
        await wait { commands.recipeStepWaiting }
        #expect(commands.recipeSteps.last?.sequence == 2)
        #expect(controller.intent == operation && controller.wanderTarget == target)
        #expect(controller.setWanderEnabled(false)); commands.finishRecipeStep(.inputCancelled)
        await wait { controller.phase == .neutral }
    }

    @Test func goAndRandomReplaceTargetsWithoutReplayingOldACKsOrResumingAPause() async throws {
        let commands = ControlledJoystickCommands(), clock = RouteTestClock()
        let controller = JoystickMovementController(commands: commands, clock: clock, wanderBearingSamples: { [0, 90] })
        #expect(controller.setWanderEnabled(true))
        let operation = try #require(controller.intent), oldTarget = try #require(controller.wanderTarget)
        await wait { commands.preparationWaiting }; commands.finishPreparation(.prepared)
        await wait { clock.sleepingCount == 1 }; clock.advance(by: .milliseconds(500))
        await wait { commands.recipeStepWaiting }
        let chosen = MapPlace(id: .mapKit("chosen"), title: "Chosen", coordinate: GeoCoordinate(latitude: 26, longitude: 122)!, address: "Exact address")
        #expect(controller.applyWanderTarget(chosen))
        let selected = try #require(controller.wanderTarget)
        #expect(selected.place == chosen && selected.id != oldTarget.id)
        commands.finishRecipeStep(.acknowledged(JoystickStepReceipt(actualCoordinate: oldTarget.coordinate,
            actualBearingDegrees: 0, targetID: oldTarget.id, arrived: true)))
        await wait { clock.sleepingCount == 1 }
        #expect(controller.wanderTarget == selected)
        clock.advance(by: .milliseconds(500)); await wait { commands.recipeStepWaiting }
        #expect(controller.pause())
        commands.finishRecipeStep(.inputCancelled)
        await wait { controller.phase == .paused }
        #expect(controller.randomizeWanderTarget())
        let random = try #require(controller.wanderTarget)
        #expect(controller.phase == .paused && random.id != selected.id)
        #expect(commands.streamResumes == 0 && commands.resumes == 0)
        #expect(!controller.beginGesture(id: UUID(), input: JoystickInput(bearingDegrees: 0, strength: 1)!))
        #expect(controller.setSpeed(RouteSpeed(kilometersPerHour: 100)!))
        controller.clearWanderError()
        #expect(controller.resume())
        await wait { clock.sleepingCount == 1 }; clock.advance(by: .milliseconds(500))
        await wait { commands.recipeStepWaiting }
        #expect(controller.intent == operation && commands.streamResumes == 1 && commands.resumes == 0)
        let resumed = try #require(commands.recipeSteps.last)
        #expect(resumed.sequence == 2)
        guard case .target(let targetStep) = resumed.recipe else { Issue.record("Expected target"); return }
        #expect(targetStep.targetID == random.id && targetStep.maximumDistanceMeters == JoystickDisplacement.maximumDistanceMeters)
        #expect(controller.setWanderEnabled(false)); commands.finishRecipeStep(.inputCancelled)
        await wait { controller.phase == .neutral }
    }

    @Test func exhaustedArrivalActuallyPausesThenExplicitRetryResumesTheSameIntentAndSequence() async throws {
        let commands = ControlledJoystickCommands(), clock = RouteTestClock(), samples = WanderBearingSequence([[0], [], [90]])
        let controller = JoystickMovementController(commands: commands, clock: clock, wanderBearingSamples: { samples.next() })
        #expect(controller.setWanderEnabled(true))
        let operation = try #require(controller.intent), reached = try #require(controller.wanderTarget)
        await wait { commands.preparationWaiting }; commands.finishPreparation(.prepared)
        await wait { clock.sleepingCount == 1 }; clock.advance(by: .milliseconds(500))
        await wait { commands.recipeStepWaiting }
        commands.finishRecipeStep(.acknowledged(JoystickStepReceipt(actualCoordinate: reached.coordinate,
            actualBearingDegrees: 0, targetID: reached.id, arrived: true)))
        await wait { controller.phase == .suspended }
        #expect(controller.suspensionReason == .targetUnavailable && controller.wanderNeedsTarget)
        #expect(controller.wanderEnabled && controller.wanderTarget == reached && controller.wanderError == .noCandidate)
        #expect(commands.releases == [.pause] && controller.intent == operation)
        controller.clearWanderError(); clock.advance(by: .seconds(30))
        #expect(controller.phase == .suspended && commands.recipeSteps.count == 1)
        #expect(controller.canRetryWander && controller.retryWander())
        let next = try #require(controller.wanderTarget)
        #expect(next.id != reached.id && !controller.wanderNeedsTarget)
        #expect(controller.intent == operation && commands.streamResumes == 1)
        await wait { clock.sleepingCount == 1 }; clock.advance(by: .milliseconds(500))
        await wait { commands.recipeStepWaiting }
        #expect(commands.recipeSteps.last?.sequence == 2)
        #expect(controller.setWanderEnabled(false)); commands.finishRecipeStep(.inputCancelled)
        await wait { controller.phase == .neutral }
    }

    @Test(arguments: [false, true])
    func inactiveWanderPausesAnInstalledStreamOrRetiresAnUnclaimedOneUntilExplicitResume(installed: Bool) async throws {
        let commands = ControlledJoystickCommands(), clock = RouteTestClock()
        let controller = JoystickMovementController(commands: commands, clock: clock, wanderBearingSamples: { [0] })
        #expect(controller.setWanderEnabled(true))
        let old = try #require(controller.intent), target = try #require(controller.wanderTarget)
        await wait { commands.preparationWaiting }; commands.finishPreparation(.prepared)
        await wait { clock.sleepingCount == 1 }
        if installed {
            clock.advance(by: .milliseconds(500)); await wait { commands.recipeStepWaiting }
            commands.finishRecipeStep(.acknowledged(JoystickStepReceipt(actualCoordinate: GeoCoordinate(latitude: 25.00001, longitude: 121)!,
                actualBearingDegrees: 0, targetID: target.id, arrived: false)))
            await wait { clock.sleepingCount == 1 }
        }
        controller.releaseForInactiveScene()
        await wait { controller.phase == (installed ? .paused : .suspended) }
        #expect(controller.suspensionReason == .sceneInactive && controller.wanderEnabled && controller.wanderTarget == target)
        #expect(commands.releases == [installed ? .pause : .endGesture])
        #expect(!controller.canResume)
        controller.sceneDidBecomeActive()
        clock.advance(by: .seconds(10))
        #expect(controller.canResume && commands.recipeSteps.count == (installed ? 1 : 0))
        #expect(!controller.beginGesture(id: UUID(), input: JoystickInput(bearingDegrees: 90, strength: 1)!))
        #expect(controller.resume())
        if installed { #expect(controller.intent == old && commands.streamResumes == 1) }
        else {
            #expect(controller.intent?.id != old.id)
            await wait { commands.preparationWaiting }; commands.finishPreparation(.prepared)
        }
        await wait { clock.sleepingCount == 1 }; clock.advance(by: .milliseconds(500))
        await wait { commands.recipeStepWaiting }
        #expect(commands.recipeSteps.last?.sequence == (installed ? 2 : 1))
        #expect(controller.setWanderEnabled(false)); commands.finishRecipeStep(.inputCancelled)
        await wait { controller.phase == .neutral }
    }

    @Test func anExplicitManualGestureMayResumeOnlyTheInternalTargetSuspensionAndReleasePausesAgain() async throws {
        let commands = ControlledJoystickCommands(), clock = RouteTestClock(), samples = WanderBearingSequence([[0], []])
        let controller = JoystickMovementController(commands: commands, clock: clock, wanderBearingSamples: { samples.next() })
        #expect(controller.setWanderEnabled(true))
        let operation = try #require(controller.intent), target = try #require(controller.wanderTarget)
        await wait { commands.preparationWaiting }; commands.finishPreparation(.prepared)
        await wait { clock.sleepingCount == 1 }; clock.advance(by: .milliseconds(500))
        await wait { commands.recipeStepWaiting }
        commands.finishRecipeStep(.acknowledged(JoystickStepReceipt(actualCoordinate: target.coordinate,
            actualBearingDegrees: 0, targetID: target.id, arrived: true)))
        await wait { controller.phase == .suspended }
        let finger = UUID(), input = JoystickInput(bearingDegrees: 90, strength: 1)!
        #expect(controller.canBeginGesture && controller.beginGesture(id: finger, input: input))
        #expect(controller.intent == operation && commands.streamResumes == 1 && controller.wanderNeedsTarget)
        #expect(controller.phase == .moving)
        guard controller.phase == .moving else {
            controller.releaseForInactiveScene()
            if commands.preparationWaiting { commands.finishPreparation(.cancelled) }
            return
        }
        await wait { clock.sleepingCount == 1 }; clock.advance(by: .milliseconds(500))
        await wait { commands.stepWaiting }
        #expect(commands.steps.last?.sequence == 2)
        commands.finishStep(.acknowledged(GeoCoordinate(latitude: 25, longitude: 122)!))
        await wait { clock.sleepingCount == 1 }
        #expect(controller.endGesture(id: finger))
        await wait { controller.phase == .suspended }
        #expect(controller.suspensionReason == .targetUnavailable && commands.releases == [.pause, .pause])
        #expect(controller.setWanderEnabled(false)); await wait { controller.phase == .neutral }
    }

    @Test func disablingARetiredSceneSuspensionRestoresTheManualNeutralEntry() async throws {
        let commands = ControlledJoystickCommands(), clock = RouteTestClock()
        let controller = JoystickMovementController(commands: commands, clock: clock, wanderBearingSamples: { [0] })
        #expect(controller.setWanderEnabled(true))
        await wait { commands.preparationWaiting }; commands.finishPreparation(.prepared)
        await wait { clock.sleepingCount == 1 }
        controller.releaseForInactiveScene()
        await wait { controller.phase == .suspended }
        controller.sceneDidBecomeActive()
        #expect(controller.setWanderEnabled(false))
        #expect(controller.phase == .neutral && controller.canBeginGesture)
        #expect(controller.suspensionReason == nil && controller.wanderTarget == nil)
    }

    @Test(arguments: [false, true])
    func manualHeldArrivalFailureKeepsManualMovingAndReleasePausesOnlyWhenNoReplacementWasChosen(replaceWhileHeld: Bool) async throws {
        let commands = ControlledJoystickCommands(), clock = RouteTestClock(), samples = WanderBearingSequence([[0], []])
        let controller = JoystickMovementController(commands: commands, clock: clock, wanderBearingSamples: { samples.next() })
        #expect(controller.setWanderEnabled(true))
        let operation = try #require(controller.intent), target = try #require(controller.wanderTarget)
        await wait { commands.preparationWaiting }; commands.finishPreparation(.prepared)
        await wait { clock.sleepingCount == 1 }
        let finger = UUID()
        #expect(controller.beginGesture(id: finger, input: JoystickInput(bearingDegrees: 90, strength: 1)!))
        clock.advance(by: .milliseconds(500)); await wait { commands.stepWaiting }
        commands.finishStep(.acknowledged(target.coordinate))
        await wait { clock.sleepingCount == 1 }
        #expect(controller.wanderNeedsTarget && controller.wanderError == .noCandidate)
        #expect(controller.phase == .moving && commands.releases.isEmpty && controller.intent == operation)
        clock.advance(by: .milliseconds(500)); await wait { commands.stepWaiting }
        commands.finishStep(.acknowledged(GeoCoordinate(latitude: 26, longitude: 122)!))
        await wait { clock.sleepingCount == 1 }
        #expect(commands.steps.count == 2 && commands.recipeSteps.isEmpty)
        if replaceWhileHeld {
            #expect(controller.applyWanderTarget(MapPlace(id: .mapKit("replacement"), title: "Replacement",
                coordinate: GeoCoordinate(latitude: 27, longitude: 123)!)))
        }
        #expect(controller.endGesture(id: finger))
        if replaceWhileHeld {
            #expect(!controller.wanderNeedsTarget && commands.releases.isEmpty)
            clock.advance(by: .milliseconds(500)); await wait { commands.recipeStepWaiting }
            #expect(commands.recipeSteps.last?.sequence == 3 && controller.intent == operation)
            #expect(controller.setWanderEnabled(false)); commands.finishRecipeStep(.inputCancelled)
            await wait { controller.phase == .neutral }
        } else {
            await wait { controller.phase == .suspended }
            #expect(controller.suspensionReason == .targetUnavailable && commands.releases == [.pause])
            #expect(controller.setWanderEnabled(false)); await wait { controller.phase == .neutral }
        }
    }

    @Test func failedFirstSelectionDoesNotEnableOrPrepareAndFailedRandomPreservesTarget() async throws {
        let commands = ControlledJoystickCommands(), clock = RouteTestClock(), samples = WanderBearingSequence([[], [0], []])
        let controller = JoystickMovementController(commands: commands, clock: clock, wanderBearingSamples: { samples.next() })
        #expect(!controller.setWanderEnabled(true))
        #expect(!controller.wanderEnabled && controller.intent == nil && controller.wanderError == .noCandidate)
        #expect(!commands.preparationWaiting && commands.intent == nil)
        #expect(controller.setWanderEnabled(true))
        await wait { commands.preparationWaiting }; commands.finishPreparation(.prepared)
        await wait { clock.sleepingCount == 1 }
        let original = controller.wanderTarget, operation = controller.intent
        #expect(!controller.randomizeWanderTarget())
        #expect(controller.wanderTarget == original && controller.intent == operation && controller.phase == .moving)
        controller.clearWanderError()
        #expect(controller.wanderEnabled && controller.wanderError == nil)
        #expect(controller.setWanderEnabled(false)); await wait { controller.phase == .neutral }
    }

    @Test func sameLeaseAndRepeatedMovementBoundariesAreIdempotentAndLateACKCannotReviveAuto() async throws {
        let commands = ControlledJoystickCommands(), clock = RouteTestClock()
        let controller = JoystickMovementController(commands: commands, clock: clock, wanderBearingSamples: { [0] })
        #expect(controller.setWanderEnabled(true))
        let operation = try #require(controller.intent), target = try #require(controller.wanderTarget)
        await wait { commands.preparationWaiting }; commands.finishPreparation(.prepared)
        await wait { clock.sleepingCount == 1 }; clock.advance(by: .milliseconds(500))
        await wait { commands.recipeStepWaiting }
        commands.events.send(.movementBoundary(operation.lease)); commands.events.send(.movementBoundary(operation.lease))
        #expect(controller.wanderEnabled && controller.intent == operation)
        let other = MovementTaskLease()
        commands.events.send(.movementBoundary(other)); commands.events.send(.movementBoundary(other))
        #expect(!controller.wanderEnabled && controller.phase == .neutral && controller.intent == nil)
        commands.finishRecipeStep(.acknowledged(JoystickStepReceipt(actualCoordinate: target.coordinate,
            actualBearingDegrees: 0, targetID: target.id, arrived: true)))
        commands.events.send(.movementBoundary(nil)); controller.sceneDidBecomeActive()
        #expect(!controller.wanderEnabled && !controller.canRetryWander && controller.lastAcknowledgedCoordinate == nil)
        clock.advance(by: .seconds(30))
        #expect(commands.recipeSteps.count == 1 && !commands.preparationWaiting)
    }

    @Test func disablingWanderWhileManualIsHeldKeepsThatInputAndIntentUntilManualRelease() async throws {
        let commands = ControlledJoystickCommands(), clock = RouteTestClock()
        let controller = JoystickMovementController(commands: commands, clock: clock, wanderBearingSamples: { [0] })
        #expect(controller.setWanderEnabled(true))
        let operation = try #require(controller.intent), finger = UUID(), input = JoystickInput(bearingDegrees: 90, strength: 1)!
        #expect(controller.beginGesture(id: finger, input: input))
        #expect(controller.setWanderEnabled(false))
        #expect(controller.input == input && controller.intent == operation && controller.wanderTarget == nil)
        #expect(commands.releases.isEmpty)
        await wait { commands.preparationWaiting }; commands.finishPreparation(.prepared)
        await wait { clock.sleepingCount == 1 }; clock.advance(by: .milliseconds(500))
        await wait { commands.stepWaiting }
        #expect(commands.recipeSteps.isEmpty && commands.steps.last?.sequence == 1)
        #expect(controller.endGesture(id: finger))
        commands.finishStep(.acknowledged(GeoCoordinate(latitude: 25, longitude: 121.00001)!))
        await wait { controller.phase == .neutral }
        #expect(commands.releases == [.endGesture])
    }

    private func wait(_ condition: @MainActor () -> Bool) async {
        let deadline = ContinuousClock.now + .seconds(2)
        while !condition() && ContinuousClock.now < deadline { await Task.yield() }
        #expect(condition())
    }
}

private final class WanderBearingSequence: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [[Double]]
    init(_ values: [[Double]]) { self.values = values }
    func next() -> [Double] { lock.withLock { values.isEmpty ? [] : values.removeFirst() } }
}
