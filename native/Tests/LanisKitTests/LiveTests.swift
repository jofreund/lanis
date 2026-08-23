import Testing
import Foundation
@testable import LanisKit

/// Hits the real SPH servers. Run with `LANIS_LIVE=1 swift test`.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["LANIS_LIVE"] == "1"))
struct LiveTests {
    @Test func schoolList() async throws {
        let schools = try await SchoolDirectory.fetch()
        #expect(schools.count > 500)
        #expect(schools.contains { $0.id == 5150 })
    }

    @Test func rsaAesHandshake() async throws {
        try await LanisSession.probeHandshake()
    }
}
