import SwiftUI
import LanisKit

struct LoginView: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss

    @State private var school: School?
    @State private var username = ""
    @State private var password = ""
    @State private var privacyAccepted = false
    @State private var pickingSchool = false

    private var canSubmit: Bool {
        school != nil && !username.isEmpty && !password.isEmpty && privacyAccepted && app.auth != .signingIn
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Button { pickingSchool = true } label: {
                        LabeledContent("Schule") {
                            Text(school.map { "\($0.name) (\($0.city))" } ?? "Auswählen")
                                .foregroundStyle(school == nil ? .secondary : .primary)
                                .multilineTextAlignment(.trailing)
                        }
                    }
                    .tint(.primary)
                    TextField("Benutzername (vorname.nachname)", text: $username)
                        .textContentType(.username).textInputAutocapitalization(.never).autocorrectionDisabled()
                    SecureField("Passwort", text: $password)
                        .textContentType(.password)
                } header: {
                    Text("Schulportal Hessen")
                } footer: {
                    Text("Die Zugangsdaten werden nur im Keychain dieses Geräts gespeichert und ausschließlich an das Schulportal gesendet.")
                }

                Section {
                    Toggle("Datenschutzerklärung akzeptieren", isOn: $privacyAccepted)
                }

                if case .failed(let message) = app.auth {
                    Section {
                        Label(message, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Anmelden")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Später", role: .cancel) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button { submit() } label: {
                        if app.auth == .signingIn { ProgressView() } else { Label("Anmelden", systemImage: "arrow.right") }
                    }
                    .buttonStyle(.glassProminent)
                    .disabled(!canSubmit)
                }
            }
            .sheet(isPresented: $pickingSchool) {
                SchoolPicker(selection: $school)
            }
        }
    }

    private func submit() {
        guard let school else { return }
        Task {
            await app.addAccount(schoolID: school.id, username: username.trimmingCharacters(in: .whitespaces),
                                 password: password, schoolName: school.name)
            if app.session != nil { Haptics.success() }
        }
    }
}

/// Searchable school list (port of `school_selector.dart`).
struct SchoolPicker: View {
    @Binding var selection: School?
    @Environment(\.dismiss) private var dismiss
    @State private var schools: [School] = []
    @State private var query = ""
    @State private var error: String?

    private var filtered: [School] {
        guard !query.isEmpty else { return schools }
        return schools.filter {
            $0.name.localizedCaseInsensitiveContains(query) || $0.city.localizedCaseInsensitiveContains(query) || String($0.id) == query
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if let error {
                    ContentUnavailableView("Schulliste nicht verfügbar", systemImage: "wifi.exclamationmark", description: Text(error))
                } else if schools.isEmpty {
                    ProgressView("Schulen laden …")
                } else {
                    List(filtered) { s in
                        Button {
                            selection = s
                            dismiss()
                        } label: {
                            VStack(alignment: .leading) {
                                Text(s.name)
                                Text("\(s.city) · \(s.district) · \(String(s.id))").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .tint(.primary)
                    }
                    .listStyle(.plain)
                }
            }
            .searchable(text: $query, prompt: "Schule, Ort oder ID")
            .navigationTitle("Schule wählen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Abbrechen", role: .cancel) { dismiss() } } }
            .task {
                do { schools = try await SchoolDirectory.fetch() }
                catch { self.error = error.localizedDescription }
            }
        }
    }
}
