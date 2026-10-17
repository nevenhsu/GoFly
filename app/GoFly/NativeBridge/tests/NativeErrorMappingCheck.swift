import GoFlyCore

@main struct NativeErrorMappingCheck {
    static func main() {
        precondition(NativeErrorMapping.failure(code: 103, subcode: 5, fallback: .tunnelUnavailable) == .pairingRequired)
        precondition(NativeErrorMapping.failure(code: 103, subcode: 4, fallback: .tunnelUnavailable) == .tunnelUnavailable)
        precondition(NativeErrorMapping.failure(code: 109, subcode: 0, fallback: .serviceUnavailable) == .operationTimedOut)
        precondition(NativeErrorMapping.failure(code: 1, subcode: 5, fallback: .serviceUnavailable) == .serviceUnavailable)
        precondition(NativeErrorMapping.failure(code: 13, subcode: 0, fallback: .devicePreparationRequired) == .devicePreparationRequired)
        print("PASS: exact native error mapper preserves pairing, timeout and operation-specific failures")
    }
}
