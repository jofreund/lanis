import Foundation

/// Per-account, per-applet JSON snapshots (port of liblanis `applet_offline_data`).
/// Views show the snapshot immediately, then refresh; on failure they fall back to it.
public struct SnapshotStore: Sendable {
    public struct Snapshot<T: Codable & Sendable>: Sendable {
        public let value: T
        public let fetchedAt: Date
    }

    private struct Envelope<T: Codable>: Codable { let fetchedAt: Date; let value: T }

    public let directory: URL

    public init(directory: URL) { self.directory = directory }

    private func url(accountID: Int, applet: AppletMeta) -> URL {
        directory.appending(path: "snapshots").appending(path: "\(accountID)-\(applet.phpURL.replacingOccurrences(of: ".php", with: "")).json")
    }

    public func read<T: Codable & Sendable>(_ type: T.Type, accountID: Int, applet: AppletMeta) -> Snapshot<T>? {
        guard let data = try? Data(contentsOf: url(accountID: accountID, applet: applet)),
              let env = try? JSONDecoder().decode(Envelope<T>.self, from: data) else { return nil }
        return Snapshot(value: env.value, fetchedAt: env.fetchedAt)
    }

    public func write<T: Codable & Sendable>(_ value: T, accountID: Int, applet: AppletMeta, fetchedAt: Date = .now) throws {
        let target = url(accountID: accountID, applet: applet)
        try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(Envelope(fetchedAt: fetchedAt, value: value)).write(to: target, options: .atomic)
    }

    public func remove(accountID: Int) {
        let dir = directory.appending(path: "snapshots")
        for f in (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? [] where f.lastPathComponent.hasPrefix("\(accountID)-") {
            try? FileManager.default.removeItem(at: f)
        }
    }
}

/// Per-account key/value settings (port of liblanis `account_settings`), JSON on disk.
public final class AccountSettings: @unchecked Sendable {
    private let fileURL: URL
    private var values: [String: [String: String]]   // accountID → key → JSON string
    private let lock = NSLock()

    public init(directory: URL) {
        fileURL = directory.appending(path: "account-settings.json")
        values = (try? Data(contentsOf: fileURL)).flatMap { try? JSONDecoder().decode([String: [String: String]].self, from: $0) } ?? [:]
    }

    public func get<T: Codable>(_ type: T.Type, accountID: Int, key: String) -> T? {
        lock.withLock {
            values[String(accountID)]?[key].flatMap { try? JSONDecoder().decode(T.self, from: Data($0.utf8)) }
        }
    }

    public func set<T: Codable>(_ value: T?, accountID: Int, key: String) {
        lock.withLock {
            var acc = values[String(accountID)] ?? [:]
            acc[key] = value.flatMap { try? String(decoding: JSONEncoder().encode($0), as: UTF8.self) }
            values[String(accountID)] = acc
            try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? JSONEncoder().encode(values).write(to: fileURL, options: .atomic)
        }
    }
}
