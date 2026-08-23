import Testing
import Foundation
import SwiftSoup
@testable import LanisKit

@Suite struct LessonsParserTests {
    @Test func overview() throws {
        let url = Bundle.module.url(forResource: "lessons_overview", withExtension: "html", subdirectory: "Fixtures")!
        let lessons = try LessonsStudentParser.parseOverview(html: try String(contentsOf: url, encoding: .utf8))
        #expect(lessons.map(\.name) == ["Mathematik 10a", "Englisch"])   // newest entry first
        let mathe = lessons[0], englisch = lessons[1]
        #expect(mathe.courseID == "111" && mathe.teachers == [LessonTeacher(name: "Max Müller", kuerzel: "MÜL")])
        #expect(mathe.attendances == ["anwesend": "12", "fehlend": "0"])
        #expect(englisch.currentEntry?.topicTitle == "Unit 1")
        #expect(englisch.currentEntry?.homework == Homework(description: "Vokabeln lernen", done: false))
        #expect(englisch.currentEntry?.files.count == 2)
        #expect(mathe.currentEntry?.homework == nil)
    }

    @Test func exams() throws {
        let html = """
        <div id="klausuren"><div class="row"><div class="col-md-12">
          <div class="col-md-6"><h2><i class="fa"></i> Kommende Leistungskontrolle(n)</h2><ul>
            <li> 04.09.2026 Arbeit, 1., 1/2, 2. Std. </li><li> 14.12.2026 Arbeit, 1. Std. </li></ul></div>
          <div class="col-md-6"><h2>Alle Leistungskontrolle(n)</h2><ul><li> 04.09.2026 Arbeit </li><li> 14.12.2026 Arbeit </li></ul></div>
        </div></div></div>
        """
        let groups = try LessonsStudentParser.parseExams(try SwiftSoup.parse(html))
        #expect(groups.map(\.name) == ["Kommende Leistungskontrolle(n)", "Alle Leistungskontrolle(n)"])
        #expect(groups[0].entries.count == 2 && groups[1].entries.count == 2)
        #expect(groups[0].entries[0].kind == "Arbeit" && groups[0].entries[0].hours == "1.–2. Std.")
        #expect(groups[0].entries[1].hours == "1. Std.")
        #expect(groups[1].entries[0].hours == nil && groups[1].entries[0].date != nil)
        #expect(try LessonsStudentParser.parseExams(try SwiftSoup.parse("<div id=\"klausuren\">Diese Kursmappe beinhaltet leider noch keine Leistungskontrollen!</div>")).isEmpty)
    }

    @Test func helpers() {
        #expect(LessonsStudentParser.courseID(from: "meinunterricht.php?a=sus_view&id=42&halb=1") == "42")
        #expect(LessonsStudentParser.queryItems(of: "meinunterricht.php?a=sus_view&id=42") == ["a": "sus_view", "id": "42"])
        #expect(LessonsStudentParser.splitDateAndHours("21.08.2026 3. - 4. Stunde") == ["21.08.2026", "3. - 4. Stunde"])
        #expect(LessonsStudentParser.germanDate("21.08.2026") != nil)
    }
}
