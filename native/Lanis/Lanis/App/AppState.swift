import SwiftUI
import LanisKit

/// App-wide observable state: account registry + the active `LanisSession`.
@Observable @MainActor
final class AppState {
    enum Auth: Equatable {
        case signedOut
        case signingIn
        case signedIn(AccountSummary)
        case failed(String)
    }

    var auth: Auth = .signedOut
    var session: LanisSession?
    var accounts: [AccountSummary] = []
    /// PHP URLs the active session may open; empty while signed out. Seeded from the last
    /// sign-in's cached list so the tab bar is correct on the first frame instead of showing
    /// applets this school does not have until SPH answers.
    var supportedApplets: Set<String> = []
    var activeAccountID: Int? { if case .signedIn(let a) = auth { a.localId } else { nil } }
    /// Bumped whenever the session is established or torn down. Applet views key their
    /// `.task(id:)` on `dataToken`; `supportedApplets` alone no longer signals "session ready",
    /// since it is seeded from the cache before the sign-in completes.
    private(set) var sessionGeneration = 0
    struct DataToken: Equatable { let generation: Int; let applets: Set<String> }
    var dataToken: DataToken { DataToken(generation: sessionGeneration, applets: supportedApplets) }
    let snapshots: SnapshotStore
    let settings: AccountSettings
    /// User-picked course colours for the active account.
    let subjectColors = SubjectColors()
    var showLogin = false
    /// Pending deep link (`lanis://common/moodle`, `lanis://common/kalender` …) consumed by `RootView`.
    var deepLink: DeepLink?

    enum DeepLink: Equatable { case moodle, applet(String), settings, course(String, section: String?), timetableFirstLesson, calendarFirstEvent }
    /// Course to open once the lessons list has loaded (from `lanis://student/lessons/<id>`).
    var pendingCourseID: String?
    var pendingCourseSection: String?
    /// `lanis://student/timetable/first` — open the first lesson of the selected day (automation aid).
    var pendingTimetableFirstLesson = false
    var pendingCalendarFirstEvent = false

    /// Parses the Flutter app's `lanis://<scope>/<segment>[/...]` scheme (see `deep_link.dart`).
    static func parse(deepLink url: URL) -> DeepLink? {
        guard url.scheme == "lanis" else { return nil }
        var parts = [url.host() ?? ""] + url.pathComponents.filter { $0 != "/" }
        parts.removeAll { $0.isEmpty }
        guard parts.count >= 2 else { return nil }
        switch parts[1] {
        case "moodle": return .moodle
        case "settings": return .settings
        case "substitutions": return .applet(AppletMeta.substitutions.phpURL)
        case "calendar": return parts.count > 2 && parts[2] == "first" ? .calendarFirstEvent : .applet(AppletMeta.calendar.phpURL)
        case "timetable": return parts.count > 2 && parts[2] == "first" ? .timetableFirstLesson : .applet(AppletMeta.timetable.phpURL)
        case "lessons": return parts.count > 2 ? .course(parts[2], section: parts.count > 3 ? parts[3] : nil) : .applet(AppletMeta.lessons.phpURL)
        case "conversations": return .applet(AppletMeta.conversations.phpURL)
        default: return nil
        }
    }

    private let store: AccountStore
    let config = LanisConfig.default(
        version: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "5.0.0",
        build: Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1")

    init() {
        let dir = (try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true))
            ?? FileManager.default.temporaryDirectory
        let root = dir.appending(path: "Lanis")
        store = AccountStore(directory: root, secrets: KeychainSecretStore())
        snapshots = SnapshotStore(directory: root)
        settings = AccountSettings(directory: root)
        if let id = AccountStore.activeID(directory: root) { supportedApplets = cachedApplets(accountID: id) }
    }

    private static let appletsKey = "supported-applets"
    private func cachedApplets(accountID: Int) -> Set<String> {
        Set(settings.get([String].self, accountID: accountID, key: Self.appletsKey) ?? [])
    }

    /// Re-authenticates the active stored account on launch.
    func restore() async {
        accounts = await store.accounts
        guard let active = await store.active else { showLogin = true; return }
        await activate(id: active.localId)
    }

    /// Validates credentials against SPH, then stores the account and signs in.
    func addAccount(schoolID: Int, username: String, password: String, schoolName: String) async {
        auth = .signingIn
        let candidate = ClearTextAccount(localId: -1, schoolID: schoolID, username: username, password: password, schoolName: schoolName)
        do {
            _ = try await LanisSession.loginURL(for: candidate, config: config)   // cheap credential check, like the Flutter login form
            let summary = try await store.add(schoolID: schoolID, username: username, password: password, schoolName: schoolName)
            try await store.setActive(id: summary.localId)
            accounts = await store.accounts
            await activate(id: summary.localId)
        } catch let e as LanisError {
            auth = .failed(Self.message(for: e)); showLogin = true
        } catch {
            auth = .failed(error.localizedDescription); showLogin = true
        }
    }

    /// Switches to (and signs in with) a stored account.
    func activate(id: Int) async {
        if let old = session { await old.deauthenticate() }
        session = nil
        // Keep the tab bar stable across the sign-in: last known list now, live list below.
        supportedApplets = cachedApplets(accountID: id)
        auth = .signingIn
        sessionGeneration += 1   // bump last: the token must only change on consistent state
        do {
            guard let account = try await store.clearText(id: id) else { throw LanisError.credentialsIncomplete }
            try await store.setActive(id: id)
            let s = LanisSession(account: account, config: config)
            try await s.authenticate()
            var summary = AccountSummary(localId: account.localId, schoolID: account.schoolID, username: account.username,
                                         schoolName: account.schoolName, accountType: await s.accountType, lastLogin: .now)
            summary.accountType = await s.accountType
            try await store.update(summary)
            accounts = await store.accounts
            let applets = await s.supportedApplets
            // Commit session, applet list and auth together, then bump the token — a bump while
            // `auth` is still `.signingIn` would make applet views reload with no active account
            // and, if the live applet list matches the cached one, never fire again.
            session = s
            supportedApplets = applets
            settings.set(Array(applets), accountID: summary.localId, key: Self.appletsKey)
            auth = .signedIn(summary)
            sessionGeneration += 1
            subjectColors.bind(settings: settings, accountID: summary.localId)
            showLogin = false
        } catch let e as LanisError {
            auth = .failed(Self.message(for: e))
        } catch {
            auth = .failed(error.localizedDescription)
        }
    }

    /// Credentials of the active account (Keychain read) — needed for Moodle SSO, which re-authenticates.
    func activeClearTextAccount() async -> ClearTextAccount? {
        guard let id = activeAccountID else { return nil }
        return try? await store.clearText(id: id)
    }

    func remove(id: Int) async {
        if case .signedIn(let a) = auth, a.localId == id, let session {
            await session.deauthenticate()
            self.session = nil
            supportedApplets = []
            auth = .signedOut
            sessionGeneration += 1
            subjectColors.bind(settings: settings, accountID: nil)
        }
        try? await store.remove(id: id)
        snapshots.remove(accountID: id)
        accounts = await store.accounts
        if let next = await store.active { await activate(id: next.localId) } else { showLogin = true }
    }

    /// Temporary English mapping; Phase 2 ports `intl_de.arb` / `intl_en.arb` to a String Catalog.
    static func message(for error: LanisError) -> String {
        switch error {
        case .wrongCredentials: "Wrong school ID, username or password."
        case .lanisDown: "Schulportal Hessen is currently unavailable."
        case .loginTimeout(let s): "Too many failed logins. Wait \(s) s."
        case .noConnection, .network: "No connection."
        case .encryptionCheckFailed: "Encryption handshake failed."
        case .notAuthenticated: "Session expired."
        case .credentialsIncomplete: "Credentials incomplete."
        case .unsupportedApplet: "Diese Funktion ist für dieses Konto nicht freigeschaltet."
        case .parse(let m), .unknown(let m): m
        }
    }
}
