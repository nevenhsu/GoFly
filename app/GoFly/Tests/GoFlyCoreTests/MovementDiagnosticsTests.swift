import Foundation
import Testing
@testable import GoFlyCore

/// Proves the movement diagnostics actually record the evidence stage B needs:
/// a failed tick, its failure category, and the controller's phase transition.
@Suite @MainActor
struct MovementDiagnosticsTests {
    @Test func failedRouteTickRecordsNotSentWithFailureAndPhaseTransition() async throws {
        let device = RouteControlledDevice()
        let service = ServiceController(service: device)
        let sink = CapturingSink()
        Diagnostics.shared.attach(sink)
        defer { Diagnostics.shared.detach(sink) }
        let intent = try await begin(service, device)

        let revision = try #require(service.routeControlRevision(executionID: intent.id, lease: intent.lease))
        let tick = Task {
            await service.sendRoutePoint(executionID: intent.id, lease: intent.lease, sequence: 1,
                expectedControlRevision: revision, coordinate: intent.route.end)
        }
        await wait { await device.waiting }
        // A failure value no other test uses keeps the shared-singleton records
        // unambiguous while suites run in parallel.
        await device.finish(.notSent(.developerModeRequired))
        #expect(await tick.value == .notSent(.developerModeRequired))
        Diagnostics.shared.flush()

        let names = sink.records.map(\.event.name)
        #expect(names.contains("route.tick"))
        #expect(names.contains("route.interrupted"))

        let tickRecord = try #require(sink.records.last {
            $0.event.name == "route.tick"
                && $0.event.fields["failure"] == .text(DeviceServiceFailure.developerModeRequired.rawValue)
        })
        #expect(tickRecord.event.level == .notice)
        #expect(tickRecord.event.fields["result"] == .text("notSent"))
        #expect(tickRecord.event.fields["seq"] == .count(1))
        #expect(tickRecord.event.fields["op"] == .text("route"))
        #expect(tickRecord.event.fields["dispatched"] == .flag(false))
    }

    @Test func watchdogTimeoutRecordsTheTimeoutAndRepairPhase() async throws {
        let device = RouteControlledDevice()
        let watchdog = ManualServiceWatchdog()
        let service = ServiceController(service: device, operationTimeout: .seconds(17),
                                       watchdogSleep: watchdog.sleep)
        let sink = CapturingSink()
        Diagnostics.shared.attach(sink)
        defer { Diagnostics.shared.detach(sink) }
        let intent = try await begin(service, device, watchdog: watchdog)

        let revision = try #require(service.routeControlRevision(executionID: intent.id, lease: intent.lease))
        let tick = Task {
            await service.sendRoutePoint(executionID: intent.id, lease: intent.lease, sequence: 1,
                expectedControlRevision: revision, coordinate: intent.route.end)
        }
        await wait { await device.waiting }
        await wait { watchdog.requests.count == 2 }
        watchdog.fireLatest()
        await wait { service.error == .operationTimedOut }
        await device.finish(.acknowledged)
        _ = await tick.value
        Diagnostics.shared.flush()

        let record = try #require(sink.records.last {
            $0.event.name == "watchdog.fired" && $0.event.fields["timeout_s"] == .number(17, digits: 0)
        })
        #expect(record.event.level == .error)
        #expect(record.event.fields["op"] == .text("route.tick"))
        #expect(record.event.fields["seq"] == .count(1))
        #expect(record.event.fields["dispatched"] == .flag(false))
    }

    private func begin(_ service: ServiceController, _ device: RouteControlledDevice,
                       watchdog: ManualServiceWatchdog? = nil) async throws -> RouteExecutionIntent {
        let from = GeoCoordinate(latitude: 25, longitude: 121)!
        let to = GeoCoordinate(latitude: 25.01, longitude: 121)!
        let draft = RouteDraft(values: [.place(place(from)), .place(place(to))])!
        let intent = RouteExecutionIntent(draft: draft,
                                          route: try PlannedRoute(points: [from, to], from: from, to: to))
        let begun = Task { await service.beginRoute(intent, expectedAdmissionRevision: service.routeAdmissionRevision) }
        await wait { await device.waiting }
        if let watchdog { await wait { watchdog.requests.count == 1 } }
        await device.finish(.acknowledged)
        #expect(await begun.value == .acknowledged)
        return intent
    }

    private func place(_ coordinate: GeoCoordinate) -> MapPlace {
        MapPlace(id: .coordinate(coordinate), title: coordinate.displayText, coordinate: coordinate)
    }

    private func wait(_ condition: @MainActor () async -> Bool) async {
        let deadline = ContinuousClock.now + .seconds(2)
        while !(await condition()) && ContinuousClock.now < deadline { await Task.yield() }
        #expect(await condition())
    }
}
