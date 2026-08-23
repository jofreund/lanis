import Testing
import Foundation
@testable import LanisKit

@Suite struct StorageTests {
    @Test func snapshotRoundTrip() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let store = SnapshotStore(directory: dir)
        #expect(store.read(Timetable.self, accountID: 1, applet: .timetable) == nil)
        let t = Timetable(planForAll: [[TimetableSubject(id: "x", name: "M", room: nil, teacher: nil, badge: nil, duration: 1,
                                                         startTime: TimeOfDay(hour: 8, minute: 0), endTime: TimeOfDay(hour: 8, minute: 45), lessonIndex: 1)]], weekBadge: "A")
        try store.write(t, accountID: 1, applet: .timetable)
        #expect(store.read(Timetable.self, accountID: 1, applet: .timetable)?.value == t)
        #expect(store.read(Timetable.self, accountID: 2, applet: .timetable) == nil)
        store.remove(accountID: 1)
        #expect(store.read(Timetable.self, accountID: 1, applet: .timetable) == nil)
    }

    @Test func accountSettings() {
        let dir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let s = AccountSettings(directory: dir)
        s.set(["a-1", "b-2"], accountID: 7, key: "hidden-lessons")
        #expect(s.get([String].self, accountID: 7, key: "hidden-lessons") == ["a-1", "b-2"])
        #expect(AccountSettings(directory: dir).get([String].self, accountID: 7, key: "hidden-lessons") == ["a-1", "b-2"])
        s.set(nil as [String]?, accountID: 7, key: "hidden-lessons")
        #expect(s.get([String].self, accountID: 7, key: "hidden-lessons") == nil)
    }
}
