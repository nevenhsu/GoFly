import Foundation

/// An opaque, owner-bound admission capability for a live transfer cutline.
///
/// The initializer and identity accessors intentionally remain package
/// internal.  A caller can only obtain a value from the owner that created it
/// and cannot manufacture a value that passes another owner's release check.
public struct TransferHold: Equatable, Sendable {
    let ownerID: UUID
    let tokenID: UUID

    init(ownerID: UUID, tokenID: UUID) {
        self.ownerID = ownerID
        self.tokenID = tokenID
    }
}
