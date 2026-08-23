import SwiftUI
import LanisKit

/// Liquid Glass tab shell. Tabs mirror the Flutter bottom-navigation applets;
/// search gets the system search tab role; the signed-in account lives in the
/// bottom accessory so it is always one tap away (replaces the Flutter drawer header).
struct RootView: View {
    @Environment(AppState.self) private var app
    @State private var selection: Tabs = .substitutions
    @State private var morePath = NavigationPath()

    enum Tabs: Hashable { case substitutions, calendar, timetable, lessons, conversations, more }

    /// Tab order, used both for the "first available" fallback and the applet lookup.
    private static let order: [(tab: Tabs, meta: AppletMeta)] = [
        (.substitutions, .substitutions), (.calendar, .calendar), (.timetable, .timetable),
        (.lessons, .lessons), (.conversations, .conversations),
    ]

    /// Mirror the Flutter drawer: only applets SPH lists for this account get a tab.
    /// With no known list (fresh install, signed out) every tab is shown so the shell is browsable.
    private func shows(_ meta: AppletMeta) -> Bool {
        app.supportedApplets.isEmpty || app.supportedApplets.contains(meta.phpURL)
    }

    /// Selection that is guaranteed to exist: if the picked tab's applet is not available for this
    /// account, fall back to the first one that is. Derived rather than corrected in `onChange` so
    /// an unsupported default (substitutions) is never shown, not even for one frame.
    private var effectiveSelection: Tabs {
        guard let current = Self.order.first(where: { $0.tab == selection }), !shows(current.meta) else { return selection }
        return Self.order.first { shows($0.meta) }?.tab ?? .more
    }

    var body: some View {
        @Bindable var app = app
        let tab = Binding(get: { effectiveSelection }, set: { selection = $0 })
        TabView(selection: tab) {
            if shows(.substitutions) {
                Tab("Vertretungen", systemImage: "arrow.left.arrow.right", value: .substitutions) { SubstitutionsView() }
            }
            if shows(.calendar) {
                Tab("Kalender", systemImage: "calendar", value: .calendar) { CalendarView() }
            }
            if shows(.timetable) {
                Tab("Stundenplan", systemImage: "tablecells", value: .timetable) { TimetableView() }
            }
            if shows(.lessons) {
                Tab("Unterricht", systemImage: "books.vertical", value: .lessons) { LessonsView() }
            }
            if shows(.conversations) {
                Tab("Nachrichten", systemImage: "bubble.left.and.bubble.right", value: .conversations) {
                    PlaceholderApplet(title: "Nachrichten", symbol: "bubble.left.and.bubble.right", phase: "Phase 4")
                }
            }
            Tab("Mehr", systemImage: "ellipsis.circle", value: .more) {
                SettingsView(path: $morePath)
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .onOpenURL { url in app.deepLink = AppState.parse(deepLink: url) }
        .onChange(of: app.deepLink) { _, link in
            DebugTrace.log("deepLink changed: \(String(describing: link))")
            guard let link else { return }
            switch link {
            case .moodle: selection = .more; morePath.append(SettingsRoute.moodle)
            case .settings: selection = .more
            case .calendarFirstEvent: selection = .calendar; app.pendingCalendarFirstEvent = true
            case .timetableFirstLesson: selection = .timetable; app.pendingTimetableFirstLesson = true
            case .course(let id, let section): selection = .lessons; app.pendingCourseID = id; app.pendingCourseSection = section
            case .applet(let php):
                switch php {
                case AppletMeta.substitutions.phpURL: selection = .substitutions
                case AppletMeta.calendar.phpURL: selection = .calendar
                case AppletMeta.timetable.phpURL: selection = .timetable
                case AppletMeta.lessons.phpURL: selection = .lessons
                default: selection = .conversations
                }
            }
            app.deepLink = nil
        }
        // Account switcher only earns its space with ≥ 2 accounts; single-account users manage it in Settings.
        .tabViewBottomAccessory(isEnabled: app.accounts.count > 1) { AccountChip() }
        .sheet(isPresented: $app.showLogin) {
            LoginView()
        }
    }
}

/// Glass account chip in the tab bar accessory.
struct AccountChip: View {
    @Environment(AppState.self) private var app

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.subheadline.weight(.semibold)).lineLimit(1)
                Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            if case .signingIn = app.auth { ProgressView().controlSize(.small) }
        }
        .padding(.horizontal, 14)
        .contentShape(.rect)
        .overlay { Menu { menuItems } label: { Color.clear } }
    }

    @ViewBuilder private var menuItems: some View {
        ForEach(app.accounts) { acc in
            Button {
                Task { await app.activate(id: acc.localId) }
            } label: {
                let active = { if case .signedIn(let a) = app.auth { return a.localId == acc.localId } else { return false } }()
                Label("\(acc.username) · \(acc.schoolName.isEmpty ? String(acc.schoolID) : acc.schoolName)",
                      systemImage: active ? "checkmark.circle.fill" : "person.crop.circle")
            }
        }
        Divider()
        Button { app.showLogin = true } label: { Label("Konto hinzufügen", systemImage: "plus") }
    }

    private var symbol: String {
        switch app.auth {
        case .signedIn(let a):
            switch a.accountType { case .teacher: "person.text.rectangle"; case .parent: "figure.and.child.holdinghands"; default: "graduationcap" }
        case .signingIn: "arrow.triangle.2.circlepath"
        default: "person.crop.circle.badge.questionmark"
        }
    }
    private var title: String {
        switch app.auth {
        case .signedIn(let a): a.username
        case .signingIn: String(localized: "Anmelden …")
        case .failed: String(localized: "Anmeldung fehlgeschlagen")
        case .signedOut: String(localized: "Nicht angemeldet")
        }
    }
    private var subtitle: String {
        switch app.auth {
        case .signedIn(let a): a.schoolName.isEmpty ? "Schule \(a.schoolID)" : a.schoolName
        case .failed(let m): m
        default: String(localized: "Tippen zum Anmelden")
        }
    }
}

struct PlaceholderApplet: View {
    let title: String
    let symbol: String
    let phase: String

    var body: some View {
        NavigationStack {
            ContentUnavailableView {
                Label(title, systemImage: symbol)
            } description: {
                Text("Wird im Rebuild-Plan in \(phase) portiert.")
            }
            .navigationTitle(title)
        }
    }
}
