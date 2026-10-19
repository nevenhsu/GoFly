import Foundation
import Testing
import GoFlyMacCore

@Suite struct MacSetupConfigurationTests {
    @Test func onlyTheFixedFormalProjectAndRuntimeAreAccepted() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("SetupConfiguration.json")
        let workspace = directory.path
        let expected: [String: String] = [
            "workspaceRoot": workspace, "pythonPath": workspace + "/work/mac-setup-env/bin/python",
            "developerDirectory": "/Applications/Xcode.app/Contents/Developer",
            "projectPath": workspace + "/app/GoFly/GoFly.xcodeproj",
            "targetBundleID": "com.neven.gofly", "targetName": "GoFly",
            "stateRoot": FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("GoFlySetup").path
        ]
        try JSONSerialization.data(withJSONObject: expected).write(to: url)
        let accepted = try MacSetupConfiguration(configurationURL: url)
        #expect(accepted.targetBundleID == "com.neven.gofly")
        let executable = directory.appendingPathComponent("work/mac-setup-env/bin/python")
        try FileManager.default.createDirectory(at: executable.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("# controlled fixture; never executed\n".utf8).write(to: executable)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
        try FileManager.default.createDirectory(atPath: expected["projectPath"]!, withIntermediateDirectories: true)
        let outsideScript = directory.appendingPathComponent("Bridge/not-the-entry.py")
        try FileManager.default.createDirectory(at: outsideScript.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("# controlled fixture; never executed\n".utf8).write(to: outsideScript)
        #expect(throws: CheckFailure.bundleInvalid) {
            try ProcessBridge(configurationURL: url, scriptURL: outsideScript)
        }
        var formalCheck = expected
        formalCheck.removeValue(forKey: "stateRoot")
        let checkURL = directory.appendingPathComponent("LocalConfiguration.json")
        try JSONSerialization.data(withJSONObject: formalCheck).write(to: checkURL)
        #expect(throws: CheckFailure.bundleInvalid) {
            try ProcessBridge(configurationURL: checkURL, scriptURL: outsideScript)
        }
        for (key, invalid) in [
            ("pythonPath", "/usr/bin/python3"), ("projectPath", workspace + "/arbitrary.xcodeproj"),
            ("targetBundleID", "com.neven.localgo"), ("targetName", "Other"),
            ("developerDirectory", "/tmp/Xcode"), ("stateRoot", workspace + "/state"),
            ("workspaceRoot", workspace + "/../other")
        ] {
            var value = expected
            value[key] = invalid
            try JSONSerialization.data(withJSONObject: value).write(to: url)
            #expect(throws: MacSetupFailure.invalidRequest) { try MacSetupConfiguration(configurationURL: url) }
        }
        let valid = String(decoding: try JSONSerialization.data(withJSONObject: expected), as: UTF8.self)
        for invalid in ["{\"targetName\":\"Other\"," + valid.dropFirst(),
                        "{\"extra\":true," + valid.dropFirst(), "{}{}"] {
            try Data(invalid.utf8).write(to: url)
            #expect(throws: MacSetupFailure.invalidRequest) { try MacSetupConfiguration(configurationURL: url) }
        }
    }
}
