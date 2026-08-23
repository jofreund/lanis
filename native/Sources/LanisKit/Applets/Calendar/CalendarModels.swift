import Foundation

public struct CalendarEventCategory: Codable, Sendable, Hashable, Identifiable {
    public let id: Int
    /// ARGB, e.g. 0xFF4242FC
    public let colorARGB: UInt32
    public let name: String
    public init(id: Int, colorARGB: UInt32, name: String) { self.id = id; self.colorARGB = colorARGB; self.name = name }
}

public struct CalendarEvent: Codable, Sendable, Hashable, Identifiable {
    public static let defaultColor: UInt32 = 0xFF4242FC

    public let id: String
    public var title: String
    public var description: String
    public var startTime: Date
    public var endTime: Date
    public var allDay: Bool
    public var place: String?
    public var category: CalendarEventCategory?
    public var lastModified: Date?
    public var isNew: Bool
    public var isPublic: Bool
    public var isPrivate: Bool
    public var isSecret: Bool
    public var responsibleID: String?
    public var schoolID: String?

    public var colorARGB: UInt32 { category?.colorARGB ?? Self.defaultColor }

    public init(id: String, title: String, description: String = "", startTime: Date, endTime: Date, allDay: Bool = false,
                place: String? = nil, category: CalendarEventCategory? = nil, lastModified: Date? = nil, isNew: Bool = false,
                isPublic: Bool = true, isPrivate: Bool = false, isSecret: Bool = false, responsibleID: String? = nil, schoolID: String? = nil) {
        self.id = id; self.title = title; self.description = description; self.startTime = startTime; self.endTime = endTime
        self.allDay = allDay; self.place = place; self.category = category; self.lastModified = lastModified; self.isNew = isNew
        self.isPublic = isPublic; self.isPrivate = isPrivate; self.isSecret = isSecret; self.responsibleID = responsibleID; self.schoolID = schoolID
    }
}
