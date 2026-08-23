import Foundation

/// Schulportal → Moodle SAML SSO redirect chain (port of `moodle_sso.dart`).
/// Produces the cookies a web view needs to open `https://mo<schoolID>.schulportal.hessen.de` signed in.
public enum MoodleSSO {
    public struct Result: Sendable {
        public let homeURL: URL
        /// Every cookie the chain produced (mo-prod01, MOODLEID1_, MoodleSession, SPH-Session …).
        public let cookies: [HTTPCookie]
    }

    public static func isSchulportalHost(_ url: URL) -> Bool {
        let h = url.host()?.lowercased() ?? ""
        return h == "schulportal.hessen.de" || h.hasSuffix(".schulportal.hessen.de")
    }

    /// Schools may host Moodle under their own `*.schule.hessen.de` / `*.bildung.hessen.de` name; keep those in-app.
    public static func isHessenSchoolHost(_ url: URL) -> Bool {
        let h = url.host()?.lowercased() ?? ""
        return isSchulportalHost(url) || h.hasSuffix(".hessen.de")
    }

    public static func perform(account: ClearTextAccount, config: LanisConfig) async throws -> Result {
        let client = HTTPClient(userAgent: config.userAgent, timeout: 15)
        let home = URL(string: "https://mo\(account.schoolID).schulportal.hessen.de")!

        if let last = HTTPCookie(properties: [.name: "schulportal_lastschool", .value: String(account.schoolID),
                                              .domain: ".hessen.de", .path: "/", .secure: "TRUE"]) {
            client.cookies.setCookie(last)
        }

        func location(_ r: HTTPClient.Response, _ step: String) throws -> URL {
            guard let loc = r.location, let u = URL(string: loc) else { throw LanisError.unknown("Moodle SSO: no redirect at \(step)") }
            return u
        }

        let r1 = try await client.head(home)                                  // → llngproxy01
        let loc1 = try location(r1, "moodle home")
        let r2 = try await client.get(loc1)                                   // → login.schulportal.hessen.de/saml/singleSignOn
        let loc2 = try location(r2, "llngproxy")
        _ = try await client.get(loc2)

        guard let pdata = client.cookies.cookies(for: loc2)?.first(where: { $0.name == "SPH-Sessionpdata" })?.value,
              let decoded = pdata.removingPercentEncoding,
              let json = try? JSONSerialization.jsonObject(with: Data(decoded.utf8)) as? [String: Any],
              let url = json["_url"] as? String else {
            throw LanisError.unknown("Moodle SSO: SPH-Sessionpdata missing")
        }

        let r3 = try await client.postForm(loc2, form: ["user": "\(account.schoolID).\(account.username)", "user2": account.username,
                                                        "password": account.password, "url": url])
        if r3.status == 503 { throw LanisError.lanisDown }
        guard r3.location != nil else { throw LanisError.wrongCredentials }
        let loc3 = try location(r3, "saml login")
        let r4 = try await client.get(loc3)                                   // → mo…/login/index.php
        let loc4 = try location(r4, "proxy artifact")
        _ = try await client.get(loc4)

        let cookies = client.cookies.cookies ?? []
        guard cookies.contains(where: { $0.name == "MoodleSession" }) else { throw LanisError.unknown("Moodle SSO: no MoodleSession cookie") }
        return Result(homeURL: home, cookies: cookies)
    }
}
