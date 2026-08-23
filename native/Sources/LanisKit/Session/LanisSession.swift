import Foundation
import SwiftSoup

/// Authenticated SPH HTTP session for one account. Port of `liblanis/session/session.dart`.
public actor LanisSession {
    public let account: ClearTextAccount
    public let config: LanisConfig

    private var http: HTTPClient
    private var cryptor = SPHCryptor()
    private var keepAlive: Task<Void, Never>?

    public private(set) var userData: [String: String] = [:]
    public private(set) var accountType: AccountType?
    public private(set) var travelMenu: [FastTravelEntry] = []
    public private(set) var isAuthenticated = false

    public struct FastTravelEntry: Codable, Sendable, Hashable {
        public let name: String
        public let link: String
        public let color: String?
        public let icon: String?

        enum CodingKeys: String, CodingKey { case name = "Name", link, color = "Farbe", icon = "Logo" }
    }

    public init(account: ClearTextAccount, config: LanisConfig) {
        self.account = account
        self.config = config
        self.http = HTTPClient(userAgent: config.userAgent, timeout: config.requestTimeout)
    }

    // MARK: Login

    /// Resolves the one-time login URL for an account without touching this session's cookies.
    /// Throws `.wrongCredentials`, `.loginTimeout`, `.lanisDown`, `.noConnection`.
    public static func loginURL(for account: ClearTextAccount, config: LanisConfig) async throws -> URL {
        let client = HTTPClient(userAgent: config.userAgent, timeout: config.requestTimeout)
        let url = SPH.login.appending(queryItems: [URLQueryItem(name: "i", value: String(account.schoolID))])
        let r1 = try await client.postForm(url, form: [
            "user": "\(account.schoolID).\(account.username)",
            "user2": account.username,
            "password": account.password,
        ])
        if r1.status == 503 { throw LanisError.lanisDown }

        if r1.location != nil {
            let r2 = try await client.get(SPH.connect)
            guard let loc = r2.location, let u = URL(string: loc) else { throw LanisError.unknown("No login redirect") }
            return u
        }
        if let doc = try? SwiftSoup.parse(r1.text), let lock = try? doc.getElementById("authErrorLocktime") {
            throw LanisError.loginTimeout(seconds: (try? lock.text()) ?? "?")
        }
        throw LanisError.wrongCredentials
    }

    public func authenticate(withoutData: Bool = false, loginURL: URL? = nil) async throws {
        http = HTTPClient(userAgent: config.userAgent, timeout: config.requestTimeout)
        isAuthenticated = false

        let down = try await http.get(SPH.start)
        if down.status == 503 || down.text.contains(SPH.downMarker) { throw LanisError.lanisDown }

        let url: URL
        if let loginURL { url = loginURL } else { url = try await Self.loginURL(for: account, config: config) }
        _ = try await http.get(url)

        travelMenu = try await fetchFastTravelMenu()
        httpLog.notice("fast-travel apps: \(self.travelMenu.map(\.link).joined(separator: ","), privacy: .public)")
        if !withoutData {
            let r = try await http.get(SPH.start.appending(path: "benutzerverwaltung.php")
                .appending(queryItems: [URLQueryItem(name: "a", value: "userData")]))
            let doc = try SwiftSoup.parse(r.text)
            userData = Self.parseUserData(doc)
            accountType = try Self.parseAccountType(doc)
        }

        try await initializeCryptor()
        isAuthenticated = true
        startKeepAlive()
    }

    public func deauthenticate() async {
        keepAlive?.cancel(); keepAlive = nil
        _ = try? await http.get(SPH.start.appending(path: "index.php").appending(queryItems: [URLQueryItem(name: "logout", value: "all")]))
        http.cookies.cookies?.forEach(http.cookies.deleteCookie)
        isAuthenticated = false
    }

    // MARK: Keep-alive (SPH logs idle sessions out; Dart pings every 10 s)

    private func startKeepAlive() {
        keepAlive?.cancel()
        keepAlive = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(10))
                await self?.preventLogout()
            }
        }
    }

    private func preventLogout() async {
        guard let sid = http.cookies.cookies(for: SPH.start)?.first(where: { $0.name == "sid" })?.value else { return }
        _ = try? await http.postForm(SPH.start.appending(path: "ajax_login.php"),
                                     form: ["name": sid], headers: ["x-requested-with": "XMLHttpRequest"])
    }

    // MARK: Cryptor handshake

    private static let ajaxHeaders = [
        "Accept": "*/*", "Sec-Fetch-Dest": "empty", "Sec-Fetch-Mode": "cors", "Sec-Fetch-Site": "same-origin",
    ]

    private func initializeCryptor() async throws {
        cryptor = SPHCryptor()
        let pk = try await http.postForm(SPH.ajax.appending(queryItems: [URLQueryItem(name: "f", value: "rsaPublicKey")]),
                                         form: [:], headers: Self.ajaxHeaders)
        if pk.status == 503 { throw LanisError.lanisDown }
        guard let json = try? JSONSerialization.jsonObject(with: pk.body) as? [String: Any],
              let pem = json["publickey"] as? String else { throw LanisError.network }
        let publicKey = try SPHCryptor.parsePublicKey(pem: pem)

        let hs = try await http.postForm(
            SPH.ajax.appending(queryItems: [URLQueryItem(name: "f", value: "rsaHandshake"),
                                            URLQueryItem(name: "s", value: String(Int.random(in: 0..<2000)))]),
            form: ["key": try cryptor.encryptedKey(with: publicKey)], headers: Self.ajaxHeaders)
        guard let json = try? JSONSerialization.jsonObject(with: hs.body) as? [String: Any],
              let challenge = json["challenge"] as? String else { throw LanisError.network }
        guard cryptor.verifyChallenge(base64: challenge) else { throw LanisError.encryptionCheckFailed }
    }

    /// Diagnostic: performs the RSA/AES handshake on a fresh anonymous session.
    /// Used by Settings → "Check SPH connection" and by the live integration test.
    public static func probeHandshake(config: LanisConfig = .default()) async throws {
        let session = LanisSession(account: ClearTextAccount(localId: -1, schoolID: 0, username: "", password: "", schoolName: ""), config: config)
        try await session.initializeCryptor()
    }

    // MARK: Requests used by applet parsers

    /// GET an SPH page; `<encoded>` blocks are decrypted like the Dart interceptor does.
    public func getHTML(path: String, query: [String: String] = [:]) async throws -> String {
        var target = url(path, query)
        var r = try await http.get(target)
        // SPH bounces some applets through forward.php before serving them. Follow
        // same-host hops only; a hop to the login host means the session is gone.
        var hops = 0
        while r.status == 302, hops < 4 {
            guard let loc = r.location, let next = URL(string: loc, relativeTo: target)?.absoluteURL else { break }
            guard next.host == SPH.start.host else { throw LanisError.notAuthenticated }
            target = next
            r = try await http.get(target)
            hops += 1
        }
        if r.status == 503 { throw LanisError.lanisDown }
        if r.status == 302 { throw LanisError.notAuthenticated }
        try Self.checkErrorPage(r.text, path: path)
        return cryptor.decryptEncodedTags(in: r.text)
    }

    public func postForm(path: String, query: [String: String] = [:], form: [String: String], extraHeaders: [String: String] = [:]) async throws -> Data {
        let r = try await http.postForm(url(path, query), form: form, headers: Self.ajaxHeaders.merging(extraHeaders) { $1 })
        if r.status == 503 { throw LanisError.lanisDown }
        if r.status == 302 { throw LanisError.unknown("Redirected to \(r.location ?? "?") — session lost") }
        return r.body
    }

    /// SPH renders applet errors as a 200 page titled "Fehler - Schulportal Hessen".
    /// "nicht freigeschaltet" = applet not enabled for this account; anything else = session gone.
    static func checkErrorPage(_ html: String, path: String) throws {
        guard html.contains("Fehler - Schulportal Hessen") else { return }
        if html.contains("nicht freigeschaltet") { throw LanisError.unsupportedApplet(path) }
        throw LanisError.notAuthenticated
    }

    /// PHP URLs of applets this account can open (fast-travel menu ∩ account type).
    public var supportedApplets: Set<String> {
        Set(AppletMeta.all.filter { supports($0) }.map(\.phpURL))
    }

    private func url(_ path: String, _ query: [String: String]) -> URL {
        var u = SPH.start.appending(path: path)
        if !query.isEmpty { u.append(queryItems: query.map { URLQueryItem(name: $0, value: $1) }) }
        return u
    }

    private func fetchFastTravelMenu() async throws -> [FastTravelEntry] {
        let r = try await http.get(url("startseite.php", ["a": "ajax", "f": "apps"]))
        struct Envelope: Decodable { let entrys: [FastTravelEntry] }
        do { return try JSONDecoder().decode(Envelope.self, from: r.body).entrys }
        catch { throw LanisError.parse("fast travel menu: \(error)") }
    }

    public func supports(_ applet: AppletMeta, overrideType: AccountType? = nil) -> Bool {
        guard travelMenu.contains(where: { $0.link == applet.phpURL }) else { return false }
        return applet.supportedAccountTypes.contains(overrideType ?? accountType ?? account.accountType ?? .student)
    }

    // MARK: Parsers (static for testability)

    static func parseUserData(_ doc: Document) -> [String: String] {
        guard let body = try? doc.select("div.col-md-12 table.table.table-striped tbody").first() else { return [:] }
        var result: [String: String] = [:]
        for row in (try? body.select("tr").array()) ?? [] {
            let cells = row.children().array()
            guard cells.count >= 2, var key = try? cells[0].text().trimmingCharacters(in: .whitespaces),
                  let value = try? cells[1].text().trimmingCharacters(in: .whitespaces) else { continue }
            if key.hasSuffix(":") { key.removeLast() }
            result[key.lowercased()] = value
        }
        return result
    }

    static func parseAccountType(_ doc: Document) throws -> AccountType {
        guard let icon = try doc.select(".nav.navbar-nav.navbar-right>li>a>i").first() else {
            throw LanisError.unknown("Unknown account type")
        }
        if icon.hasClass("fa-child") { return .student }
        if icon.hasClass("fa-user-circle") { return .parent }
        if icon.hasClass("fa-user") { return .teacher }
        throw LanisError.unknown("Unknown account type")
    }
}
