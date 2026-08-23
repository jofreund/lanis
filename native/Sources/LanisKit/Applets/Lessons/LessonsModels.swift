import Foundation

public struct LessonTeacher: Codable, Sendable, Hashable {
    public var name: String?
    public var kuerzel: String?
    public init(name: String?, kuerzel: String?) { self.name = name; self.kuerzel = kuerzel }
}

public struct Homework: Codable, Sendable, Hashable {
    public var description: String
    public var done: Bool
    public init(description: String, done: Bool) { self.description = description; self.done = done }
}

public struct LessonFile: Codable, Sendable, Hashable, Identifiable {
    public var id: String { url?.absoluteString ?? name ?? UUID().uuidString }
    public var name: String?
    public var size: String?
    public var url: URL?
    public init(name: String? = nil, size: String? = nil, url: URL? = nil) { self.name = name; self.size = size; self.url = url }
}

public struct LessonUpload: Codable, Sendable, Hashable, Identifiable {
    public enum Status: String, Codable, Sendable { case open, closed }
    public var id: String { url.absoluteString }
    public var name: String
    public var status: Status
    public var url: URL
    public var uploaded: String?
    public var deadline: String?
    public init(name: String, status: Status, url: URL, uploaded: String? = nil, deadline: String? = nil) {
        self.name = name; self.status = status; self.url = url; self.uploaded = uploaded; self.deadline = deadline
    }
}

/// One course-folder entry ("Stunde") — the current one on the overview, all of them in the detail view.
public struct LessonEntry: Codable, Sendable, Hashable, Identifiable {
    public var id: String { entryID }
    public let entryID: String
    public var topicTitle: String?
    public var description: String?
    public var topicDate: Date?
    public var schoolHours: String?
    public var homework: Homework?
    public var presence: String?
    public var files: [LessonFile]
    public var uploads: [LessonUpload]
    public init(entryID: String, topicTitle: String? = nil, description: String? = nil, topicDate: Date? = nil, schoolHours: String? = nil,
                homework: Homework? = nil, presence: String? = nil, files: [LessonFile] = [], uploads: [LessonUpload] = []) {
        self.entryID = entryID; self.topicTitle = topicTitle; self.description = description; self.topicDate = topicDate
        self.schoolHours = schoolHours; self.homework = homework; self.presence = presence; self.files = files; self.uploads = uploads
    }
}

public struct Lesson: Codable, Sendable, Hashable, Identifiable {
    public var id: String { courseID }
    public let courseID: String
    public var name: String
    /// Relative SPH path, e.g. `meinunterricht.php?a=sus_view&id=1234`.
    public var coursePath: String
    public var teachers: [LessonTeacher]
    public var attendances: [String: String]?
    public var currentEntry: LessonEntry?
    public init(courseID: String, name: String, coursePath: String, teachers: [LessonTeacher], attendances: [String: String]? = nil, currentEntry: LessonEntry? = nil) {
        self.courseID = courseID; self.name = name; self.coursePath = coursePath; self.teachers = teachers; self.attendances = attendances; self.currentEntry = currentEntry
    }
}

public struct LessonMark: Codable, Sendable, Hashable, Identifiable {
    public var id: String { "\(name)|\(date)|\(mark)" }
    public var name: String, date: String, mark: String
    public var comment: String?
    public init(name: String, date: String, mark: String, comment: String? = nil) { self.name = name; self.date = date; self.mark = mark; self.comment = comment }
}

public struct LessonExamEntry: Codable, Sendable, Hashable, Identifiable {
    public var id: String { "\(date?.timeIntervalSince1970 ?? 0)|\(kind)|\(hours ?? "")" }
    public var date: Date?
    /// "Arbeit", "Klausur", "Test" …
    public var kind: String
    /// "1.–2. Std." (compacted), nil when SPH omits it.
    public var hours: String?
    public init(date: Date?, kind: String, hours: String?) { self.date = date; self.kind = kind; self.hours = hours }
}

public struct LessonExamGroup: Codable, Sendable, Hashable, Identifiable {
    public var id: String { name }
    public var name: String
    public var entries: [LessonExamEntry]
    public init(name: String, entries: [LessonExamEntry]) { self.name = name; self.entries = entries }
}

public struct DetailedLesson: Codable, Sendable, Hashable {
    public let courseID: String
    public var name: String
    public var teachers: [LessonTeacher]
    public var history: [LessonEntry]
    public var marks: [LessonMark]
    public var exams: [LessonExamGroup]
    public var attendances: [String: String]
    public var semester1Path: String?
    public init(courseID: String, name: String, teachers: [LessonTeacher], history: [LessonEntry], marks: [LessonMark], exams: [LessonExamGroup], attendances: [String: String], semester1Path: String? = nil) {
        self.courseID = courseID; self.name = name; self.teachers = teachers; self.history = history; self.marks = marks; self.exams = exams; self.attendances = attendances; self.semester1Path = semester1Path
    }
}
