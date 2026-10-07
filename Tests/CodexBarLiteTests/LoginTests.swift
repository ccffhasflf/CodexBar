import Foundation
import Testing
@testable import CodexBarLite
@testable import CodexBarLiteCore

@MainActor
struct LoginTests {
    @Test func `login uses a scoped home and file credentials without a shell command`() async throws {
        let fixture = try Fixture()
        defer { fixture.clean() }
        let script = fixture.repository.root.appendingPathComponent("fake codex")
        let contents = """
        #!/bin/sh
        test "$1" = '-c' || exit 3
        test "$2" = 'cli_auth_credentials_store="file"' || exit 4
        test "$3" = 'login' || exit 5
        test -z "$OPENAI_API_KEY" || exit 6
        test "$PWD" -ef "$CODEX_HOME" || exit 7
        exit 0
        """
        try contents.write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: script.path)
        let login = LoginCoordinator()
        try await login.run(home: fixture.repository.home(for: fixture.account), configured: script.path)
        #expect(!login.isRunning)
        #expect(login.authorizationURL == nil)
    }

    @Test func `cancelled login terminates the subprocess and clears progress`() async throws {
        let fixture = try Fixture()
        defer { fixture.clean() }
        let script = fixture.repository.root.appendingPathComponent("waiting-codex")
        try "#!/bin/sh\nexec /bin/sleep 30\n".write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: script.path)
        let login = LoginCoordinator()
        let task = Task { try await login.run(
            home: fixture.repository.home(for: fixture.account),
            configured: script.path) }
        while !login.isRunning {
            await Task.yield()
        }
        login.cancel()
        do {
            try await task.value
            Issue.record("Cancelled login unexpectedly succeeded")
        } catch is CancellationError {
            #expect(!login.isRunning)
        }
    }

    @Test func `missing login binary is reported without leaving a pending login`() async throws {
        let fixture = try Fixture()
        defer { fixture.clean() }
        let login = LoginCoordinator()
        await #expect(throws: (any Error).self) {
            try await login.run(home: fixture.repository.home(for: fixture.account), configured: "/missing-fixture")
        }
        #expect(!login.isRunning)
    }
}
