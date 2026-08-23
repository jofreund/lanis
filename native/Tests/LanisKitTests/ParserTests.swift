import Testing
import Foundation
@testable import LanisKit

@Suite struct SchoolDirectoryTests {
    @Test func decodesSPHPayload() throws {
        let json = #"[{"Id":"7","Name":"Bergstraße","Schulen":[{"Id":"3354","Name":"B-Schule","Ort":"Wald"},{"Id":"4652","Name":"A-Schule","Ort":"Viernheim"}]}]"#
        let schools = try SchoolDirectory.decode(Data(json.utf8))
        #expect(schools.map(\.name) == ["A-Schule", "B-Schule"])
        #expect(schools[0].id == 4652 && schools[0].district == "Bergstraße")
    }
}

@Suite struct SubstitutionsParserTests {
    @Test func ajaxDay() throws {
        let body = #"[{"Tag":"08.05.2024","Tag_en":"2024-05-08","Stunde":"1 - 2","Klasse":"10a","Fach":"M","Art":"Vertretung","Hinweis":null,"_hervorgehoben":["Fach"]}]"#
        let day = try SubstitutionsParser.parseAjaxDay(body, date: "08.05.2024")
        #expect(day.substitutions.count == 1)
        #expect(day.substitutions[0].hinweis == nil)
        #expect(day.substitutions[0].hervorgehoben == ["Fach"])
        #expect(try SubstitutionsParser.parseAjaxDay("-1", date: "08.05.2024").substitutions.isEmpty)
        #expect(throws: LanisError.self) { try SubstitutionsParser.parseAjaxDay("<html>", date: "x") }
    }

    @Test func nonAjaxHTML() throws {
        let url = Bundle.module.url(forResource: "substitutions_nonajax", withExtension: "html", subdirectory: "Fixtures")!
        let html = try String(contentsOf: url, encoding: .utf8)
        let plan = try SubstitutionsParser.parse(shellHTML: html)
        #expect(plan.days.count == 1)
        let day = plan.days[0]
        #expect(day.parsedDate == "08.05.2024")
        #expect(day.substitutions.map(\.stunde) == ["1 - 2", "5"])
        #expect(day.substitutions[1].art == "Entfall" && day.substitutions[1].raum == nil)
        #expect(day.infos == [SubstitutionInfo(header: "Allgemein", values: ["Raum 12 gesperrt"])])
        #expect(Calendar.current.component(.hour, from: plan.lastUpdated) == 13)
    }

    @Test func helpers() {
        #expect(SubstitutionsParser.parseHours("3. - 4.") == "3 - 4")
        #expect(SubstitutionsParser.parseHours("ganztägig") == "ganztägig")
        #expect(SubstitutionsParser.normalizeDateKey("8_5_2024") == "08.05.2024")
        #expect(SubstitutionsParser.normalizeDateKey("foo") == nil)
    }
}
