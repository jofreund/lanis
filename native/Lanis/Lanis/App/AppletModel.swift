import SwiftUI
import LanisKit

/// Generic applet state: snapshot-first, refresh in background, offline fallback.
/// Port of liblanis `AppletParser.fetchData` semantics (fetching / online / offline / error).
@Observable @MainActor
final class AppletModel<T: Codable & Sendable & Equatable> {
    private(set) var value: T?
    private(set) var fetchedAt: Date?
    private(set) var isOffline = false
    private(set) var error: String?
    private(set) var loading = false

    let applet: AppletMeta
    private var loadedFor: Int?

    init(applet: AppletMeta) { self.applet = applet }

    /// Shows the stored snapshot (if any) at once, then fetches. On failure keeps the snapshot and marks it offline.
    func load(app: AppState, fetch: @Sendable (LanisSession) async throws -> T) async {
        guard let session = app.session, let accountID = app.activeAccountID, app.supportedApplets.contains(applet.phpURL) else {
            value = nil; fetchedAt = nil; error = nil; loadedFor = nil; return
        }
        if loadedFor != accountID, let snap = app.snapshots.read(T.self, accountID: accountID, applet: applet) {
            value = snap.value; fetchedAt = snap.fetchedAt; isOffline = true
        }
        loadedFor = accountID
        loading = true; error = nil
        defer { loading = false }
        do {
            let fresh = try await fetch(session)
            value = fresh; fetchedAt = .now; isOffline = false
            if applet.allowOffline { try? app.snapshots.write(fresh, accountID: accountID, applet: applet) }
        } catch let e as LanisError {
            error = AppState.message(for: e); isOffline = value != nil
        } catch {
            self.error = error.localizedDescription; isOffline = value != nil
        }
    }
}

/// "Offline · Stand 12:30" pill shown above applet content when serving a snapshot.
struct OfflineBanner: View {
    let fetchedAt: Date?
    let error: String?
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "wifi.slash")
            Text("Offline")
            if let fetchedAt { Text("· Stand \(fetchedAt.formatted(date: .omitted, time: .shortened))") }
            Spacer()
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(.secondary)
        .glassCard(tint: .orange.opacity(0.25))
        .padding(.horizontal)
        .help(error ?? "")
    }
}
