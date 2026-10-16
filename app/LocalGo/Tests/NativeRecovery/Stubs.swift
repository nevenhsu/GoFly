import Foundation

protocol LocationEngine: Sendable {
    func set(latitude: Double, longitude: Double) throws
    func clear() throws
}

enum NativeTestFailure: Error { case disconnected }

enum NativeTestState {
    static var reachable = true
    static var epoch = 0
    static var actualIdentity = "test-device"
    static var identityXML: String?
    static var freshOpens = 0
    static var clientsFreed = 0
    static var errorsFreed = 0
    static var xmlFreed = 0
    static var tunnelsFreed = 0
    static var clearCalls = 0
    static var setCalls = 0
    static var failClient = false
    static var partialClient = false
    static var missingClient = false
    static var xmlReadFails = false
    static var recordValid = true

    static func reset() {
        reachable = true
        epoch += 1
        actualIdentity = "test-device"
        identityXML = nil
        freshOpens = 0
        clientsFreed = 0
        errorsFreed = 0
        xmlFreed = 0
        tunnelsFreed = 0
        clearCalls = 0
        setCalls = 0
        failClient = false
        partialClient = false
        missingClient = false
        xmlReadFails = false
        recordValid = true
    }
}

enum PairingFileStore {
    static var expectedDeviceUDID: String? { "test-device" }
    static func prepareURL() -> URL { URL(fileURLWithPath: "/fake-pairing") }
    static func verifyStoredRecord(expectedDeviceUDID: String) -> Bool { NativeTestState.recordValid }
}

final class JITEnableContext {
    static let shared = JITEnableContext()
    static func makeIsolatedContext() -> JITEnableContext { JITEnableContext() }
    private var connectedEpoch: Int?
    var adapterHandle: OpaquePointer? { connectedEpoch.map { OpaquePointer(bitPattern: $0 + 1)! } }
    var handshakeHandle: OpaquePointer? { adapterHandle }

    func ensureTunnel() throws {
        if connectedEpoch == nil { try startTunnel() }
    }

    func startTunnel() throws {
        NativeTestState.freshOpens += 1
        guard NativeTestState.reachable else { throw NativeTestFailure.disconnected }
        if connectedEpoch != nil { NativeTestState.tunnelsFreed += 1 }
        connectedEpoch = NativeTestState.epoch
    }

    func ideviceInfoInit() throws -> OpaquePointer {
        guard connectedEpoch == NativeTestState.epoch, NativeTestState.reachable else {
            throw NativeTestFailure.disconnected
        }
        return OpaquePointer(bitPattern: 3)!
    }

    func withFreshTunnel<T>(hostname: String, _ body: (OpaquePointer, OpaquePointer) throws -> T) throws -> T {
        NativeTestState.freshOpens += 1
        guard NativeTestState.reachable else { throw NativeTestFailure.disconnected }
        defer { NativeTestState.tunnelsFreed += 1 }
        return try body(OpaquePointer(bitPattern: 1)!, OpaquePointer(bitPattern: 2)!)
    }

    func ideviceInfoGetXML(withLockdownClient: OpaquePointer?) throws -> UnsafeMutablePointer<CChar>? {
        if NativeTestState.xmlReadFails { throw NativeTestFailure.disconnected }
        let xml = NativeTestState.identityXML ?? """
        <?xml version="1.0" encoding="UTF-8"?>
        <plist version="1.0"><dict><key>UniqueDeviceID</key><string>\(NativeTestState.actualIdentity)</string></dict></plist>
        """
        return strdup(xml)
    }
}

func lockdownd_connect_rsd(_ adapter: OpaquePointer?, _ handshake: OpaquePointer?, _ client: UnsafeMutablePointer<OpaquePointer?>) -> OpaquePointer? {
    guard NativeTestState.reachable,
          adapter == OpaquePointer(bitPattern: NativeTestState.epoch + 1) else {
        return OpaquePointer(bitPattern: 4)!
    }
    if NativeTestState.failClient {
        if NativeTestState.partialClient { client.pointee = OpaquePointer(bitPattern: 3)! }
        return OpaquePointer(bitPattern: 4)!
    }
    if NativeTestState.missingClient { return nil }
    client.pointee = OpaquePointer(bitPattern: 3)!
    return nil
}

func idevice_error_free(_ error: OpaquePointer) { NativeTestState.errorsFreed += 1 }
func lockdownd_client_free(_ client: OpaquePointer) { NativeTestState.clientsFreed += 1 }
func plist_mem_free(_ xml: UnsafeMutablePointer<CChar>) {
    NativeTestState.xmlFreed += 1
    free(xml)
}

enum DeveloperDiskImageService {
    static let filesAreReady = true
    static let directoryURL = URL(fileURLWithPath: "/fake-ddi")
}
enum TestMountStatus { case mounted }
func checkMountStatus() -> TestMountStatus { .mounted }
func mountDeveloperDiskImage(from path: String) -> Bool { true }
enum DeviceConnectionContext { static let targetIPAddress = "10.7.0.1" }

func simulate_location(_ ip: String, _ latitude: Double, _ longitude: Double, _ pairing: String) -> Int32 {
    NativeTestState.setCalls += 1
    return 0
}

func clear_paired_simulated_location(_ ip: String, _ pairing: String) -> Int32 {
    NativeTestState.clearCalls += 1
    return 0
}
