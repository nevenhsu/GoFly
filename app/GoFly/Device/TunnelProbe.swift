import Foundation
import GoFlyCore

#if !targetEnvironment(simulator)
import Darwin

/// A fresh TCP probe for the fixed LocalDevVPN endpoint.
enum TunnelProbe {
    static func run() throws {
        let descriptor = socket(AF_INET, SOCK_STREAM, 0)
        guard descriptor >= 0 else { throw DeviceServiceFailure.tunnelUnavailable }
        defer { Darwin.close(descriptor) }
        guard fcntl(descriptor, F_SETFL, O_NONBLOCK) != -1 else {
            throw DeviceServiceFailure.tunnelUnavailable
        }
        var address = localTunnelAddress()
        let result = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.stride))
            }
        }
        if result == 0 { return }
        guard errno == EINPROGRESS else { throw DeviceServiceFailure.tunnelUnavailable }
        var pollDescriptor = pollfd(fd: descriptor, events: Int16(POLLOUT), revents: 0)
        let ready = poll(&pollDescriptor, 1, 3_000)
        guard ready > 0 else {
            throw ready == 0 ? DeviceServiceFailure.operationTimedOut : .tunnelUnavailable
        }
        var socketError: Int32 = 0
        var length = socklen_t(MemoryLayout<Int32>.size)
        guard getsockopt(descriptor, SOL_SOCKET, SO_ERROR, &socketError, &length) == 0,
              socketError == 0 else { throw DeviceServiceFailure.tunnelUnavailable }
    }
}

func localTunnelAddress() -> sockaddr_in {
    var address = sockaddr_in()
    address.sin_len = UInt8(MemoryLayout<sockaddr_in>.stride)
    address.sin_family = sa_family_t(AF_INET)
    address.sin_port = in_port_t(49152).bigEndian
    // The transport is a fixed LocalDevVPN endpoint, never user/defaults input.
    _ = "10.7.0.1".withCString { inet_pton(AF_INET, $0, &address.sin_addr) }
    return address
}

#endif
