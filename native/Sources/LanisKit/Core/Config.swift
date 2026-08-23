import Foundation

public struct LanisConfig: Sendable {
    public var userAgent: String
    public var requestTimeout: TimeInterval

    public init(userAgent: String, requestTimeout: TimeInterval = 8) {
        self.userAgent = userAgent
        self.requestTimeout = requestTimeout
    }

    public static func `default`(version: String = "0.0.0", build: String = "0") -> LanisConfig {
        LanisConfig(userAgent: "Lanis-Mobile/v\(version)+\(build)")
    }
}

enum SPH {
    static let start = URL(string: "https://start.schulportal.hessen.de/")!
    static let login = URL(string: "https://login.schulportal.hessen.de/")!
    static let connect = URL(string: "https://connect.schulportal.hessen.de")!
    static let ajax = URL(string: "https://start.schulportal.hessen.de/ajax.php")!
    static let schoolList = URL(string: "https://startcache.schulportal.hessen.de/exporteur.php?a=schoollist")!
    static let downMarker = "Der Bereich der pädagogischen Organisation steht Ihnen aktuell nicht zur Verfügung."
}
