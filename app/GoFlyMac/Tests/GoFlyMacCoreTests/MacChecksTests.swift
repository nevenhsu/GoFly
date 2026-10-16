import Foundation
import Testing
@testable import GoFlyMacCore

private struct EchoChecker: MacChecking {
    let wrongDevice: Bool
    func check(_ request: CheckRequest) async throws -> Data {
        let payload: [String: Any]
        switch request.action {
        case .environment: payload = ["ready": true, "checks": [], "teamID": NSNull()]
        case .devices: payload = ["devices": [["id": "device-a", "name": "iPhone", "transport": "usb"]]]
        case .inspect:
            payload = ["device": ["id": wrongDevice ? "device-b" : "device-a", "name": "iPhone", "transport": "usb"],
                       "developerMode": true, "installed": NSNull(), "vpnInstalled": NSNull(),
                       "canInstall": false, "canRenew": false, "canRepair": false, "canReinstall": false]
        }
        return try JSONSerialization.data(withJSONObject: ["protocol": 1, "requestID": request.requestID,
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
}

@Test func responseMustMatchFreshRequest() throws {
    let request = CheckRequest(action: .environment)
    let oldRequest = CheckRequest(action: .environment)
    let stale = try JSONSerialization.data(withJSONObject: ["protocol": 1, "requestID": oldRequest.requestID,
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
    let data = try JSONSerialization.data(withJSONObject: ["protocol": 1, "requestID": request.requestID,
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

@Test @MainActor func cancellationDiscardsLateResult() async throws {
    let model = MacAppModel(live: SlowChecker())
    model.checkEnvironment()
    model.cancel()
    try await Task.sleep(for: .milliseconds(180))
    #expect(model.environment == nil)
    #expect(!model.busy)
}

@Test @MainActor func changingDeviceClearsEvidence() async throws {
    let model = MacAppModel(live: EchoChecker(wrongDevice: false))
    model.checkEnvironment(); try await settled(model)
    model.openDevices(firstInstall: true); try await settled(model)
    model.select("device-a"); model.inspectSelected(); try await settled(model)
    #expect(model.inspection != nil)
    #expect(model.inspection?.installed == nil)
    model.refreshDevices(); try await settled(model)
    #expect(model.inspection == nil)
    #expect(model.selectedID == nil)
}

@Test @MainActor func previewDoesNotInvokeLiveChecker() async throws {
    let model = MacAppModel(live: UnavailableChecker())
    model.switchMode(preview: true); try await settled(model)
    #expect(model.ready)
    model.openDevices(firstInstall: true); try await settled(model)
    #expect(model.visibleDevices.count == 1)
    model.select(model.visibleDevices[0].id)
    model.inspectSelected(); try await settled(model)
    #expect(model.page == .install)
    model.previewAdvance()
    #expect(model.page == .vpn)
    model.previewAdvance()
    #expect(model.page == .handoff)
    model.switchMode(preview: false); try await settled(model)
    #expect(model.failure == .unavailable)
    #expect(model.inspection == nil)
    #expect(model.previewStage == 0)
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
