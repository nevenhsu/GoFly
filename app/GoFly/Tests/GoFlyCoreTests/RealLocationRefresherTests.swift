import Foundation
import Testing
@testable import GoFlyCore

@Suite @MainActor
struct RealLocationRefresherTests {
    @Test func anActiveSceneRefreshesEveryIntervalWithinTheOriginFreshnessWindow() async {
        let source = CountingFixSource(), clock = RouteTestClock()
        let refresher = RealLocationRefresher(source: source, clock: clock)
        #expect(RealLocationRefresher.interval < .seconds(15))

        refresher.sceneDidBecomeActive()
        await wait { clock.sleepingCount == 1 }
        #expect(source.requests == 1)
        clock.advance(by: RealLocationRefresher.interval)
        await wait { source.requests == 2 && clock.sleepingCount == 1 }
        clock.advance(by: RealLocationRefresher.interval)
        await wait { source.requests == 3 }
    }

    @Test func aSimulatedFixStopsRefreshingUntilAnExplicitRequest() async {
        let source = CountingFixSource(), clock = RouteTestClock()
        let refresher = RealLocationRefresher(source: source, clock: clock)
        refresher.sceneDidBecomeActive()
        await wait { clock.sleepingCount == 1 }

        refresher.fixReceived(simulated: true)
        #expect(refresher.deviceSimulating && !refresher.isRefreshing)
        await wait { clock.sleepingCount == 0 }
        clock.advance(by: .seconds(60))
        await settle()
        #expect(source.requests == 1)

        refresher.refreshNow()
        #expect(!refresher.deviceSimulating && refresher.isRefreshing)
        await wait { source.requests == 2 }
    }

    @Test func aRealFixResumesRefreshingInAnActiveScene() async {
        let source = CountingFixSource(), clock = RouteTestClock()
        let refresher = RealLocationRefresher(source: source, clock: clock)
        refresher.sceneDidBecomeActive()
        await wait { source.requests == 1 }
        refresher.fixReceived(simulated: true)

        refresher.fixReceived(simulated: false)
        #expect(refresher.isRefreshing)
        await wait { source.requests == 2 }
        refresher.fixReceived(simulated: false)
        await settle()
        #expect(source.requests == 2, "A running refresh is not restarted by each fix")
    }

    @Test func anInactiveSceneStopsRefreshingButStillAnswersExplicitRequestsOnce() async {
        let source = CountingFixSource(), clock = RouteTestClock()
        let refresher = RealLocationRefresher(source: source, clock: clock)
        refresher.sceneDidBecomeActive()
        await wait { clock.sleepingCount == 1 }

        refresher.sceneDidBecomeInactive()
        #expect(!refresher.isRefreshing)
        refresher.fixReceived(simulated: false)
        #expect(!refresher.isRefreshing)

        refresher.refreshNow()
        #expect(source.requests == 2 && !refresher.isRefreshing)
        clock.advance(by: .seconds(60))
        await settle()
        #expect(source.requests == 2)
    }

    @Test func releasingTheRefresherEndsItsLoop() async {
        let source = CountingFixSource(), clock = RouteTestClock()
        var refresher: RealLocationRefresher? = RealLocationRefresher(source: source, clock: clock)
        refresher?.sceneDidBecomeActive()
        await wait { clock.sleepingCount == 1 }
        refresher = nil
        await wait { clock.sleepingCount == 0 }
        clock.advance(by: .seconds(60))
        await settle()
        #expect(source.requests == 1)
    }

    private func settle() async { for _ in 0..<20 { await Task.yield() } }
    private func wait(_ condition: @MainActor () -> Bool) async {
        let deadline = ContinuousClock.now + .seconds(2)
        while !condition() && ContinuousClock.now < deadline { await Task.yield() }
        #expect(condition())
    }
}

@MainActor
private final class CountingFixSource: RealLocationFixRequesting {
    private(set) var requests = 0
    func requestFix() { requests += 1 }
}
