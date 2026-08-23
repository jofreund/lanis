import Testing
import Foundation
@testable import LanisKit

@Suite struct TimetableParserTests {
    func fixture() throws -> Timetable {
        let url = Bundle.module.url(forResource: "timetable", withExtension: "html", subdirectory: "Fixtures")!
        return try TimetableParser.parse(html: try String(contentsOf: url, encoding: .utf8))
    }

    @Test func rowsAndBreaks() throws {
        let t = try fixture()
        #expect(t.weekBadge == "A")
        #expect(t.hours.map(\.label) == ["1.", "2.", "3."])
        #expect(t.hoursWithBreaks.map(\.label) == ["1.", "2.", "Pause", "3."])
    }

    @Test func rowspanLayout() throws {
        let t = try fixture()
        #expect(t.planForAll.count == 2)
        let monday = t.planForAll[0], tuesday = t.planForAll[1]
        #expect(monday.map(\.name) == ["Mathe"])
        #expect(monday[0].duration == 2 && monday[0].startTime == TimeOfDay(hour: 8, minute: 0) && monday[0].endTime == TimeOfDay(hour: 9, minute: 35))
        #expect(monday[0].room == "A12" && monday[0].teacher == "MÜL" && monday[0].id.hasPrefix("m1-0-8-0"))
        // Englisch sits in row 2 col 1 but Monday is covered by the rowspan → Tuesday.
        #expect(tuesday.map(\.name) == ["Deutsch", "Englisch", "Sport"])
        #expect(tuesday[1].startTime == TimeOfDay(hour: 8, minute: 50))
        #expect(t.isCurrentWeek(tuesday[0]) && !t.isCurrentWeek(tuesday[2]) && t.isCurrentWeek(monday[0]))
    }

    @Test func missingTable() throws {
        let t = try TimetableParser.parse(html: "<html><body><p>nix</p></body></html>")
        #expect(t.planForAll.isEmpty && t.planForOwn == nil && t.hours.isEmpty)
    }
}
