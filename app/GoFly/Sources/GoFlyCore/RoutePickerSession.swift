import Foundation

@MainActor
public struct RoutePickerSession: Identifiable {
    public let id: UUID
    public let nodeID: RouteNodeID
    public let candidates: CandidateController
    public internal(set) var allowsCurrent: Bool
    public internal(set) var role: RouteNodeRole
    var clearRevision: UInt64?
    public var clearedPlace: Bool {
        guard let clearRevision, clearRevision == candidates.editingRevision else { return false }
        return candidates.candidate == nil && candidates.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
