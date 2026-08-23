import Foundation

public struct TimeOfDay: Codable, Sendable, Hashable, Comparable {
    public let hour: Int
    public let minute: Int
    public init(hour: Int, minute: Int) { self.hour = hour; self.minute = minute }
    public var minutes: Int { hour * 60 + minute }
    public static func < (a: TimeOfDay, b: TimeOfDay) -> Bool { a.minutes < b.minutes }
    public var formatted: String { String(format: "%02d:%02d", hour, minute) }
}

public struct TimetableSubject: Codable, Sendable, Hashable, Identifiable {
    public let id: String
    public var name: String?
    public var room: String?
    public var teacher: String?
    /// A/B-week badge text, empty when the school has no week rhythm.
    public var badge: String?
    public var duration: Int
    public var startTime: TimeOfDay
    public var endTime: TimeOfDay
    /// Row index in the SPH table (1-based).
    public var lessonIndex: Int

    public init(id: String, name: String?, room: String?, teacher: String?, badge: String?, duration: Int,
                startTime: TimeOfDay, endTime: TimeOfDay, lessonIndex: Int) {
        self.id = id; self.name = name; self.room = room; self.teacher = teacher; self.badge = badge
        self.duration = duration; self.startTime = startTime; self.endTime = endTime; self.lessonIndex = lessonIndex
    }
}

public typealias TimetableDay = [TimetableSubject]

public struct TimetableRow: Codable, Sendable, Hashable {
    public enum Kind: String, Codable, Sendable { case lesson, pause }
    public let kind: Kind
    public let startTime: TimeOfDay
    public let endTime: TimeOfDay
    public let label: String
    public let lessonIndex: Int
    public init(kind: Kind, startTime: TimeOfDay, endTime: TimeOfDay, label: String, lessonIndex: Int) {
        self.kind = kind; self.startTime = startTime; self.endTime = endTime; self.label = label; self.lessonIndex = lessonIndex
    }
}

public struct Timetable: Codable, Sendable, Hashable {
    /// Full class plan (`#all`), one entry per weekday column.
    public var planForAll: [TimetableDay]
    /// Personal plan (`#own`), nil when the school does not offer it.
    public var planForOwn: [TimetableDay]?
    public var hours: [TimetableRow]
    /// Current A/B week badge from `#aktuelleWoche`.
    public var weekBadge: String?

    public init(planForAll: [TimetableDay] = [], planForOwn: [TimetableDay]? = nil, hours: [TimetableRow] = [], weekBadge: String? = nil) {
        self.planForAll = planForAll; self.planForOwn = planForOwn; self.hours = hours; self.weekBadge = weekBadge
    }

    /// True when `lesson` takes place in the current week (badge match) — port of `TimeTableData.isCurrentWeek`.
    public func isCurrentWeek(_ lesson: TimetableSubject, sameWeek: Bool = true) -> Bool {
        guard let w = weekBadge, !w.isEmpty, let b = lesson.badge, !b.isEmpty else { return true }
        return sameWeek ? w == b : w != b
    }

    /// Lessons + synthesized "Pause" rows for gaps > 10 min.
    public var hoursWithBreaks: [TimetableRow] {
        var out: [TimetableRow] = []
        for (i, h) in hours.enumerated() {
            if i > 0, hours[i - 1].endTime != h.startTime, h.startTime.minutes - hours[i - 1].endTime.minutes > 10 {
                out.append(TimetableRow(kind: .pause, startTime: hours[i - 1].endTime, endTime: h.startTime, label: "Pause", lessonIndex: -1))
            }
            out.append(h)
        }
        return out
    }
}
