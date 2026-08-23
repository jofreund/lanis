import Foundation

/// Applet identity + defaults (port of `liblanis@0.1.2 lib/src/applets/definition.dart`).
public struct AppletMeta: Sendable, Hashable, Identifiable {
    public var id: String { phpURL }
    public let phpURL: String
    public let supportedAccountTypes: [AccountType]
    public let allowOffline: Bool
    public let refreshInterval: Duration

    public static let substitutions = AppletMeta(phpURL: "vertretungsplan.php", supportedAccountTypes: AccountType.allCases, allowOffline: true, refreshInterval: .seconds(600))
    public static let calendar      = AppletMeta(phpURL: "kalender.php",        supportedAccountTypes: AccountType.allCases, allowOffline: false, refreshInterval: .seconds(3600))
    public static let timetable     = AppletMeta(phpURL: "stundenplan.php",     supportedAccountTypes: [.student],            allowOffline: true, refreshInterval: .seconds(3600))
    public static let conversations = AppletMeta(phpURL: "nachrichten.php",     supportedAccountTypes: AccountType.allCases, allowOffline: false, refreshInterval: .seconds(120))
    public static let lessons       = AppletMeta(phpURL: "meinunterricht.php",  supportedAccountTypes: AccountType.allCases, allowOffline: false, refreshInterval: .seconds(900))
    public static let dataStorage   = AppletMeta(phpURL: "dateispeicher.php",   supportedAccountTypes: AccountType.allCases, allowOffline: false, refreshInterval: .seconds(300))
    public static let studyGroups   = AppletMeta(phpURL: "lerngruppen.php",     supportedAccountTypes: [.student],            allowOffline: false, refreshInterval: .seconds(900))

    public static let all: [AppletMeta] = [substitutions, calendar, timetable, conversations, lessons, dataStorage, studyGroups]
}
