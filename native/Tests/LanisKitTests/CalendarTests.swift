import Testing
import Foundation
@testable import LanisKit

@Suite struct CalendarParserTests {
    @Test func categories() {
        let html = """
        <script>var categories = [];
        categories.push({id: 1, color: '#f00', name: 'Ferien'});
        categories.push({ id: '7', color: '#12ab34', name: 'Klausur' });
        categories.push({id: 'x', color: '#000', name: 'bad'});
        </script>
        """
        let cats = CalendarParser.parseCategories(html: html)
        #expect(cats.count == 2)
        #expect(cats[0] == CalendarEventCategory(id: 1, colorARGB: 0xFFFF0000, name: "Ferien"))
        #expect(cats[1].colorARGB == 0xFF12AB34)
        #expect(CalendarParser.parseColor("nope") == CalendarEvent.defaultColor)
    }

    @Test func events() throws {
        let body = """
        [{"Id":"42","title":"Mathe-Klausur","description":"<b>Raum 12</b>","Anfang":"2026-09-01 08:00:00","Ende":"2026-09-01 09:30:00",
          "allDay":false,"Ort":"A12","category":"7","Neu":"nein","Oeffentlich":"ja","Privat":"nein","Geheim":"nein","LetzteAenderung":"31.08.2026 10:00"},
         {"Id":"43","title":"Ferien","start":"2026-10-05T00:00:00+02:00","end":"2026-10-17T00:00:00+02:00","allDay":"true"},
         {"Id":"44","title":"broken"}]
        """
        let cats = [CalendarEventCategory(id: 7, colorARGB: 0xFF12AB34, name: "Klausur")]
        let events = try CalendarParser.parseEvents(body, categories: cats)
        #expect(events.count == 2)
        #expect(events[0].category?.name == "Klausur")
        #expect(events[0].place == "A12" && !events[0].isNew && events[0].isPublic && !events[0].isPrivate)
        #expect(Calendar(identifier: .gregorian).component(.hour, from: events[0].lastModified!) >= 0)
        #expect(events[1].allDay)
        #expect(events[1].endTime.timeIntervalSince(events[1].startTime) == 12 * 86400)
        #expect(throws: LanisError.self) { try CalendarParser.parseEvents("{\"error\":1}", categories: []) }
    }
}

@Suite struct AccountStoreTests {
    @Test func lifecycle() async throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let secrets = MemorySecretStore()
        let store = AccountStore(directory: dir, secrets: secrets)
        let a = try await store.add(schoolID: 5150, username: "max.muster", password: "pw", schoolName: "AKG")
        #expect(await store.active?.localId == a.localId)
        await #expect(throws: LanisError.self) { try await store.add(schoolID: 5150, username: "max.muster", password: "x", schoolName: "") }
        let b = try await store.add(schoolID: 6075, username: "erika", password: "pw2", schoolName: "Aartal")
        try await store.setActive(id: b.localId)
        #expect(try await store.clearText(id: b.localId)?.password == "pw2")

        // Reload from disk keeps accounts and active selection.
        let reloaded = AccountStore(directory: dir, secrets: secrets)
        #expect(await reloaded.accounts.count == 2)
        #expect(await reloaded.active?.username == "erika")
        try await reloaded.remove(id: b.localId)
        #expect(await reloaded.active?.username == "max.muster")
        #expect(secrets.read("password.\(b.localId)") == nil)
    }
}
