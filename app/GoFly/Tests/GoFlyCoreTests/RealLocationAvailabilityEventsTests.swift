import Combine
import Foundation
import Testing
@testable import GoFlyCore

@Suite @MainActor
struct RealLocationAvailabilityEventsTests {
    @Test func onlyAFixThatMakesAnOriginAvailableAnnouncesIt() {
        let time = TestTime()
        let service = ServiceController(service: JoystickControlledDevice(), now: { time.now })
        let events = EventCounter(service)

        service.observeRealLocation(fix(at: time.now))
        #expect(events.route == 1 && events.joystick == 1)
        #expect(service.currentJoystickOrigin != nil && service.currentRouteOrigin != nil)

        time.advance(5)
        service.observeRealLocation(fix(at: time.now, latitude: 25.0001))
        #expect(events.route == 1 && events.joystick == 1, "A refresh of an available origin is silent")
    }

    @Test func aFreshFixAfterTheLastOneExpiredAnnouncesAgain() {
        let time = TestTime()
        let service = ServiceController(service: JoystickControlledDevice(), now: { time.now })
        let events = EventCounter(service)

        service.observeRealLocation(fix(at: time.now))
        time.advance(20)
        #expect(service.currentJoystickOrigin == nil, "The origin expires without any event")
        service.observeRealLocation(fix(at: time.now))
        #expect(events.route == 2 && events.joystick == 2)
    }

    @Test func aMissingOrStaleFixClearsTheLocationWithoutAnnouncing() {
        let time = TestTime()
        let service = ServiceController(service: JoystickControlledDevice(), now: { time.now })
        let events = EventCounter(service)

        service.observeRealLocation(fix(at: time.now))
        service.observeRealLocation(nil)
        #expect(service.realLocation == nil)
        service.observeRealLocation(fix(at: time.now.addingTimeInterval(-30)))
        #expect(service.realLocation == nil)
        #expect(events.route == 1 && events.joystick == 1)
    }

    private func fix(at date: Date, latitude: Double = 25) -> RealLocationObservation {
        RealLocationObservation(latitude: latitude, longitude: 121, horizontalAccuracy: 50, observedAt: date)!
    }
}

private final class TestTime: @unchecked Sendable {
    private let lock = NSLock()
    private var current = Date(timeIntervalSince1970: 1_800_000_000)
    var now: Date { lock.withLock { current } }
    func advance(_ seconds: TimeInterval) { lock.withLock { current += seconds } }
}

@MainActor
private final class EventCounter {
    private(set) var route = 0
    private(set) var joystick = 0
    private var subscriptions: [AnyCancellable] = []
    init(_ service: ServiceController) {
        subscriptions.append(service.routeEvents.sink { [unowned self] event in
            if case .availabilityChanged = event { route += 1 }
        })
        subscriptions.append(service.joystickEvents.sink { [unowned self] event in
            if case .availabilityChanged = event { joystick += 1 }
        })
    }
}
