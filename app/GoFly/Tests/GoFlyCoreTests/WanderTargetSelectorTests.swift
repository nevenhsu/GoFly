import Foundation
import Testing
@testable import GoFlyCore

struct WanderTargetSelectorTests {
    @Test func selectsACompleteNewTargetOnTheTenMinuteSpeedRing() throws {
        let origin = GeoCoordinate(latitude: 0, longitude: 0)!
        let selected = try #require(WanderTargetSelector.select(origin: origin, speed: .standard,
            currentTarget: nil, history: [], bearingSamples: [.nan, .infinity, 0]))
        #expect(abs(selected.coordinate.latitude - 0.029977386863957686) < 1e-12)
        #expect(abs(selected.coordinate.longitude) < 1e-12)
        #expect(selected.place.id == .coordinate(selected.coordinate))
        #expect(selected.place.title == selected.coordinate.displayText)
        let independentPath = try PlannedRoute(points: [origin, selected.coordinate], from: origin, to: selected.coordinate)
        #expect(abs(independentPath.totalDistanceMeters - 3333.3333333333335) < 1e-7)
        let next = try #require(WanderTargetSelector.select(origin: origin, speed: .standard,
            currentTarget: nil, history: [], bearingSamples: [0]))
        #expect(next.coordinate == selected.coordinate && next.id != selected.id)
    }
    @Test func selectionIsBoundedToThirtyTwoDrawsAndSkipsInvalidOrExcludedCandidates() throws {
        let origin = GeoCoordinate(latitude: 0, longitude: 0)!
        let north = try #require(WanderTargetSelector.select(origin: origin, speed: .standard,
            currentTarget: nil, history: [], bearingSamples: [0]))
        #expect(WanderTargetSelector.select(origin: origin, speed: .standard, currentTarget: north,
            history: [], bearingSamples: Array(repeating: 0, count: 32) + [90]) == nil)
        let east = try #require(WanderTargetSelector.select(origin: origin, speed: .standard,
            currentTarget: north, history: [], bearingSamples: [.nan, -.infinity, 0, 450]))
        #expect(abs(east.coordinate.latitude) < 1e-12)
        #expect(east.coordinate.longitude > 0)
        #expect(WanderTargetSelector.select(origin: origin, speed: .standard, currentTarget: nil,
            history: [], bearingSamples: []) == nil)
    }

    @Test func historyUsesOnlyTheLatestHundredCommitsAndExcludesTheOneMeterNeighborhood() throws {
        let origin = GeoCoordinate(latitude: 0, longitude: 0)!
        let north = try #require(WanderTargetSelector.select(origin: origin, speed: .standard,
            currentTarget: nil, history: [], bearingSamples: [0]))
        #expect(WanderTargetSelector.select(origin: origin, speed: .standard, currentTarget: nil,
            history: [north.coordinate] + Array(repeating: origin, count: 99), bearingSamples: [0]) == nil)
        #expect(WanderTargetSelector.select(origin: origin, speed: .standard, currentTarget: nil,
            history: [north.coordinate] + Array(repeating: origin, count: 100), bearingSamples: [0]) != nil)
        let near = JoystickGeodesy.destination(from: north.coordinate,
            displacement: JoystickDisplacement(bearingDegrees: 0, distanceMeters: 0.99)!)
        let outside = JoystickGeodesy.destination(from: north.coordinate,
            displacement: JoystickDisplacement(bearingDegrees: 0, distanceMeters: 1.01)!)
        #expect(WanderTargetSelector.select(origin: origin, speed: .standard, currentTarget: nil,
            history: [near], bearingSamples: [0]) == nil)
        #expect(WanderTargetSelector.select(origin: origin, speed: .standard, currentTarget: nil,
            history: [outside], bearingSamples: [0])?.coordinate == north.coordinate)
    }

    @Test func ringsRemainValidAtSpeedExtremesPolesAndTheDateline() throws {
        for origin in [GeoCoordinate(latitude: 90, longitude: 42)!, GeoCoordinate(latitude: -90, longitude: -180)!, GeoCoordinate(latitude: 0, longitude: 179.999)!] {
            for speed in [RouteSpeed(kilometersPerHour: 2)!, RouteSpeed(kilometersPerHour: 100)!] {
                let target = try #require(WanderTargetSelector.select(origin: origin, speed: speed,
                    currentTarget: nil, history: [], bearingSamples: [90]))
                #expect((-180..<180).contains(target.coordinate.longitude))
                let independent = try PlannedRoute(points: [origin, target.coordinate], from: origin, to: target.coordinate)
                let expected = speed.kilometersPerHour == 2 ? 333.3333333333333 : 16666.666666666668
                #expect(abs(independent.totalDistanceMeters - expected) < 1e-6)
            }
        }
    }
}
