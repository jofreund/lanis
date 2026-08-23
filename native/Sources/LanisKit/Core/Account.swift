import Foundation

public enum AccountType: String, Codable, Sendable, CaseIterable {
    case student, teacher, parent
}

/// Account credentials with plaintext password (in-memory / just decrypted).
public struct ClearTextAccount: Sendable, Hashable, Identifiable {
    public var id: Int { localId }
    public let localId: Int
    public let schoolID: Int
    public let username: String
    public let password: String
    public let schoolName: String
    public var accountType: AccountType?

    public init(localId: Int, schoolID: Int, username: String, password: String,
                schoolName: String, accountType: AccountType? = nil) {
        self.localId = localId
        self.schoolID = schoolID
        self.username = username
        self.password = password
        self.schoolName = schoolName
        self.accountType = accountType
    }
}

/// Account row without password (safe for lists / persistence).
public struct AccountSummary: Codable, Sendable, Hashable, Identifiable {
    public var id: Int { localId }
    public let localId: Int
    public let schoolID: Int
    public let username: String
    public let schoolName: String
    public var accountType: AccountType?
    public var lastLogin: Date?
    public let creationDate: Date

    public init(localId: Int, schoolID: Int, username: String, schoolName: String,
                accountType: AccountType? = nil, lastLogin: Date? = nil, creationDate: Date = .now) {
        self.localId = localId
        self.schoolID = schoolID
        self.username = username
        self.schoolName = schoolName
        self.accountType = accountType
        self.lastLogin = lastLogin
        self.creationDate = creationDate
    }
}
