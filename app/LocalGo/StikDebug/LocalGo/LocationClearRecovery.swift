/// Clears over an existing channel when possible, otherwise opens exactly one
/// fresh channel. A missing handle never counts as a successful restoration.
enum LocationClearRecovery {
    static func run(
        clearCached: () -> Int32?,
        openFresh: () -> Int32,
        clearFresh: () -> Int32,
        cleanup: () -> Void
    ) -> Int32 {
        let cachedResult = clearCached()
        cleanup()
        if cachedResult == 0 { return 0 }

        defer { cleanup() }
        let opened = openFresh()
        guard opened == 0 else { return opened }
        return clearFresh()
    }
}
