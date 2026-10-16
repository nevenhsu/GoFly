import Foundation

var failures = 0
func check(_ condition: @autoclosure () -> Bool, _ name: String) {
    if !condition() { failures += 1; print("FAIL: \(name)") }
}

func scenario(_ name: String, _ body: () throws -> Void) {
    if CommandLine.arguments.last == "--list" { print(name); return }
    guard CommandLine.arguments.last == name else { return }
    NativeTestState.reset()
    do { try body() }
    catch { failures += 1; print("FAIL: \(name) threw") }
}

scenario("stop and restart after lock/unlock") {
    let engine = LiveLocationEngine()
    try engine.prepareDevice()
    try engine.set(latitude: 25, longitude: 121)
    // A lock/network transition kills the old process-owned tunnel while a
    // new connection is available through the reconnected VPN.
    NativeTestState.epoch += 1
    try engine.clear()
    check(NativeTestState.clearCalls == 1, "stop reaches native clear after stale identity tunnel")
    try engine.prepareDevice()
    try engine.set(latitude: 26, longitude: 122)
    check(NativeTestState.setCalls == 2, "restart can set again")
    check(NativeTestState.freshOpens == 2, "healthy verification reuses identity tunnel; stale tunnel rebuilds once")
    check(NativeTestState.clientsFreed == 5, "each verification releases its client")
    check(NativeTestState.xmlFreed == 5, "each verification releases its XML")
    check(NativeTestState.tunnelsFreed == 1, "stale owned tunnel released on replacement")
}

scenario("VPN returns after failed stop") {
    let engine = LiveLocationEngine()
    try engine.prepareDevice()
    NativeTestState.epoch += 1
    NativeTestState.reachable = false
    do { try engine.clear(); check(false, "unreachable stop must fail") } catch {}
    check(NativeTestState.clearCalls == 0, "unreachable verification cannot claim clear")
    NativeTestState.reachable = true
    try engine.clear()
    check(NativeTestState.clearCalls == 1, "stop retry reaches clear after VPN recovery")
}

scenario("mismatched device cannot clear") {
    let engine = LiveLocationEngine()
    NativeTestState.actualIdentity = "different-device"
    do { try engine.clear(); check(false, "mismatched identity must fail") } catch {}
    check(NativeTestState.clearCalls == 0, "no clear on wrong device")
    check(NativeTestState.clientsFreed == 1, "mismatch closes client")
    check(NativeTestState.freshOpens == 1, "mismatch does not trigger reconnect")
}

scenario("invalid identity cannot clear") {
    let engine = LiveLocationEngine()
    NativeTestState.identityXML = "invalid"
    do { try engine.clear(); check(false, "invalid identity must fail") } catch {}
    check(NativeTestState.clearCalls == 0, "no clear on invalid identity")
    check(NativeTestState.clientsFreed == 1, "invalid XML closes client")
    check(NativeTestState.xmlFreed == 1, "invalid XML freed")
    check(NativeTestState.freshOpens == 1, "invalid XML does not trigger reconnect")
}

scenario("failed client connection cannot clear") {
    NativeTestState.failClient = true
    do { try LiveLocationEngine().clear(); check(false, "failed client must fail") } catch {}
    check(NativeTestState.clearCalls == 0, "no clear after client connect failure")
    check(NativeTestState.errorsFreed == 2, "both failed connect errors freed once")
    check(NativeTestState.freshOpens == 2, "client failure allows only one retry")
}

scenario("partial failed client is released") {
    NativeTestState.failClient = true
    NativeTestState.partialClient = true
    do { try LiveLocationEngine().clear(); check(false, "partial failed client must fail") } catch {}
    check(NativeTestState.clientsFreed == 2, "partial clients released on both attempts")
    check(NativeTestState.errorsFreed == 2, "partial client errors released once each")
    check(NativeTestState.clearCalls == 0, "partial failed client cannot clear")
}

scenario("missing client cannot clear") {
    NativeTestState.missingClient = true
    do { try LiveLocationEngine().clear(); check(false, "missing client must fail") } catch {}
    check(NativeTestState.clearCalls == 0, "missing client cannot clear")
    check(NativeTestState.clientsFreed == 0, "no invalid client free")
    check(NativeTestState.freshOpens == 2, "missing client allows only one retry")
}

scenario("device info read failure cannot clear") {
    NativeTestState.xmlReadFails = true
    do { try LiveLocationEngine().clear(); check(false, "device info read failure must fail") } catch {}
    check(NativeTestState.clearCalls == 0, "no clear without identity read")
    check(NativeTestState.clientsFreed == 2, "read failure closes both clients")
    check(NativeTestState.freshOpens == 2, "read failure allows only one retry")
}

scenario("invalid stored pairing cannot open a channel") {
    NativeTestState.recordValid = false
    do { try LiveLocationEngine().clear(); check(false, "invalid pairing must fail") } catch {}
    check(NativeTestState.freshOpens == 0, "invalid pairing opens no tunnel")
    check(NativeTestState.clearCalls == 0, "invalid pairing cannot clear")
}

if failures > 0 { exit(1) }
if CommandLine.arguments.last != "--list" {
    print("PASS: \(CommandLine.arguments.last ?? "") (fake transport; no device claim)")
}
