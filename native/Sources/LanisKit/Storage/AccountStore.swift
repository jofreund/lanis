import Foundation

/// Multi-account registry: summaries in a JSON file, passwords in the `SecretStore`.
/// (Plan Phase 2 names SwiftData; a Codable file keeps LanisKit UI-framework-free and
/// is trivially migratable later. Port of liblanis `accounts` table + Riverpod registry.)
public actor AccountStore {
    public struct State: Codable, Sendable {
        public var accounts: [AccountSummary] = []
        public var activeID: Int?
        public var nextID: Int = 1
    }

    private let fileURL: URL
    private let secrets: SecretStore
    private var state: State

    public init(directory: URL, secrets: SecretStore) {
        self.fileURL = directory.appending(path: "accounts.json")
        self.secrets = secrets
        self.state = (try? Data(contentsOf: fileURL)).flatMap { try? JSONDecoder().decode(State.self, from: $0) } ?? State()
    }

    public var accounts: [AccountSummary] { state.accounts }
    public var active: AccountSummary? { state.accounts.first { $0.localId == state.activeID } }

    private func persist() throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(state).write(to: fileURL, options: .atomic)
    }

    private static func key(_ id: Int) -> String { "password.\(id)" }

    /// Adds an account; throws if the same school/user pair exists.
    @discardableResult
    public func add(schoolID: Int, username: String, password: String, schoolName: String, accountType: AccountType? = nil) throws -> AccountSummary {
        guard !state.accounts.contains(where: { $0.schoolID == schoolID && $0.username == username }) else {
            throw LanisError.unknown("Account already exists")
        }
        let summary = AccountSummary(localId: state.nextID, schoolID: schoolID, username: username, schoolName: schoolName, accountType: accountType)
        try secrets.write(password, for: Self.key(summary.localId))
        state.nextID += 1
        state.accounts.append(summary)
        if state.activeID == nil { state.activeID = summary.localId }
        try persist()
        return summary
    }

    public func update(_ summary: AccountSummary) throws {
        guard let i = state.accounts.firstIndex(where: { $0.localId == summary.localId }) else { return }
        state.accounts[i] = summary
        try persist()
    }

    public func remove(id: Int) throws {
        state.accounts.removeAll { $0.localId == id }
        try? secrets.delete(Self.key(id))
        if state.activeID == id { state.activeID = state.accounts.first?.localId }
        try persist()
    }

    public func setActive(id: Int) throws {
        guard state.accounts.contains(where: { $0.localId == id }) else { return }
        state.activeID = id
        try persist()
    }

    /// Summary + Keychain password → credentials for `LanisSession`.
    public func clearText(id: Int) throws -> ClearTextAccount? {
        guard let s = state.accounts.first(where: { $0.localId == id }), let pw = try secrets.read(Self.key(id)) else { return nil }
        return ClearTextAccount(localId: s.localId, schoolID: s.schoolID, username: s.username, password: pw, schoolName: s.schoolName, accountType: s.accountType)
    }
}
