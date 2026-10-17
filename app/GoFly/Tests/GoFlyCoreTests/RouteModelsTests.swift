import Foundation
import Testing
@testable import GoFlyCore

struct RouteModelsTests {
    @Test func nearbyRoadEndpointsArePreservedBetweenExactRequestedAnchors() throws {
        let from = GeoCoordinate(latitude: 0, longitude: 0)!, to = GeoCoordinate(latitude: 0, longitude: 0.001)!
        let road = [GeoCoordinate(latitude: 0, longitude: 0.0001)!,
                    GeoCoordinate(latitude: 0.0001, longitude: 0.0005)!,
                    GeoCoordinate(latitude: 0, longitude: 0.0009)!]
        let route = try PlannedRoute(points: [road[0]] + road + [road[2]], from: from, to: to)
        #expect(route.points == [from] + road + [to])
        #expect(route.coordinate(at: 0) == from)
        #expect(route.coordinate(at: route.totalDistanceMeters) == to)
    }

    @Test(arguments: [false, true])
    func eitherRemoteRoadEndpointRejectsTheWholeRoute(remoteStart: Bool) throws {
        let from = GeoCoordinate(latitude: 0, longitude: 0)!, to = GeoCoordinate(latitude: 0, longitude: 0.001)!
        let road = remoteStart ? [GeoCoordinate(latitude: 1, longitude: 0)!, to]
                               : [from, GeoCoordinate(latitude: 1, longitude: 0.001)!]
        #expect(throws: RouteExecutionFailure.invalidPath) { try PlannedRoute(points: road, from: from, to: to) }
    }

    @Test func theSnapLimitUsesUnroundedSphericalMeters() throws {
        let from = GeoCoordinate(latitude: 0, longitude: 0)!, to = GeoCoordinate(latitude: 0, longitude: 0.01)!
        func offset(_ meters: Double) -> GeoCoordinate { GeoCoordinate(latitude: 0, longitude: meters / 6_371_000 * 180 / .pi)! }
        let inside = offset(49.999999), outside = offset(50.000001)
        #expect(try PlannedRoute(points: [inside, to], from: from, to: to).points == [from, inside, to])
        #expect(throws: RouteExecutionFailure.invalidPath) { try PlannedRoute(points: [outside, to], from: from, to: to) }
        let insideEnd = GeoCoordinate(latitude: 0, longitude: to.longitude - inside.longitude)!
        let outsideEnd = GeoCoordinate(latitude: 0, longitude: to.longitude - outside.longitude)!
        #expect(try PlannedRoute(points: [from, insideEnd], from: from, to: to).points == [from, insideEnd, to])
        #expect(throws: RouteExecutionFailure.invalidPath) { try PlannedRoute(points: [from, outsideEnd], from: from, to: to) }
    }

    @Test func snapValidationUsesShortDatelineDistanceAndPoleAliases() throws {
        let from = GeoCoordinate(latitude: 0, longitude: -180)!, to = GeoCoordinate(latitude: 0, longitude: -179.999)!
        let road = [GeoCoordinate(latitude: 0, longitude: 179.9999)!, GeoCoordinate(latitude: 0, longitude: -179.9991)!]
        #expect(try PlannedRoute(points: road, from: from, to: to).points == [from] + road + [to])
        for latitude in [-90.0, 90.0] {
            let pole = GeoCoordinate(latitude: latitude, longitude: 0)!
            let alias = GeoCoordinate(latitude: latitude, longitude: 90)!
            let end = GeoCoordinate(latitude: latitude * 0.99999, longitude: 90)!
            #expect(try PlannedRoute(points: [alias, end], from: pole, to: end).points == [pole, alias, end])
        }
    }

    @Test func theFinalPointCapIncludesBothExactAnchors() throws {
        let from = GeoCoordinate(latitude: 0, longitude: 0)!
        for count in [9_998, 9_999, 10_000] {
            let road = (1...count).map { GeoCoordinate(latitude: 0, longitude: Double($0) * 0.0000001)! }
            let to = GeoCoordinate(latitude: 0, longitude: Double(count + 1) * 0.0000001)!
            if count == 9_998 {
                #expect(try PlannedRoute(points: road, from: from, to: to).points.count == 10_000)
            } else {
                #expect(throws: RouteExecutionFailure.invalidPath) { try PlannedRoute(points: road, from: from, to: to) }
            }
        }
    }

    @Test func routeSpeedAndDraftKeepValidatedValuesAndStableNodeIdentity() throws {
        let draft = RouteDraft()
        #expect(draft.nodes.count == 2)
        #expect(draft.start.id != draft.destination.id)
        #expect(draft.start.value == .current)
        #expect(draft.destination.value == nil)
        #expect(draft.speed.kilometersPerHour == 20)
        #expect(RouteSpeed(kilometersPerHour: 1) == nil)
        #expect(RouteSpeed(kilometersPerHour: 101) == nil)
        #expect(RouteSpeed(kilometersPerHour: 36)?.metersPerSecond == 10)
    }

    @Test func plannedGeometryAnchorsExactEndpointsAndInterpolatesSphericalDistance() throws {
        let start = GeoCoordinate(latitude: 0, longitude: 0)!
        let end = GeoCoordinate(latitude: 0, longitude: 1)!
        let route = try PlannedRoute(points: [start, start, end], from: start, to: end)
        #expect(route.points == [start, end])
        #expect(abs(route.totalDistanceMeters - 111_194.92664455874) < 0.001)
        #expect(route.coordinate(at: 0) == start)
        #expect(route.coordinate(at: route.totalDistanceMeters) == end)
        #expect(abs(try #require(route.coordinate(at: route.totalDistanceMeters / 2)).longitude - 0.5) < 0.000001)
        #expect(route.coordinate(at: .nan) == nil)
        #expect(throws: RouteExecutionFailure.self) { try PlannedRoute(points: [start], from: start, to: end) }
        #expect(throws: RouteExecutionFailure.self) { try PlannedRoute(points: [start, start], from: start, to: end) }
    }
    @Test func geographicAliasesAreZeroLengthAndAntimeridianInterpolationUsesTheShortArc() throws {
        for (start, end) in [(GeoCoordinate(latitude: 90, longitude: 0)!, GeoCoordinate(latitude: 90, longitude: 90)!),
                             (GeoCoordinate(latitude: 0, longitude: 180)!, GeoCoordinate(latitude: 0, longitude: -180)!)] {
            #expect(throws: RouteExecutionFailure.self) { try PlannedRoute(points: [start, end], from: start, to: end) }
        }
        let start = GeoCoordinate(latitude: 0, longitude: 179.9)!, end = GeoCoordinate(latitude: 0, longitude: -179.9)!
        let route = try PlannedRoute(points: [start, end], from: start, to: end)
        #expect(abs(route.totalDistanceMeters - 22_238.98532891) < 0.001)
        #expect(abs(abs(try #require(route.coordinate(at: route.totalDistanceMeters / 2)).longitude) - 180) < 0.000001)
        #expect(throws: RouteExecutionFailure.self) { try PlannedRoute(points: Array(repeating: start, count: 10_001), from: start, to: end) }
    }
}
