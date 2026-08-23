import Foundation

/// Port of `liblanis/applets/calendar/parser.dart` + `CalendarEvent.fromLanisJson`.
public struct CalendarParser: Sendable {
    public static let meta = AppletMeta.calendar
    public init() {}

    public func fetchHome(session: LanisSession) async throws -> [CalendarEvent] {
        try await fetch(session: session, start: .now.addingTimeInterval(-120 * 86400), end: .now.addingTimeInterval(356 * 86400))
    }

    public func fetch(session: LanisSession, start: Date, end: Date, query: String = "") async throws -> [CalendarEvent] {
        let html = try await session.getHTML(path: Self.meta.phpURL)
        let categories = Self.parseCategories(html: html)
        let f = Self.isoDay
        let body = try await session.postForm(path: Self.meta.phpURL,
                                              query: ["f": "getEvents", "s": query, "start": f.string(from: start), "end": f.string(from: end)],
                                              form: ["f": "getEvents", "start": f.string(from: start), "end": f.string(from: end), "s": query])
        return try Self.parseEvents(String(decoding: body, as: UTF8.self), categories: categories)
    }

    /// Event detail; nil when SPH returns an empty object.
    public func event(id: String, session: LanisSession) async throws -> [String: Any]? {
        let body = try await session.postForm(path: Self.meta.phpURL, form: ["f": "getEvent", "id": id])
        guard let dict = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
              let id = dict["id"], !"\(id)".isEmpty, !(id is NSNull) else { return nil }
        return dict
    }

    /// iCal subscription link + exportable years (for Calendar.app subscription).
    public func exports(session: LanisSession) async throws -> (years: Set<Int>, subscriptionLink: String) {
        let html = try await session.getHTML(path: Self.meta.phpURL)
        let re = try NSRegularExpression(pattern: #"year=(\d{4})"#)
        let years = Set(re.matches(in: html, range: NSRange(html.startIndex..., in: html))
            .compactMap { Int(html[Range($0.range(at: 1), in: html)!]) })
        let link = try await session.postForm(path: Self.meta.phpURL, form: ["f": "iCalAbo"])
        return (years, String(decoding: link, as: UTF8.self))
    }

    // MARK: Pure parsing

    /// Extracts `categories.push({id: 1, color: '#abc', name: '…'})` lines from kalender.php.
    public static func parseCategories(html: String) -> [CalendarEventCategory] {
        let re = try! NSRegularExpression(pattern: #"categories\.push\(\s*(\{[^}]+\})\s*\)"#)
        let keyRe = try! NSRegularExpression(pattern: #"(\w+):"#)
        var out: [CalendarEventCategory] = []
        for m in re.matches(in: html, range: NSRange(html.startIndex..., in: html)) {
            let raw = String(html[Range(m.range(at: 1), in: html)!])
            var json = keyRe.stringByReplacingMatches(in: raw, range: NSRange(raw.startIndex..., in: raw), withTemplate: "\"$1\":")
            json = json.replacingOccurrences(of: "'", with: "\"")
            guard let dict = try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any],
                  let id = dict["id"].flatMap({ Int("\($0)") }) else { continue }
            out.append(CalendarEventCategory(id: id, colorARGB: parseColor(dict["color"]), name: "\(dict["name"] ?? "")"))
        }
        return out
    }

    static func parseColor(_ value: Any?) -> UInt32 {
        guard var hex = value as? String, !hex.isEmpty else { return CalendarEvent.defaultColor }
        hex = hex.trimmingCharacters(in: .whitespaces)
        if hex.hasPrefix("#") { hex.removeFirst() }
        if hex.count == 3 { hex = hex.map { "\($0)\($0)" }.joined() }
        guard hex.count == 6, let v = UInt32(hex, radix: 16) else { return CalendarEvent.defaultColor }
        return v | 0xFF00_0000
    }

    public static func parseEvents(_ body: String, categories: [CalendarEventCategory]) throws -> [CalendarEvent] {
        guard let data = try? JSONSerialization.jsonObject(with: Data(body.utf8)), let list = data as? [Any] else {
            throw LanisError.parse("getEvents response is not a JSON list")
        }
        return list.compactMap { ($0 as? [String: Any]).flatMap { parseEvent($0, categories: categories) } }
    }

    static func parseEvent(_ j: [String: Any], categories: [CalendarEventCategory]) -> CalendarEvent? {
        func s(_ k: String) -> String? {
            guard let v = j[k], !(v is NSNull) else { return nil }
            let str = "\(v)"; return str.isEmpty || str == "null" ? nil : str
        }
        guard let start = parseDate(s("Anfang")) ?? parseDate(s("start")),
              let end = parseDate(s("Ende")) ?? parseDate(s("end")) else { return nil }
        let catID = s("category").flatMap(Int.init)
        let allDay = (j["allDay"] as? Bool) ?? (s("allDay") == "true")
        return CalendarEvent(
            id: s("Id") ?? "", title: s("title") ?? "", description: s("description") ?? "",
            startTime: start, endTime: end, allDay: allDay, place: s("Ort"),
            category: categories.first { $0.id == catID }, lastModified: parseDate(s("LetzteAenderung")),
            isNew: s("Neu") != "nein", isPublic: s("Oeffentlich") != "nein", isPrivate: s("Privat") != "nein",
            isSecret: s("Geheim") != "nein", responsibleID: s("Verantwortlich"), schoolID: s("Institution"))
    }

    nonisolated(unsafe) static let isoDay: DateFormatter = make("yyyy-MM-dd")
    nonisolated(unsafe) private static let formats: [DateFormatter] =
        ["yyyy-MM-dd HH:mm:ss", "dd.MM.yyyy HH:mm:ss", "dd.MM.yyyy HH:mm", "yyyy-MM-dd"].map(make)

    private static func make(_ f: String) -> DateFormatter {
        let d = DateFormatter(); d.dateFormat = f; d.locale = Locale(identifier: "de_DE"); d.timeZone = TimeZone(identifier: "Europe/Berlin"); return d
    }

    static func parseDate(_ raw: String?) -> Date? {
        guard let raw = raw?.trimmingCharacters(in: .whitespaces), !raw.isEmpty else { return nil }
        for f in formats { if let d = f.date(from: raw) { return d } }
        return try? Date(raw, strategy: .iso8601.year().month().day().time(includingFractionalSeconds: false).timeZone(separator: .colon))
            ?? Date(raw, strategy: .iso8601)
    }
}
