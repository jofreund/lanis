import Foundation
import SwiftSoup

/// Port of `liblanis/applets/timetable/parser.dart` (student timetable).
public struct TimetableParser: Sendable {
    public static let meta = AppletMeta.timetable
    public init() {}

    public func fetchHome(session: LanisSession) async throws -> Timetable {
        // `stundenplan.php` normally redirects to add a query param; the data loads either way.
        // `getHTML` follows same-host redirects, so the final document is what we parse.
        let html = try await session.getHTML(path: Self.meta.phpURL)
        return try Self.parse(html: html)
    }

    public static func parse(html: String) throws -> Timetable {
        let doc = try SwiftSoup.parse(html)
        let all = try doc.select("#all tbody").first()
        let own = try doc.select("#own tbody").first()
        let badge = try doc.getElementById("aktuelleWoche")?.text().trimmingCharacters(in: .whitespacesAndNewlines)
        guard let all else {
            return Timetable(planForAll: [], planForOwn: try own.map(parseRoomPlan), hours: [], weekBadge: badge)
        }
        return Timetable(planForAll: try parseRoomPlan(all), planForOwn: try own.map(parseRoomPlan),
                         hours: try parseRows(all), weekBadge: badge)
    }

    static func parseRoomPlan(_ tbody: Element) throws -> [TimetableDay] {
        let rows = tbody.children().array()
        guard let first = rows.first else { return [] }
        let dayCount = first.children().count - 1
        guard dayCount > 0 else { return [] }

        var result = [TimetableDay](repeating: [], count: dayCount)
        let slots = try tbody.select(".VonBis").array().compactMap { try parseVonBis($0) }
        var parsed = [[Bool]](repeating: [Bool](repeating: false, count: dayCount), count: rows.count + 32)
        let offsetFirstRow = !(try first.children().first()?.text().trimmingCharacters(in: .whitespaces).isEmpty ?? true)

        for (rowIndex, row) in rows.enumerated() where rowIndex > 0 {
            for (colIndex, cell) in row.children().array().enumerated() where colIndex > 0 {
                let rowSpan = Int(try cell.attr("rowspan")) ?? 1
                var day = colIndex - 1
                while day < dayCount, parsed[rowIndex][day] { day += 1 }
                guard day < dayCount else { continue }
                for i in 0..<rowSpan where rowIndex + i < parsed.count { parsed[rowIndex + i][day] = true }
                result[day].append(contentsOf: try parseCell(cell, y: rowIndex, slots: slots, offsetFirstRow: offsetFirstRow, day: day))
            }
        }
        return result
    }

    static func parseRows(_ tbody: Element) throws -> [TimetableRow] {
        var out: [TimetableRow] = []
        for (rowIndex, row) in tbody.children().array().enumerated() where rowIndex > 0 {
            for cell in row.children().array() {
                guard let vonBis = try cell.select(".VonBis").first(),
                      let labelRoot = try cell.select(".print-show").first(),
                      let slot = try parseVonBis(vonBis) else { break }
                let label = try (labelRoot.select("b").first() ?? labelRoot).text().trimmingCharacters(in: .whitespacesAndNewlines)
                out.append(TimetableRow(kind: .lesson, startTime: slot.0, endTime: slot.1, label: label, lessonIndex: rowIndex))
                break
            }
        }
        return out
    }

    static func parseCell(_ cell: Element, y: Int, slots: [(TimeOfDay, TimeOfDay)], offsetFirstRow: Bool, day: Int) throws -> [TimetableSubject] {
        var out: [TimetableSubject] = []
        for row in try cell.select(".stunde").array() {
            let name = try row.select("b").first()?.text().trimmingCharacters(in: .whitespacesAndNewlines)
            let room = row.getChildNodes().compactMap { ($0 as? TextNode)?.text().trimmingCharacters(in: .whitespacesAndNewlines) }.joined()
            let teacher = try row.select("small").first()?.text().trimmingCharacters(in: .whitespacesAndNewlines)
            let badge = try row.select(".badge").first()?.text().trimmingCharacters(in: .whitespacesAndNewlines)
            let duration = Int(try row.parent()?.attr("rowspan") ?? "1") ?? 1

            let startIndex = offsetFirstRow ? y : y - 1
            let endIndex = startIndex + duration - 1
            let start: TimeOfDay, end: TimeOfDay
            if !slots.isEmpty, startIndex >= 0, endIndex < slots.count {
                start = slots[startIndex].0; end = slots[endIndex].1
            } else {
                start = TimeOfDay(hour: 0, minute: 0); end = start
            }
            var id = try row.attr("data-mix")
            if id.isEmpty { id = stableID(name ?? room) }
            out.append(TimetableSubject(id: "\(id)-\(day)-\(start.hour)-\(start.minute)", name: name, room: room.isEmpty ? nil : room,
                                        teacher: teacher, badge: badge, duration: duration, startTime: start, endTime: end, lessonIndex: y))
        }
        return out
    }

    /// Deterministic fallback id (Dart uses UUID v5 of the name; any stable hash works for hidden-lesson settings).
    static func stableID(_ s: String) -> String {
        var h: UInt64 = 0xcbf29ce484222325
        for b in s.utf8 { h ^= UInt64(b); h &*= 0x100000001b3 }
        return String(h, radix: 16)
    }

    static func parseVonBis(_ e: Element) throws -> (TimeOfDay, TimeOfDay)? {
        let parts = try e.text().trimmingCharacters(in: .whitespaces).components(separatedBy: " - ")
        guard parts.count == 2 else { return nil }
        func t(_ s: String) -> TimeOfDay? {
            let c = s.split(separator: ":").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
            return c.count >= 2 ? TimeOfDay(hour: c[0], minute: c[1]) : nil
        }
        guard let a = t(parts[0]), let b = t(parts[1]) else { return nil }
        return (a, b)
    }
}
