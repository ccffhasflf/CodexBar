import AppKit
import CodexBarLiteCore
import Foundation
import Observation

private final class LoginOutput: @unchecked Sendable {
    private let lock = NSLock()
    private var bytes = Data()

    func append(_ data: Data) {
        self.lock.withLock {
            self.bytes.append(data)
            if self.bytes.count > 32768 { self.bytes = Data(self.bytes.suffix(32768)) }
        }
    }

    var authorizationURL: URL? {
        // CLI chunks may end mid-codepoint; replacement decoding keeps an earlier URL usable.
        // swiftlint:disable:next optional_data_string_conversion
        let text = self.lock.withLock { String(decoding: self.bytes, as: UTF8.self) }
        return text.split(whereSeparator: \.isWhitespace).compactMap { URL(string: String($0)) }
            .first { $0.scheme == "https" && $0.host == "auth.openai.com" }
    }
}

@MainActor @Observable
final class LoginCoordinator {
    private(set) var isRunning = false
    private(set) var authorizationURL: URL?
    @ObservationIgnored private var process: Process?
    @ObservationIgnored private var cancelled = false

    static func executable(configured: String) -> URL? {
        let fm = FileManager.default
        if !configured.isEmpty {
            return fm.isExecutableFile(atPath: configured) ? URL(fileURLWithPath: configured) : nil
        }
        let paths = (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").map(String.init)
        let candidates = paths.map { $0 + "/codex" } + [
            "/opt/homebrew/bin/codex", "/usr/local/bin/codex",
            "/Applications/Codex.app/Contents/Resources/codex",
        ]
        return candidates.first(where: { fm.isExecutableFile(atPath: $0) }).map { URL(fileURLWithPath: $0) }
    }

    func run(home: URL, configured: String) async throws {
        guard !self.isRunning else { return }
        guard let executable = Self.executable(configured: configured) else { throw LiteError.missingCLI }
        self.isRunning = true
        self.cancelled = false
        self.authorizationURL = nil
        let process = Process()
        self.process = process
        process.executableURL = executable
        // A separate CODEX_HOME and file-backed credentials keep rotation owned by this app.
        process.arguments = ["-c", "cli_auth_credentials_store=\"file\"", "login"]
        var environment = ProcessInfo.processInfo.environment
        environment["CODEX_HOME"] = home.path
        environment["PATH"] = executable.deletingLastPathComponent().path + ":"
            + (environment["PATH"] ?? "/usr/bin:/bin")
        environment.removeValue(forKey: "OPENAI_API_KEY")
        process.environment = environment
        process.currentDirectoryURL = home
        process.standardInput = FileHandle.nullDevice
        let pipe = Pipe()
        let output = LoginOutput()
        process.standardOutput = pipe
        process.standardError = pipe
        pipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if !data.isEmpty { output.append(data) }
        }
        defer {
            pipe.fileHandleForReading.readabilityHandler = nil
            try? pipe.fileHandleForReading.close()
            try? pipe.fileHandleForWriting.close()
            self.process = nil
            self.authorizationURL = nil
            self.isRunning = false
        }
        try process.run()
        let deadline = Date().addingTimeInterval(300)
        while process.isRunning, !self.cancelled, !Task.isCancelled, Date() < deadline {
            self.authorizationURL = output.authorizationURL
            try? await Task.sleep(for: .milliseconds(200))
        }
        if process.isRunning {
            process.terminate()
            for _ in 0..<10 where process.isRunning {
                try? await Task.sleep(for: .milliseconds(100))
            }
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
            // Reap before the caller removes the temporary account directory.
            process.waitUntilExit()
            if self.cancelled || Task.isCancelled { throw CancellationError() }
            throw LiteError.loginTimedOut
        }
        guard !self.cancelled, !Task.isCancelled else { throw CancellationError() }
        guard process.terminationStatus == 0 else { throw LiteError.loginFailed }
    }

    func cancel() { self.cancelled = true }

    func terminateForQuit() {
        self.cancelled = true
        if let process, process.isRunning { kill(process.processIdentifier, SIGKILL) }
    }
}
