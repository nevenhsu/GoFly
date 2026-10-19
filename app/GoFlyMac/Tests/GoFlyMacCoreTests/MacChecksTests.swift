import Foundation
import Testing
import GoFlyMacCore

private struct EchoChecker: MacChecking {
    let wrongDevice: Bool
    var installed: Bool? = nil
    var installedVersion: String? = nil
    var installedBuild: String? = nil
    var expiresAt: String? = nil
    func check(_ request: CheckRequest) async throws -> Data {
        let payload: [String: Any]
        switch request.action {
        case .environment: payload = ["ready": true, "checks": [],
                                     "teams": [["teamID": "ABCDE12345", "teamName": "Test Team", "isFreeProvisioningTeam": true]],
                                     "xcodeVersion": "27.1", "projectVersion": "0.2.0", "projectBuild": "21"]
        case .devices: payload = ["devices": [["id": "device-a", "name": "iPhone", "transport": "usb"],
                                              ["id": "device-a", "name": "iPhone", "transport": "wifi"]]]
        case .inspect:
            payload = ["device": ["id": wrongDevice ? "device-b" : "device-a", "name": "iPhone", "transport": request.transport?.rawValue ?? "usb"],
                       "developerMode": true, "installed": installed.map { $0 as Any } ?? NSNull(),
                       "vpnInstalled": NSNull(),
                       "appVersion": installedVersion.map { $0 as Any } ?? NSNull(),
                       "appBuild": installedBuild.map { $0 as Any } ?? NSNull(),
                       "expiresAt": expiresAt.map { $0 as Any } ?? NSNull()]
        }
        return try JSONSerialization.data(withJSONObject: ["requestID": request.requestID,
                                                           "status": "ok", "payload": payload])
    }
}

private struct SlowChecker: MacChecking {
    func check(_ request: CheckRequest) async throws -> Data {
        // Deliberately ignore cancellation to model a late child-process response.
        try? await Task.sleep(for: .milliseconds(120))
        return try await EchoChecker(wrongDevice: false).check(request)
    }
}

private actor HeldChecker: MacChecking {
    private var pending: [(CheckRequest, CheckedContinuation<Data, Error>)] = []
    func check(_ request: CheckRequest) async throws -> Data {
        try await withCheckedThrowingContinuation { pending.append((request, $0)) }
    }
    func entered() -> Bool { !pending.isEmpty }
    func finish() async throws {
        let commands = pending
        pending = []
        for (request, continuation) in commands {
            continuation.resume(returning: try await EchoChecker(wrongDevice: false).check(request))
        }
    }
}

@MainActor private func settled(_ model: MacAppModel) async throws {
    for _ in 0..<200 {
        if !model.busy { return }
        try await Task.sleep(for: .milliseconds(5))
    }
    Issue.record("Model did not finish the check")
}

@Test func readOnlyActionSet() {
    #expect(CheckAction(rawValue: "install") == nil)
    #expect(CheckAction(rawValue: "repair") == nil)
    #expect(CheckAction(rawValue: "reinstall") == nil)
}

@Test func dedupPrefersUSBAndFirstInstallExcludesWiFi() {
    let wifi = ConnectedDevice(id: "ABC", name: "Phone", transport: .wifi)
    let usb = ConnectedDevice(id: "abc", name: "Phone", transport: .usb)
    let other = ConnectedDevice(id: "other", name: "Other", transport: .wifi)
    let management = ConnectedDevice.unique([wifi, usb, other], usbOnly: false)
    #expect(management.count == 2)
    #expect(management.first(where: { $0.id.lowercased() == "abc" })?.transport == .usb)
    #expect(ConnectedDevice.unique([wifi, usb, other], usbOnly: true) == [usb])
    let choices = ConnectedDevice.connectionChoices([wifi, usb, wifi, other], usbOnly: false)
    #expect(choices.count == 3)
    #expect(Set(choices.map(\.connectionID)).count == 3)
    #expect(ConnectedDevice.connectionChoices([wifi, usb, other], usbOnly: true) == [usb])
}

@Test func responseMustMatchFreshRequest() throws {
    let pinned = CheckRequest(action: .inspect, deviceID: "abc", transport: .wifi)
    let encoded = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(pinned)) as? [String: Any])
    #expect(encoded["transport"] as? String == "wifi")
    let request = CheckRequest(action: .environment)
    let oldRequest = CheckRequest(action: .environment)
    let stale = try JSONSerialization.data(withJSONObject: ["requestID": oldRequest.requestID,
        "status": "ok", "payload": ["ready": true, "checks": []]])
    #expect(throws: CheckFailure.invalidResponse) {
        try ResponseDecoder.decode(stale, for: request, as: MacEnvironment.self)
    }
}

@Test func malformedOversizeAndMultipleResponsesFail() {
    let request = CheckRequest(action: .environment)
    for data in [Data(), Data(repeating: 65, count: 262_145), Data("{}{}".utf8), Data("not-json".utf8)] {
        #expect(throws: CheckFailure.invalidResponse) {
            try ResponseDecoder.decode(data, for: request, as: MacEnvironment.self)
        }
    }
}

@Test func unknownErrorCannotLeakArbitraryDiagnostics() throws {
    let request = CheckRequest(action: .devices)
    let data = try JSONSerialization.data(withJSONObject: ["requestID": request.requestID,
        "status": "error", "code": "sensitive raw device output"])
    #expect(throws: CheckFailure.invalidResponse) {
        try ResponseDecoder.decode(data, for: request, as: DeviceList.self)
    }
}

@Test @MainActor func environmentGateAndIdentityMismatch() async throws {
    let model = MacAppModel(live: EchoChecker(wrongDevice: true))
    model.navigate(.devices)
    #expect(model.page == .environment)
    model.checkEnvironment(); try await settled(model)
    model.openDevices(firstInstall: true); try await settled(model)
    model.select("device-a")
    model.inspectSelected(); try await settled(model)
    #expect(model.inspection == nil)
    #expect(model.failure == .invalidResponse)
    #expect(model.page == .devices)
}

@Test @MainActor func installedPhoneOnFirstInstallOffersDevicePage() async throws {
    let model = MacAppModel(live: EchoChecker(wrongDevice: false, installed: true))
    model.checkEnvironment(); try await settled(model)
    model.openDevices(firstInstall: true); try await settled(model)
    model.select("device-a", transport: .usb)
    model.inspectSelected(); try await settled(model)
    #expect(model.installedOnFirstInstall)
    #expect(model.page == .install)
    model.openSelectedDevicePage()
    #expect(!model.firstInstall)
    #expect(model.page == .device)
    #expect(model.selectedID == "device-a")
    #expect(model.selectedTransport == .usb)
}

@Test @MainActor func deviceManagementChoosesUpdateOrRenew() async throws {
    let update = MacAppModel(live: EchoChecker(wrongDevice: false, installed: true,
                                               installedVersion: "0.1.0", installedBuild: "20"))
    update.checkEnvironment(); try await settled(update)
    update.openDevices(firstInstall: false); try await settled(update)
    update.select("device-a", transport: .usb)
    update.inspectSelected(); try await settled(update)
    #expect(update.page == .device)
    #expect(update.renewButtonTitle == "更新 GoFly")

    let renew = MacAppModel(live: EchoChecker(wrongDevice: false, installed: true,
                                              installedVersion: "0.2.0", installedBuild: "21"))
    renew.checkEnvironment(); try await settled(renew)
    renew.openDevices(firstInstall: false); try await settled(renew)
    renew.select("device-a", transport: .usb)
    renew.inspectSelected(); try await settled(renew)
    #expect(renew.renewButtonTitle == "延長簽名期限")
}

@Test @MainActor func cancellationDiscardsLateResult() async throws {
    let model = MacAppModel(live: SlowChecker())
    model.checkEnvironment()
    model.cancel()
    try await Task.sleep(for: .milliseconds(180))
    #expect(model.environment == nil)
    #expect(!model.busy)
}

@Test @MainActor func cancelledReadOnlyCheckRetainsAdmissionUntilItReturns() async throws {
    let runner = HeldChecker()
    let model = MacAppModel(live: runner)
    model.checkEnvironment()
    for _ in 0..<200 {
        if await runner.entered() { break }
        try await Task.sleep(for: .milliseconds(5))
    }
    #expect(await runner.entered())
    model.cancel()
    #expect(model.busy)
    model.navigate(.environment)
    #expect(model.page == .home)
    try await runner.finish()
    try await settled(model)
    #expect(!model.busy)
    #expect(model.environment == nil)
}

@Test @MainActor func changingDeviceClearsEvidence() async throws {
    let model = MacAppModel(live: EchoChecker(wrongDevice: false))
    model.checkEnvironment(); try await settled(model)
    model.openDevices(firstInstall: false); try await settled(model)
    #expect(model.visibleDevices.count == 1)
    #expect(model.availableConnections.count == 2)
    model.select("device-a"); model.inspectSelected(); try await settled(model)
    #expect(model.inspection != nil)
    #expect(model.inspection?.installed == nil)
    model.inspectSelected(); try await settled(model)
    model.select("device-a", transport: .wifi)
    #expect(model.inspection == nil)
    model.inspectSelected(); try await settled(model)
    #expect(model.inspection?.device.transport == .wifi)
    model.refreshDevices(); try await settled(model)
    #expect(model.inspection == nil)
    #expect(model.selectedID == nil)
}

@Test func boundedProcessStopsOnTimeout() throws {
    let runner = BoundedProcess()
    #expect(throws: CheckFailure.timeout) {
        try runner.run(executable: "/usr/bin/python3", arguments: ["-c", "import os,time; os.setpgrp(); time.sleep(10)"],
                       developerDirectory: "/Applications/Xcode.app/Contents/Developer", input: Data(), timeout: 0.15)
    }
}

@Test func boundedProcessRejectsOversizeAndCrash() throws {
    let runner = BoundedProcess()
    #expect(throws: CheckFailure.invalidResponse) {
        try runner.run(executable: "/usr/bin/python3", arguments: ["-c", "import os; os.setpgrp(); print('x'*300000)"],
                       developerDirectory: "/Applications/Xcode.app/Contents/Developer", input: Data(), timeout: 5)
    }
    let crashing = BoundedProcess()
    #expect(throws: CheckFailure.invalidResponse) {
        try crashing.run(executable: "/usr/bin/python3", arguments: ["-c", "raise RuntimeError('private diagnostic')"],
                         developerDirectory: "/Applications/Xcode.app/Contents/Developer", input: Data(), timeout: 5)
    }
}
