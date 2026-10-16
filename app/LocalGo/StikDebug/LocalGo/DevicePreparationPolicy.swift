enum DevicePreparationPolicy {
    enum Failure: Error { case filesMissing, deviceNotMounted }

    /// Device status is authoritative: relaunching must not force a second
    /// installation, and an installation error can race a successful mount.
    static func ensureMounted(
        isMounted: () -> Bool,
        filesReady: () -> Bool,
        attemptMount: () -> Void
    ) throws {
        if isMounted() { return }
        guard filesReady() else { throw Failure.filesMissing }
        attemptMount()
        guard isMounted() else { throw Failure.deviceNotMounted }
    }
}
