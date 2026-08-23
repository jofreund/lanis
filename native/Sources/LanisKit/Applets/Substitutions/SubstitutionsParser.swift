import Foundation
import SwiftSoup

/// Port of `liblanis/applets/substitutions/parser.dart` (AJAX and non-AJAX paths).
public struct SubstitutionsParser: Sendable {
    public static let meta = AppletMeta.substitutions

    public init() {}

    /// Live fetch: shell page, then one AJAX call per day.
    public func fetchHome(session: LanisSession) async throws -> SubstitutionPlan {
        let shell = try await session.getHTML(path: meta.phpURL)
        var ajax: [String: String] = [:]
        for date in try Self.substitutionDates(in: shell) {
            let body = try await session.postForm(path: Self.meta.phpURL, query: ["a": "my"],
                                                  form: ["tag": date, "ganzerPlan": "true"])
            ajax[date] = String(decoding: body, as: UTF8.self)
        }
        return try Self.parse(shellHTML: shell, ajaxByDate: ajax)
    }

    private var meta: AppletMeta { Self.meta }

    // MARK: Pure parsing

    public static func parse(shellHTML html: String, ajaxByDate: [String: String]? = nil) throws -> SubstitutionPlan {
        let lastEdit = parseLastEditDate(html)
        let dates = try substitutionDates(in: html)
        let doc = try SwiftSoup.parse(html)
        let hasAjax = ajaxByDate.map { a in dates.contains { a[$0] != nil } } ?? false

        if dates.isEmpty || !hasAjax {
            var plan = try parseNonAJAX(doc)
            plan.lastUpdated = lastEdit ?? .now
            return plan
        }

        var plan = SubstitutionPlan(lastUpdated: lastEdit ?? .now)
        for date in dates {
            guard let body = ajaxByDate?[date] else { continue }
            var day = try parseAjaxDay(body, date: date)
            if let tagEl = try doc.getElementById("tag" + date.replacingOccurrences(of: ".", with: "_")) {
                day.infos = try parseInformationTables(tagEl)
            }
            plan.add(day)
        }
        plan.removeEmptyDays()
        return plan
    }

    /// One `getSubstitutions` AJAX body for `date` (dd.MM.yyyy). SPH returns a JSON list,
    /// or a numeric sentinel (`-1`) when empty.
    public static func parseAjaxDay(_ body: String, date: String) throws -> SubstitutionDay {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("<") { throw LanisError.parse("Substitution AJAX body is HTML, not JSON") }
        let decoded: Any
        do { decoded = try JSONSerialization.jsonObject(with: Data(trimmed.utf8), options: [.fragmentsAllowed]) }
        catch { throw LanisError.parse("Substitution AJAX body is not valid JSON") }
        if decoded is NSNumber { return SubstitutionDay(parsedDate: date) }
        guard let list = decoded as? [Any] else { throw LanisError.parse("Substitution AJAX body is not a JSON list") }

        func str(_ e: [String: Any], _ k: String) -> String? {
            guard let v = e[k] else { return nil }
            if v is NSNull { return nil }
            return "\(v)"
        }
        let rows: [Substitution] = list.compactMap { any in
            guard let e = any as? [String: Any] else { return nil }
            return Substitution(
                tag: str(e, "Tag") ?? date, tagEN: str(e, "Tag_en") ?? "",
                stunde: parseHours(str(e, "Stunde") ?? ""),
                vertreter: str(e, "Vertreter"), lehrer: str(e, "Lehrer"), klasse: str(e, "Klasse"),
                klasseAlt: str(e, "Klasse_alt"), fach: str(e, "Fach"), fachAlt: str(e, "Fach_alt"),
                raum: str(e, "Raum"), raumAlt: str(e, "Raum_alt"), hinweis: str(e, "Hinweis"),
                hinweis2: str(e, "Hinweis2"), art: str(e, "Art"), lehrerKuerzel: str(e, "Lehrerkuerzel"),
                vertreterKuerzel: str(e, "Vertreterkuerzel"),
                hervorgehoben: (e["_hervorgehoben"] as? [Any])?.map { "\($0)" })
        }
        return SubstitutionDay(parsedDate: date, substitutions: rows)
    }

    static func parseNonAJAX(_ doc: Document) throws -> SubstitutionPlan {
        var plan = SubstitutionPlan()
        var dateKeys: [String] = []
        func addKey(_ k: String) { if !dateKeys.contains(k) { dateKeys.append(k) } }

        for el in try doc.select("[data-tag]").array() {
            if let key = normalizeDateKey(try el.attr("data-tag")) { addKey(key) }
        }
        let panel = try NSRegularExpression(pattern: #"^tag(\d{2})_(\d{2})_(\d{4})$"#)
        for el in try doc.select("[id^=tag]").array() {
            let id = el.id()
            if let m = panel.firstMatch(in: id, range: NSRange(id.startIndex..., in: id)) {
                let g = (1...3).map { String(id[Range(m.range(at: $0), in: id)!]) }
                addKey("\(g[0]).\(g[1]).\(g[2])")
            }
        }

        for date in dateKeys {
            let idKey = date.replacingOccurrences(of: ".", with: "_")
            guard let tagEl = try doc.getElementById("tag\(idKey)") ?? doc.getElementById("tag\(date)") else { continue }
            var day = SubstitutionDay(parsedDate: date, infos: try parseInformationTables(tagEl))
            guard let vtable = try doc.select("#vtable\(idKey)").first()
                    ?? doc.select("#vtable\(date)").first()
                    ?? tagEl.select("table[id^=vtable]").first() else { plan.add(day); continue }

            let headers = try vtable.select("th").array().compactMap { th -> String? in
                let f = try th.attr("data-field"); return f.isEmpty ? nil : f
            }
            guard let stundeIdx = headers.firstIndex(of: "Stunde") else { plan.add(day); continue }

            for row in try vtable.select("tbody tr").array() {
                if try !row.select("td[colspan]").isEmpty() { continue }
                let fields = try row.select("td").array()
                guard fields.count > stundeIdx else { continue }
                func col(_ name: String) throws -> String? {
                    guard let i = headers.firstIndex(of: name), i < fields.count else { return nil }
                    let t = try fields[i].text().trimmingCharacters(in: .whitespacesAndNewlines)
                    return t.isEmpty ? nil : t
                }
                day.substitutions.append(Substitution(
                    tag: date, tagEN: idKey, stunde: parseHours(try fields[stundeIdx].text()),
                    vertreter: try col("Vertreter"), lehrer: try col("Lehrer"), klasse: try col("Klasse"),
                    klasseAlt: try col("Klasse_alt"), fach: try col("Fach"), fachAlt: try col("Fach_alt"),
                    raum: try col("Raum"), raumAlt: try col("Raum_alt"), hinweis: try col("Hinweis"),
                    hinweis2: try col("Hinweis2"), art: try col("Art")))
            }
            plan.add(day)
        }
        plan.removeEmptyDays()
        return plan
    }

    /// `dd.MM.yyyy` or `dd_MM_yyyy` → `dd.MM.yyyy` (validated).
    static func normalizeDateKey(_ raw: String) -> String? {
        let parts = raw.split(whereSeparator: { $0 == "." || $0 == "_" }).compactMap { Int($0) }
        guard parts.count == 3, (1...31).contains(parts[0]), (1...12).contains(parts[1]), parts[2] > 1970 else { return nil }
        return String(format: "%02d.%02d.%04d", parts[0], parts[1], parts[2])
    }

    /// Unique `data-tag="dd.MM.yyyy"` dates; empty means non-AJAX layout.
    public static func substitutionDates(in html: String) throws -> [String] {
        try LanisSession.checkErrorPage(html, path: meta.phpURL)
        let re = try NSRegularExpression(pattern: #"data-tag="(\d{2})\.(\d{2})\.(\d{4})""#)
        var out: [String] = []
        for m in re.matches(in: html, range: NSRange(html.startIndex..., in: html)) {
            let g = (1...3).map { String(html[Range(m.range(at: $0), in: html)!]) }
            let key = "\(g[0]).\(g[1]).\(g[2])"
            if !out.contains(key) { out.append(key) }
        }
        return out
    }

    /// "Letzte Aktualisierung: 08.05.2024 um 13:35:30 Uhr"
    public static func parseLastEditDate(_ html: String) -> Date? {
        let re = try! NSRegularExpression(
            pattern: #"Letzte\s+Aktualisierung:\s*(\d{2})\.(\d{2})\.(\d{4})\s+um\s+(\d{2}):(\d{2}):(\d{2})\s+Uhr"#,
            options: [.caseInsensitive])
        guard let m = re.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)) else { return nil }
        let g = (1...6).map { Int(html[Range(m.range(at: $0), in: html)!])! }
        return Calendar.current.date(from: DateComponents(year: g[2], month: g[1], day: g[0], hour: g[3], minute: g[4], second: g[5]))
    }

    public static func parseHours(_ hours: String) -> String {
        let re = try! NSRegularExpression(pattern: #"\d+"#)
        let nums = re.matches(in: hours, range: NSRange(hours.startIndex..., in: hours))
            .map { String(hours[Range($0.range, in: hours)!]) }
        if nums.isEmpty || nums.count > 2 { return hours }
        return nums.count == 2 ? "\(nums[0]) - \(nums[1])" : nums[0]
    }

    static func parseInformationTables(_ element: Element) throws -> [SubstitutionInfo] {
        guard let table = try element.getElementsByClass("infos").first() else { return [] }
        var infos: [SubstitutionInfo] = []
        var current: SubstitutionInfo?
        for row in try table.select("tr").array() {
            let cells = try row.select("td").array()
            guard !cells.isEmpty else { continue }
            if (try row.classNames()).contains(where: { $0.contains("header") }) {
                if let c = current { infos.append(c) }
                current = SubstitutionInfo(header: try cells[0].text().trimmingCharacters(in: .whitespacesAndNewlines), values: [])
            } else {
                current?.values.append(try cells[0].html().trimmingCharacters(in: .whitespacesAndNewlines))
            }
        }
        if let c = current { infos.append(c) }
        return infos
    }
}
