import Foundation

/// Typed SPH / client errors. Mirrors `liblanis/exceptions.dart`.
/// Messages are developer-facing English; the app maps cases to localized strings.
public enum LanisError: Error, Sendable, Equatable {
    case wrongCredentials
    case lanisDown
    case loginTimeout(seconds: String)
    case credentialsIncomplete
    case network
    case noConnection
    case encryptionCheckFailed
    case notAuthenticated
    case unsupportedApplet(String)
    case parse(String)
    case unknown(String)

    public var isUnexpected: Bool {
        switch self {
        case .parse, .unknown: true
        default: false
        }
    }
}
