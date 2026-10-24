import Foundation
import Testing
@testable import GoFlyCore

@Suite struct WanderStartRequestGateTests {
    @Test func onlyTheMatchingOriginAcknowledgementConsumesTheDeferredStartOnce() {
        var gate = WanderStartRequestGate()
        let originIntent = UUID()
        gate.waitForOriginAcknowledgement(originIntent)

        let mismatchedACK = gate.consumeAcknowledgement(for: UUID())
        #expect(!mismatchedACK)
        let matchingACK = gate.consumeAcknowledgement(for: originIntent)
        #expect(matchingACK)
        let duplicateACK = gate.consumeAcknowledgement(for: originIntent)
        #expect(!duplicateACK)
        #expect(gate.originIntentID == nil)
    }

    @Test func matchingFailureOrCancellationDoesNotLeaveADeferredStart() {
        var gate = WanderStartRequestGate()
        let failedIntent = UUID()
        gate.waitForOriginAcknowledgement(failedIntent)
        let matchedFailure = gate.consumeFailure(for: failedIntent)
        #expect(matchedFailure)
        let lateACK = gate.consumeAcknowledgement(for: failedIntent)
        #expect(!lateACK)

        gate.waitForOriginAcknowledgement(UUID())
        gate.cancel()
        #expect(gate.originIntentID == nil)
    }
}
