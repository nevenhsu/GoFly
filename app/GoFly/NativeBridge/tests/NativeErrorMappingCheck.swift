import GoFlyCore

@main struct NativeErrorMappingCheck {
    static func main() {
        precondition(NativeErrorMapping.failure(code: 103, subcode: 5, fallback: .tunnelUnavailable) == .pairingRequired)
        precondition(NativeErrorMapping.failure(code: 103, subcode: 4, fallback: .tunnelUnavailable) == .tunnelUnavailable)
        precondition(NativeErrorMapping.failure(code: 109, subcode: 0, fallback: .serviceUnavailable) == .operationTimedOut)
        precondition(NativeErrorMapping.failure(code: 1, subcode: 5, fallback: .serviceUnavailable) == .serviceUnavailable)
        precondition(NativeErrorMapping.failure(code: 13, subcode: 0, fallback: .devicePreparationRequired) == .devicePreparationRequired)
        precondition(NativeErrorMapping.failure(code: 24, subcode: 0, fallback: .devicePreparationRequired) == .developerModeRequired)
        precondition(NativeErrorMapping.failure(code: 24, subcode: 1, fallback: .devicePreparationRequired) == .devicePreparationRequired)
        precondition(NativeErrorMapping.isNotMounted(code: 20, subcode: 99))
        precondition(!NativeErrorMapping.isNotMounted(code: 24, subcode: 0))
        print("PASS: exact native error mapper preserves pairing, timeout, developer mode, not-mounted and operation-specific failures")
    }
}
