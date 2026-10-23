import Foundation
import Testing
@testable import GoFlyCore

@Suite
struct FallbackRoutePlannerTests {
    private let start = GeoCoordinate(latitude: 25, longitude: 121)!
    private let end = GeoCoordinate(latitude: 25.001, longitude: 121.001)!

    @Test func triesModesInOrderAndStopsAtFirstUsablePath() async throws {
        let walkingPath = [start, GeoCoordinate(latitude: 25.0005, longitude: 121.0005)!, end]
        let provider = RecordingPathProvider(responses: [
            .automobile: .failure(.unavailable),
            .walking: .success(walkingPath),
            .transit: .failure(.unavailable)
        ])
        let planner = FallbackRoutePlanner(provider: provider)

        let result = try await planner.plan(from: start, to: end)

        #expect(result == walkingPath)
        let calls = await provider.calls
        #expect(calls == [.automobile, .walking])
    }

    @Test func reportsPlanningFailureAfterAllModesFail() async throws {
        let provider = RecordingPathProvider(responses: [
            .automobile: .failure(.unavailable),
            .walking: .failure(.unavailable),
            .transit: .failure(.unavailable)
        ])
        let planner = FallbackRoutePlanner(provider: provider)

        await #expect(throws: RouteExecutionFailure.planningFailed) {
            try await planner.plan(from: start, to: end)
        }
        let calls = await provider.calls
        #expect(calls == [.automobile, .walking, .transit])
    }

    @Test func cancellationDoesNotTryAnotherTransport() async throws {
        let provider = RecordingPathProvider(responses: [
            .automobile: .failure(.cancelled),
            .walking: .success([start, end]),
            .transit: .success([start, end])
        ])
        let planner = FallbackRoutePlanner(provider: provider)

        await #expect(throws: CancellationError.self) {
            try await planner.plan(from: start, to: end)
        }
        let calls = await provider.calls
        #expect(calls == [.automobile])
    }
}

private enum RecordingProviderError: Error, Sendable {
    case unavailable
    case cancelled
}

private actor RecordingPathProvider: RoutePathProviding {
    private var responses: [RouteTransport: Result<[GeoCoordinate], RecordingProviderError>]
    private(set) var calls: [RouteTransport] = []

    init(responses: [RouteTransport: Result<[GeoCoordinate], RecordingProviderError>]) {
        self.responses = responses
    }

    func path(from: GeoCoordinate, to: GeoCoordinate,
              transport: RouteTransport) async throws -> [GeoCoordinate] {
        calls.append(transport)
        guard let response = responses[transport] else { throw RecordingProviderError.unavailable }
        switch response {
        case .success(let path): return path
        case .failure(.unavailable): throw RecordingProviderError.unavailable
        case .failure(.cancelled): throw CancellationError()
        }
    }
}
