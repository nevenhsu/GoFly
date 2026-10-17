import Foundation

public enum TunnelResetState: Equatable, Sendable {
    case idle
    case running(id: UUID)
    case succeeded(id: UUID)
    case failed(id: UUID, failure: DeviceServiceFailure)
}
