import Darwin
import Foundation

public enum CurrentCodexHome {
    public static func resolve(
        configured: String?,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL
    {
        let value = [configured, environment["CODEX_HOME"]]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
        guard let value else { return homeDirectory.appendingPathComponent(".codex", isDirectory: true) }
        if value == "~" { return homeDirectory }
        if value.hasPrefix("~/") { return homeDirectory.appendingPathComponent(String(value.dropFirst(2))) }
        if value.hasPrefix("/") { return URL(fileURLWithPath: value, isDirectory: true).standardizedFileURL }
        return homeDirectory.appendingPathComponent(value, isDirectory: true).standardizedFileURL
    }
}

/// Watches both the file and its parent: Codex may rewrite auth.json in place or atomically replace it.
/// Only metadata is inspected here. No token copy, backup, hashing or polling is needed.
@MainActor
public final class CurrentLoginMonitor {
    private struct Revision: Equatable {
        let inode: UInt64
        let modified: Date
        let size: UInt64
    }

    private let file: URL
    private let onChange: @MainActor () -> Void
    private var sources: [DispatchSourceFileSystemObject] = []
    private var revision: Revision?
    private var pending: Task<Void, Never>?
    private var running = false

    public init(home: URL, onChange: @escaping @MainActor () -> Void) {
        self.file = home.appendingPathComponent("auth.json")
        self.onChange = onChange
    }

    public func start() {
        guard !self.running else { return }
        self.running = true
        self.revision = self.readRevision()
        self.installSources()
    }

    public func stop() {
        self.running = false
        self.pending?.cancel()
        self.pending = nil
        for source in self.sources {
            source.cancel()
        }
        self.sources.removeAll()
    }

    private func readRevision() -> Revision? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: self.file.path),
              let inode = attributes[.systemFileNumber] as? NSNumber,
              let modified = attributes[.modificationDate] as? Date,
              let size = attributes[.size] as? NSNumber
        else { return nil }
        return Revision(inode: inode.uint64Value, modified: modified, size: size.uint64Value)
    }

    private func installSources() {
        for source in self.sources {
            source.cancel()
        }
        self.sources.removeAll()
        var parent = self.file.deletingLastPathComponent()
        while !FileManager.default.fileExists(atPath: parent.path), parent.path != "/" {
            parent.deleteLastPathComponent()
        }
        for url in [parent, self.file] {
            let descriptor = open(url.path, O_EVTONLY)
            guard descriptor >= 0 else { continue }
            let source = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: descriptor, eventMask: [.write, .rename, .delete, .attrib], queue: .main)
            source.setEventHandler { [weak self] in
                Task { @MainActor in self?.changed() }
            }
            source.setCancelHandler { close(descriptor) }
            source.resume()
            self.sources.append(source)
        }
    }

    private func changed() {
        guard self.running else { return }
        self.pending?.cancel()
        self.pending = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(150)) } catch { return }
            guard let self, self.running else { return }
            let next = self.readRevision()
            let changed = next != self.revision
            self.revision = next
            self.installSources()
            self.pending = nil
            if changed { self.onChange() }
        }
    }
}
