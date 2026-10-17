import Foundation

@MainActor
public struct RoutePickerSession: Identifiable {
    public let id: UUID
    public let nodeID: RouteNodeID
    public let candidates: CandidateController
    public let allowsCurrent: Bool
    public let initialValue: RouteNodeValue?
}
