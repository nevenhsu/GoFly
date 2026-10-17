import Foundation
import GoFlyCore

#if !targetEnvironment(simulator)
import Darwin
import idevice

// Tunnel, personalized/cryptex mounting and location-channel ownership logic
// adapted from StikDebug (AGPL-3.0), JITEnableContext.swift and
// IdeviceFFIBridge.swift. See the production target's license/provenance files.
// This class does not import their global contexts, caches or command queues.
final class NativeDeviceSession: DeviceSession {
    private var adapter: OpaquePointer?
    private var handshake: OpaquePointer?
    private var remoteServer: OpaquePointer?
    private var location: OpaquePointer?

    init(pairingURL: URL) throws {
        var pairing: OpaquePointer?
        defer { if let pairing { rp_pairing_file_free(pairing) } }
        do {
            try throwIfFFIError(pairingURL.path.withCString { rp_pairing_file_read($0, &pairing) }, .pairingRequired)
            guard let pairing else { throw DeviceServiceFailure.pairingRequired }
            var address = localTunnelAddress()
            try throwIfFFIError(withUnsafePointer(to: &address) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    tunnel_create_rppairing_verify_only(
                        $0, socklen_t(MemoryLayout<sockaddr_in>.stride),
                        "GoFlyService", pairing, &adapter, &handshake
                    )
                }
            }, .tunnelUnavailable)
            guard adapter != nil, handshake != nil else { throw DeviceServiceFailure.tunnelUnavailable }
        } catch {
            close()
            throw error
        }
    }

    func close() {
        if let location { location_simulation_free(location); self.location = nil }
        if let remoteServer { remote_server_free(remoteServer); self.remoteServer = nil }
        if let handshake { rsd_handshake_free(handshake); self.handshake = nil }
        if let adapter { adapter_free(adapter); self.adapter = nil }
    }

    func deviceIdentifier() throws -> String { try stringValue("UniqueDeviceID") }

    func isSupportPrepared() throws -> Bool {
        if try mountMethod() == .cryptex {
            var installed: UnsafeMutablePointer<InstalledCryptexC>?
            defer { cryptexd_free_installed_cryptex(installed) }
            try throwIfFFIError(cryptexd_installed_ddi(adapter, handshake, &installed), .devicePreparationRequired)
            return installed != nil
        }
        return try withImageMounter { client in
            var signature: UnsafeMutablePointer<UInt8>?
            var count = 0
            defer { if let signature { idevice_data_free(signature, UInt(count)) } }
            if let error = image_mounter_lookup_image(client, "Personalized", &signature, &count) {
                // Native library's NotFound (20) is the sole absent-image case.
                // Transport/protocol failures cannot trigger a blind mount.
                let code = error.pointee.code
                idevice_error_free(error)
                if code == 20 { return false }
                throw code == 109 ? DeviceServiceFailure.operationTimedOut : .devicePreparationRequired
            }
            return signature != nil && count > 0
        }
    }

    func mountProvisionedSupport() throws {
        let method = try mountMethod()
        let support = try ProvisionedSupport(method: method)
        if method == .cryptex {
            var assets: OpaquePointer?
            defer { if let assets { cryptex1_assets_free(assets) } }
            try throwIfFFIError(support.directory.path.withCString { cryptex1_assets_load($0, &assets) }, .devicePreparationRequired)
            guard let assets else { throw DeviceServiceFailure.devicePreparationRequired }
            // Explicit user preparation may invoke native Apple signing. The
            // app itself only reads support already provisioned by the Mac.
            try throwIfFFIError(cryptexd_install_ddi(adapter, handshake, assets, nil), .devicePreparationRequired)
        } else {
            let image = try support.data("Image.dmg")
            let trustcache = try support.data("Image.dmg.trustcache")
            let manifest = try support.data("BuildManifest.plist")
            let chipID = try unsignedValue("UniqueChipID")
            try withImageMounter { client in
                try throwIfFFIError(image.withUnsafeBytes { imageBytes in
                    trustcache.withUnsafeBytes { cacheBytes in
                        manifest.withUnsafeBytes { manifestBytes in
                            image_mounter_mount_personalized_rsd(
                                client, adapter, handshake,
                                imageBytes.bindMemory(to: UInt8.self).baseAddress, image.count,
                                cacheBytes.bindMemory(to: UInt8.self).baseAddress, trustcache.count,
                                manifestBytes.bindMemory(to: UInt8.self).baseAddress, manifest.count,
                                nil, chipID
                            )
                        }
                    }
                }, .devicePreparationRequired)
            }
        }
    }

    func validateLocationService() throws {
        if location != nil { return }
        try throwIfFFIError(remote_server_connect_rsd(adapter, handshake, &remoteServer), .serviceUnavailable)
        guard remoteServer != nil else { throw DeviceServiceFailure.serviceUnavailable }
        try throwIfFFIError(location_simulation_new(remoteServer, &location), .serviceUnavailable)
        guard location != nil else { throw DeviceServiceFailure.serviceUnavailable }
        // Opening a channel validates readiness without setting a coordinate.
    }

    func clearLocation() throws {
        try validateLocationService()
        try throwIfFFIError(location_simulation_clear(location), .serviceUnavailable)
    }

    private func mountMethod() throws -> SupportMountMethod {
        let components = try stringValue("ProductVersion").split(separator: ".")
        guard let major = components.first.flatMap({ Int($0) }),
              major >= 26 else { throw DeviceServiceFailure.devicePreparationRequired }
        let minor = components.count > 1 ? Int(components[1]) : 0
        guard let minor else { throw DeviceServiceFailure.devicePreparationRequired }
        return major > 26 || minor >= 4 ? .cryptex : .personalized
    }

    private func withLockdown<T>(_ operation: (OpaquePointer) throws -> T) throws -> T {
        var client: OpaquePointer?
        defer { if let client { lockdownd_client_free(client) } }
        try throwIfFFIError(lockdownd_connect_rsd(adapter, handshake, &client), .serviceUnavailable)
        guard let client else { throw DeviceServiceFailure.serviceUnavailable }
        return try operation(client)
    }

    private func withImageMounter<T>(_ operation: (OpaquePointer) throws -> T) throws -> T {
        var client: OpaquePointer?
        defer { if let client { image_mounter_free(client) } }
        try throwIfFFIError(image_mounter_connect_rsd(adapter, handshake, &client), .devicePreparationRequired)
        guard let client else { throw DeviceServiceFailure.devicePreparationRequired }
        return try operation(client)
    }

    private func stringValue(_ key: String) throws -> String {
        try withLockdown { client in
            var value: plist_t?
            defer { plist_free(value) }
            try throwIfFFIError(key.withCString { lockdownd_get_value(client, $0, nil, &value) }, .serviceUnavailable)
            guard let value, plist_get_node_type(value) == PLIST_STRING else {
                throw DeviceServiceFailure.serviceUnavailable
            }
            var count: UInt64 = 0
            guard let bytes = plist_get_string_ptr(value, &count), count > 0, count <= 256,
                  let result = String(bytes: UnsafeBufferPointer(start: UnsafeRawPointer(bytes).assumingMemoryBound(to: UInt8.self), count: Int(count)), encoding: .utf8) else {
                throw DeviceServiceFailure.serviceUnavailable
            }
            return result
        }
    }

    private func unsignedValue(_ key: String) throws -> UInt64 {
        try withLockdown { client in
            var value: plist_t?
            defer { plist_free(value) }
            try throwIfFFIError(key.withCString { lockdownd_get_value(client, $0, nil, &value) }, .devicePreparationRequired)
            guard let value, plist_get_node_type(value) == PLIST_INT else {
                throw DeviceServiceFailure.devicePreparationRequired
            }
            var result: UInt64 = 0
            plist_get_uint_val(value, &result)
            guard result != 0 else { throw DeviceServiceFailure.devicePreparationRequired }
            return result
        }
    }
}

private func throwIfFFIError(_ error: UnsafeMutablePointer<IdeviceFfiError>?, _ fallback: DeviceServiceFailure) throws {
    guard let error else { return }
    let failure = NativeErrorMapping.failure(
        code: error.pointee.code, subcode: error.pointee.sub_code, fallback: fallback
    )
    idevice_error_free(error)
    // Raw FFI messages can contain identifiers and paths; never retain them.
    throw failure
}

#endif
