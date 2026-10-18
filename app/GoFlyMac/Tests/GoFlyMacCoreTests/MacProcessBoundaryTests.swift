import Foundation
import GoFlyMacCore
import Testing

@Suite struct MacProcessBoundaryTests {
    @Test func childCanWriteBothStreamsBeforeReadingTheWholeRequest() throws {
        let process = BoundedProcess()
        let output = try process.run(executable: "/usr/bin/python3", arguments: ["-c",
            "import os,sys; os.setpgrp(); sys.stderr.write('e'*60000); sys.stderr.flush(); sys.stdout.write('o'*100000); sys.stdout.flush(); data=sys.stdin.buffer.read(); print(len(data))"],
            developerDirectory: "/Applications/Xcode.app/Contents/Developer", input: Data(repeating: 65, count: 32768), timeout: 5)
        #expect(output.count == 100006)
        #expect(output.suffix(6) == Data("32768\n".utf8))
        #expect(output.prefix(100000) == Data(repeating: 111, count: 100000))
    }

    @Test func oversizedStderrCannotBeAcceptedAsAValidProcessResponse() throws {
        let process = BoundedProcess()
        #expect(throws: CheckFailure.invalidResponse) {
            try process.run(executable: "/usr/bin/python3", arguments: ["-c",
                "import os,sys; os.setpgrp(); sys.stderr.write('x'*70000); print('{}')"],
                developerDirectory: "/Applications/Xcode.app/Contents/Developer", input: Data(), timeout: 5)
        }
    }
}
