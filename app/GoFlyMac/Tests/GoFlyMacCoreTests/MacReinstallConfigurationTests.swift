import Foundation
import GoFlyMacCore
import Testing

@Suite struct MacReinstallConfigurationTests {
    @Test func configurationBindsTheValidatorToTheSameAppBundle() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("gofly-reinstall-config-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let resources = root.appendingPathComponent("GoFly.app/Contents/Resources")
        try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
        let url = resources.appendingPathComponent("ReinstallConfiguration.json")
        let workspace = root.standardizedFileURL.path
        let expected: [String: String] = [
            "workspaceRoot": workspace, "pythonPath": workspace + "/work/mac-setup-env/bin/python",
            "developerDirectory": "/Applications/Xcode.app/Contents/Developer",
            "projectPath": workspace + "/app/GoFly/GoFly.xcodeproj",
            "targetBundleID": "com.neven.gofly", "targetName": "GoFly",
            "stateRoot": FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("GoFlySetup").path,
            "validatorPath": resources.deletingLastPathComponent().appendingPathComponent("MacOS/GoFlyTransferValidator").path
        ]
        try JSONSerialization.data(withJSONObject: expected).write(to: url)
        let actual = try MacReinstallConfiguration(configurationURL: url)
        #expect(actual.validatorPath == expected["validatorPath"])
        #expect(actual.targetBundleID == "com.neven.gofly")
        for (key, value) in [
            ("validatorPath", "/other.app/Contents/MacOS/GoFlyTransferValidator"),
            ("pythonPath", "/usr/bin/python3"), ("targetBundleID", "com.neven.localgo"),
            ("stateRoot", workspace + "/arbitrary-state"), ("developerDirectory", "/tmp/Xcode")
        ] {
            var changed = expected
            changed[key] = value
            try JSONSerialization.data(withJSONObject: changed).write(to: url)
            #expect(throws: MacReinstallFailure.invalidRequest) { try MacReinstallConfiguration(configurationURL: url) }
        }
        let raw = String(decoding: try JSONSerialization.data(withJSONObject: expected, options: [.sortedKeys]), as: UTF8.self)
        for invalid in ["{\"validatorPath\":\"/extra\"," + raw.dropFirst(),
                        "{\"extra\":true," + raw.dropFirst(), "{}{}"] {
            try Data(invalid.utf8).write(to: url)
            #expect(throws: MacReinstallFailure.invalidRequest) { try MacReinstallConfiguration(configurationURL: url) }
        }
        // A valid-shaped config outside the calling app cannot launch a script.
        try JSONSerialization.data(withJSONObject: expected).write(to: url)
        #expect(throws: MacReinstallFailure.unavailable) {
            try ReinstallProcessBridge(configurationURL: url, scriptURL: resources.appendingPathComponent("Bridge/Reinstall/reinstall_bridge.py"))
        }
    }
}
