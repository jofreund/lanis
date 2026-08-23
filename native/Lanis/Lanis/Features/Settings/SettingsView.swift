import SwiftUI
import LanisKit

enum SettingsRoute: Hashable { case moodle }

struct SettingsView: View {
    @Environment(AppState.self) private var app
    @Binding var path: NavigationPath
    @State private var probe: String?
    @State private var notificationsGranted: Bool?

    var body: some View {
        NavigationStack(path: $path) {
            List {
                Section("Konten") {
                    ForEach(app.accounts) { a in
                        let active = { if case .signedIn(let s) = app.auth { return s.localId == a.localId } else { return false } }()
                        Button { Task { await app.activate(id: a.localId) } } label: {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(a.username)
                                    Text("\(a.schoolName.isEmpty ? String(a.schoolID) : a.schoolName) · \(a.accountType?.rawValue ?? "–")")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if active { Image(systemName: "checkmark").foregroundStyle(.tint) }
                            }
                        }
                        .tint(.primary)
                        .swipeActions { Button("Entfernen", role: .destructive) { Task { await app.remove(id: a.localId) } } }
                    }
                    Button { app.showLogin = true } label: { Label("Konto hinzufügen", systemImage: "plus") }
                }
                Section("Applets für dieses Konto") {
                    let names = ["vertretungsplan.php": "Vertretungsplan", "kalender.php": "Kalender", "stundenplan.php": "Stundenplan",
                                 "nachrichten.php": "Nachrichten", "meinunterricht.php": "Mein Unterricht", "dateispeicher.php": "Dateispeicher",
                                 "lerngruppen.php": "Lerngruppen"]
                    ForEach(AppletMeta.all) { meta in
                        let on = app.supportedApplets.contains(meta.phpURL)
                        LabeledContent(names[meta.phpURL] ?? meta.phpURL) {
                            Image(systemName: on ? "checkmark.circle.fill" : "minus.circle").foregroundStyle(on ? Color.green : Color.secondary)
                        }
                    }
                }
                if app.supportedApplets.contains("schulmoodle.php") || app.session == nil {
                    Section("Extern") {
                        NavigationLink(value: SettingsRoute.moodle) { Label("Moodle", systemImage: "graduationcap") }
                    }
                }
                Section("Benachrichtigungen") {
                    Button("Mitteilungen erlauben") { Task { notificationsGranted = await BackgroundRefresh.requestAuthorization() } }
                    if let g = notificationsGranted { Text(g ? "Erlaubt" : "Abgelehnt").font(.footnote).foregroundStyle(.secondary) }
                    Text("Der Vertretungsplan wird im Hintergrund aktualisiert; neue Einträge lösen eine Mitteilung aus.").font(.footnote).foregroundStyle(.secondary)
                }
                Section("Diagnose") {
                    Button("SPH-Verschlüsselung testen") {
                        Task {
                            do { try await LanisSession.probeHandshake(); probe = "RSA/AES-Handshake OK" }
                            catch { probe = "Fehler: \(error)" }
                        }
                    }
                    if let probe { Text(probe).font(.footnote).foregroundStyle(.secondary) }
                }
                Section {
                    LabeledContent("Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?")
                    LabeledContent("Engine", value: "Swift / SwiftUI · LanisKit")
                }
            }
            .navigationTitle("Mehr")
            .navigationDestination(for: SettingsRoute.self) { route in
                switch route { case .moodle: MoodleView() }
            }
        }
    }
}
