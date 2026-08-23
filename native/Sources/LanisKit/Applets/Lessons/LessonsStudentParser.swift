import Foundation
import SwiftSoup

/// Port of `liblanis/applets/lessons/student_parser.dart` (overview, detail, homework toggle).
/// Uploads / file deletion are Phase 4 follow-ups.
public struct LessonsStudentParser: Sendable {
    public static let meta = AppletMeta.lessons
    public init() {}

    public func fetchHome(session: LanisSession) async throws -> [Lesson] {
        let html = try await session.getHTML(path: Self.meta.phpURL, query: ["cacheBreaker": String(Int(Date.now.timeIntervalSince1970 * 1000))])
        let lessons = try Self.parseOverview(html: html)
        return lessons
    }

    public func fetchDetail(session: LanisSession, coursePath: String, force: Bool = false) async throws -> DetailedLesson {
        var query = Self.queryItems(of: coursePath)
        if force { query["cacheBreaker"] = String(Int(Date.now.timeIntervalSince1970 * 1000)) }
        let path = coursePath.split(separator: "?", maxSplits: 1).first.map(String.init) ?? coursePath
        let html = try await session.getHTML(path: path, query: query)
        return try Self.parseDetail(html: html, courseID: Self.courseID(from: coursePath))
    }

    /// SPH answers "1" on success.
    public func setHomework(session: LanisSession, courseID: String, entryID: String, done: Bool) async throws -> Bool {
        let body = try await session.postForm(path: Self.meta.phpURL,
                                              form: ["a": "sus_homeworkDone", "entry": entryID, "id": courseID, "b": done ? "done" : "undone"],
                                              extraHeaders: ["X-Requested-With": "XMLHttpRequest"])
        return String(decoding: body, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines) == "1"
    }

    // MARK: Overview

    public static func parseOverview(html: String) throws -> [Lesson] {
        let doc = try SwiftSoup.parse(html)
        var lessons: [Lesson] = []

        if let row = try doc.getElementById("mappen")?.getElementsByClass("row").first() {
            for mappe in row.children().array() {
                guard let link = try mappe.select("a.btn.btn-primary").first() else { continue }
                let href = try link.attr("href")
                let teachers = try mappe.select("div.btn-group>button").array().map {
                    LessonTeacher(name: try $0.attr("title").components(separatedBy: " (").first?.trimmingCharacters(in: .whitespaces),
                                  kuerzel: try $0.text().trimmingCharacters(in: .whitespaces))
                }
                lessons.append(Lesson(courseID: courseID(from: href),
                                      name: try mappe.getElementsByTag("h2").first()?.text().trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                                      coursePath: href, teachers: teachers))
            }
        }

        // Aktuelle Einträge
        for row in try doc.select("tr.printable").array() {
            guard let datum = try row.select(".datum").first() else { continue }
            let courseURL = try row.select("td>h3>a").first()?.attr("href")
            var homework: Homework?
            if try row.select(".homework").first() != nil {
                homework = Homework(description: try row.select(".realHomework").first()?.text().trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                                    done: try row.select(".undone").first() == nil)
            }
            let entry = LessonEntry(entryID: try row.attr("data-entry"),
                                    topicTitle: try row.select(".thema").first()?.text().trimmingCharacters(in: .whitespacesAndNewlines),
                                    topicDate: germanDate(try datum.text()),
                                    homework: homework,
                                    files: Array(repeating: LessonFile(), count: try row.getElementsByClass("file").count))
            if let i = lessons.firstIndex(where: { $0.coursePath == courseURL }) { lessons[i].currentEntry = entry }
        }

        // Anwesenheiten
        if let anwesend = try doc.getElementById("anwesend") {
            let keys = try anwesend.select("thead>tr").first()?.children().array().map { try $0.text().trimmingCharacters(in: .whitespaces) } ?? []
            for row in try anwesend.select("tbody>tr").array() {
                let cols = row.children().array()
                var values: [String] = []
                for col in cols {
                    try col.select("div.hidden.hidden_encoded").remove()
                    values.append(try col.text().trimmingCharacters(in: .whitespacesAndNewlines))
                }
                var attendances: [String: String] = [:]
                for (i, key) in keys.enumerated() where i < values.count {
                    let k = key.lowercased()
                    if k == "kurs" || k == "lehrkraft" { continue }
                    attendances[k] = values[i].isEmpty ? "0" : values[i]
                }
                guard let href = try row.getElementsByTag("a").first()?.attr("href") else { continue }
                if let i = lessons.firstIndex(where: { href.contains($0.courseID) }) { lessons[i].attendances = attendances }
            }
        }

        return lessons.sorted { a, b in
            switch (a.currentEntry?.topicDate, b.currentEntry?.topicDate) {
            case let (x?, y?): x > y
            case (nil, _?): false
            default: true
            }
        }
    }

    // MARK: Detail

    public static func parseDetail(html: String, courseID: String) throws -> DetailedLesson {
        let doc = try SwiftSoup.parse(html)
        let base = "https://start.schulportal.hessen.de/"

        let heading = try doc.getElementById("content")?.select("h1").first()
        try heading?.children().first()?.remove()
        let title = try heading?.text().trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        var semester1: String?
        let halbjahr = try doc.getElementsByClass("btn btn-default hidden-print").array()
        if halbjahr.count > 1, try halbjahr[0].attr("href").contains("&halb=1") { semester1 = try halbjahr[0].attr("href") }

        var history: [LessonEntry] = []
        for row in try doc.getElementById("history")?.select("table>tbody>tr").array() ?? [] {
            let cells = row.children().array()
            guard cells.count >= 3 else { continue }
            try cells[2].select("div.hidden.hidden_encoded").remove()

            let description = try cells[1].select("span.markup i.far.fa-comment-alt:first-child").first()?.parent()?.text().trimmingCharacters(in: .whitespacesAndNewlines)
            let homeworkText = try cells[1].select("span.homework + br + span.markup").first()?.text().trimmingCharacters(in: .whitespacesAndNewlines)
            let homeworkDone = try row.select("span.done.hidden").isEmpty()

            var files: [LessonFile] = []
            if let alertLink = try cells[1].select("div.alert.alert-info>a").first() {
                let fileBase = (base + (try alertLink.attr("href"))).replacingOccurrences(of: "&b=zip", with: "")
                for div in try row.getElementsByClass("files").first()?.children().array() ?? [] {
                    let name = try div.attr("data-file")
                    files.append(LessonFile(name: name, size: try div.select("a>small").first()?.text(),
                                            url: URL(string: fileBase + "&f=" + (name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? name))))
                }
            }

            var uploads: [LessonUpload] = []
            for group in try cells[1].select("div.btn-group").array() {
                let open = try group.select(".btn-warning").first()
                let closed = try group.select(".btn-default").first()
                guard let button = open ?? closed,
                      let href = try group.select("ul.dropdown-menu li a").first()?.attr("href"),
                      let url = URL(string: base + href) else { continue }
                let nodes = button.getChildNodes()
                let name = nodes.count > 2 ? (nodes[2] as? TextNode)?.text().trimmingCharacters(in: .whitespacesAndNewlines) ?? "" : ""
                let deadline = try open?.select("small").first()?.text()
                    .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                    .replacingOccurrences(of: "bis ", with: "").replacingOccurrences(of: "um", with: "").trimmingCharacters(in: .whitespaces)
                uploads.append(LessonUpload(name: name, status: open != nil ? .open : .closed, url: url,
                                            uploaded: try button.select("span.badge").first()?.text(), deadline: deadline))
            }

            let dateInfo = try cells[0].text().components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            // SwiftSoup collapses newlines in text(); fall back to splitting "dd.MM.yyyy 1. - 2. Stunde".
            let dateParts: [String] = dateInfo.count >= 2 ? dateInfo : splitDateAndHours(dateInfo.first ?? "")
            let presence = try cells[2].text().trimmingCharacters(in: .whitespacesAndNewlines)

            history.append(LessonEntry(
                entryID: try row.attr("data-entry"),
                topicTitle: try cells[1].select("td>b, b").first()?.text().trimmingCharacters(in: .whitespacesAndNewlines),
                description: description,
                topicDate: germanDate(dateParts.first ?? ""),
                schoolHours: dateParts.count > 1 ? dateParts[1].replacingOccurrences(of: "Stunde", with: "").trimmingCharacters(in: .whitespaces) : nil,
                homework: homeworkText.map { Homework(description: $0, done: homeworkDone) },
                presence: presence == "nicht erfasst" ? nil : presence,
                files: files, uploads: uploads))
        }

        var attendances: [String: String] = [:]
        for row in try doc.getElementById("attendanceTable")?.select("table>tbody>tr").array() ?? [] {
            try row.getElementsByClass("hidden_encoded").remove()
            let c = row.children().array()
            if c.count >= 2 { attendances[try c[0].text().trimmingCharacters(in: .whitespaces)] = try c[1].text().trimmingCharacters(in: .whitespaces) }
        }

        var marks: [LessonMark] = []
        for row in try doc.getElementById("marks")?.select("table>tbody>tr").array() ?? [] {
            try row.getElementsByClass("hidden_encoded").remove()
            let c = row.children().array()
            guard c.count == 3 else { continue }
            var comment: String?
            if let next = try row.nextElementSibling(), let td = try next.select("td").array().dropFirst().first {
                let parts = try td.text().trimmingCharacters(in: .whitespaces).components(separatedBy: ":")
                let text = parts.dropFirst().joined(separator: ":").trimmingCharacters(in: .whitespaces)
                comment = text.isEmpty ? nil : text
            }
            marks.append(LessonMark(name: try c[0].text().trimmingCharacters(in: .whitespaces), date: try c[1].text().trimmingCharacters(in: .whitespaces),
                                    mark: try c[2].text().trimmingCharacters(in: .whitespaces), comment: comment))
        }

        let exams = try parseExams(doc)

        let teachers = try doc.getElementsByClass("btn btn-primary dropdown-toggle btn-md").array().map {
            LessonTeacher(name: try $0.parent()?.select("ul>li>a").first()?.text().trimmingCharacters(in: .whitespaces),
                          kuerzel: try $0.text().trimmingCharacters(in: .whitespaces))
        }

        return DetailedLesson(courseID: courseID, name: title, teachers: teachers, history: history, marks: marks, exams: exams,
                              attendances: attendances, semester1Path: semester1)
    }

    /// `#klausuren` holds one block per group ("Kommende …", "Alle …"), each an `h2` + `ul li` list
    /// of "dd.MM.yyyy Arbeit[, 1., 1/2, 2. Std.]" lines.
    static func parseExams(_ doc: Document) throws -> [LessonExamGroup] {
        guard let section = try doc.getElementById("klausuren"),
              !(try section.text().contains("beinhaltet leider noch keine Leistungskontrollen")) else { return [] }
        var groups: [LessonExamGroup] = []
        for block in try section.select("div").array() {
            let kids = block.children().array()
            guard let heading = kids.first(where: { ["h1", "h2", "h3", "h4"].contains($0.tagName()) }) else { continue }
            let lists = kids.filter { $0.tagName() == "ul" }
            let entries = try lists.flatMap { $0.children().array() }.filter { $0.tagName() == "li" }.map { try parseExamLine($0.text()) }
            groups.append(LessonExamGroup(name: try heading.text().trimmingCharacters(in: .whitespaces), entries: entries))
        }
        return groups
    }

    static func parseExamLine(_ raw: String) -> LessonExamEntry {
        let line = raw.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression).trimmingCharacters(in: .whitespaces)
        let re = try! NSRegularExpression(pattern: #"^(\d{2}\.\d{2}\.\d{4})\s*(.*)$"#)
        guard let m = re.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) else {
            return LessonExamEntry(date: nil, kind: line, hours: nil)
        }
        let date = germanDate(String(line[Range(m.range(at: 1), in: line)!]))
        var rest = String(line[Range(m.range(at: 2), in: line)!])
        var hours: String?
        if let comma = rest.firstIndex(of: ",") {
            hours = rest[rest.index(after: comma)...].trimmingCharacters(in: .whitespaces)
            rest = String(rest[..<comma])
        }
        return LessonExamEntry(date: date, kind: rest.trimmingCharacters(in: .whitespaces), hours: hours.map(compactHours))
    }

    /// "1., 1/2, 2. Std." → "1.–2. Std."; "1. Std." stays.
    static func compactHours(_ h: String) -> String {
        let nums = h.components(separatedBy: ",").compactMap { Int($0.trimmingCharacters(in: .whitespaces).prefix { $0.isNumber }) }
        guard let lo = nums.min(), let hi = nums.max() else { return h }
        return lo == hi ? "\(lo). Std." : "\(lo).–\(hi). Std."
    }

    // MARK: Helpers

    static func courseID(from path: String) -> String {
        path.components(separatedBy: "id=").dropFirst().first.map { String($0.prefix { $0 != "&" }) } ?? path
    }

    static func queryItems(of path: String) -> [String: String] {
        guard let q = path.split(separator: "?", maxSplits: 1).dropFirst().first else { return [:] }
        var out: [String: String] = [:]
        for pair in q.split(separator: "&") {
            let kv = pair.split(separator: "=", maxSplits: 1).map(String.init)
            out[kv[0]] = kv.count > 1 ? kv[1].removingPercentEncoding ?? kv[1] : ""
        }
        return out
    }

    static func germanDate(_ s: String) -> Date? {
        let p = s.trimmingCharacters(in: .whitespaces).split(separator: ".").prefix(3).compactMap { Int($0) }
        guard p.count == 3 else { return nil }
        return Calendar(identifier: .gregorian).date(from: DateComponents(timeZone: TimeZone(identifier: "Europe/Berlin"), year: p[2], month: p[1], day: p[0]))
    }

    static func splitDateAndHours(_ s: String) -> [String] {
        let re = try! NSRegularExpression(pattern: #"^(\d{2}\.\d{2}\.\d{4})\s*(.*)$"#)
        guard let m = re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) else { return [s] }
        return [String(s[Range(m.range(at: 1), in: s)!]), String(s[Range(m.range(at: 2), in: s)!])]
    }
}
