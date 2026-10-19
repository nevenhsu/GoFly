import Testing
import GoFlyCore

struct WanderTargetSelectorTests {
    @Test func selectsOneRandomTargetOnTheTenMinuteRing() throws {
        let origin = GeoCoordinate(latitude: 25, longitude: 121)!
        let target = try #require(WanderTargetSelector.select(origin: origin, speed: .standard, bearingSamples: [90]))
        let distance = JoystickGeodesy.distanceMeters(from: origin, to: target.coordinate)
        #expect(abs(distance - RouteSpeed.standard.metersPerSecond * 600) < 1)
    }

    @Test func invalidOrZeroDistanceSampleKeepsTheTargetUnavailable() {
        let origin = GeoCoordinate(latitude: 25, longitude: 121)!
        #expect(WanderTargetSelector.select(origin: origin, speed: .standard, bearingSamples: [.nan]) == nil)
    }
}
