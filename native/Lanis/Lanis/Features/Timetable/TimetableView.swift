import SwiftUI
import LanisKit

struct TimetableView: View {
    @Environment(AppState.self) private var app
    @State private var model = AppletModel<Timetable>(applet: .timetable)
    @State private var day = TimetableView.todayIndex
    @State private var useOwn = true
    @State private var thisWeek = true
    @State private var hidden: Set<String> = []
    @State private var showHidden = false
    @State private var selected: TimetableSubject?
    private var timetable: Timetable? { model.value }

    private static var todayIndex: Int {
        let wd = Calendar.current.component(.weekday, from: .now) // 1 = Sunday
        return min(max(wd - 2, 0), 4)
    }
    private static let dayNames = ["Montag", "Dienstag", "Mittwoch", "Donnerstag", "Freitag", "Samstag", "Sonntag"]

    private var plan: [TimetableDay] {
        guard let t = timetable else { return [] }
        return (useOwn ? t.planForOwn : nil) ?? t.planForAll
    }
    private var lessons: [TimetableSubject] {
        guard let t = timetable, day < plan.count else { return [] }
        return plan[day].filter { t.isCurrentWeek($0, sameWeek: thisWeek) && (showHidden || !hidden.contains($0.id)) }.sorted { $0.startTime < $1.startTime }
    }

    var body: some View {
        NavigationStack {
            Group {
                if let timetable, !plan.isEmpty {
                    content(timetable)
                } else if model.loading {
                    ProgressView("Stundenplan laden …")
                } else if let error = model.error {
                    ContentUnavailableView("Fehler", systemImage: "exclamationmark.triangle", description: Text(error))
                } else if app.session == nil {
                    ContentUnavailableView("Nicht angemeldet", systemImage: "person.crop.circle.badge.questionmark")
                } else {
                    ContentUnavailableView("Kein Stundenplan", systemImage: "tablecells")
                }
            }
            .navigationTitle("Stundenplan")
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    if timetable?.planForOwn != nil {
                        Button { useOwn.toggle() } label: {
                            Label(useOwn ? "Eigener Plan" : "Klassenplan", systemImage: useOwn ? "person" : "person.3")
                        }
                    }
                    if let badge = timetable?.weekBadge, !badge.isEmpty {
                        Button { thisWeek.toggle() } label: {
                            Text(thisWeek ? "\(badge)-Woche" : "Nächste").font(.subheadline.weight(.semibold))
                        }
                    }
                    Menu {
                        Toggle("Ausgeblendete anzeigen", isOn: $showHidden)
                        Button("Alle wieder einblenden") { hidden = []; saveHidden() }.disabled(hidden.isEmpty)
                        Button { Task { await load() } } label: { Label("Aktualisieren", systemImage: "arrow.clockwise") }
                            .disabled(model.loading || app.session == nil)
                    } label: { Label("Mehr", systemImage: "ellipsis") }
                }
            }
            .refreshable { await load() }
            .task(id: app.supportedApplets) {
                loadHidden(); await load()
                if app.pendingTimetableFirstLesson { app.pendingTimetableFirstLesson = false; selected = lessons.first }
            }
        }
    }

    private func content(_ t: Timetable) -> some View {
        VStack(spacing: 0) {
            Picker("Tag", selection: $day) {
                ForEach(0..<plan.count, id: \.self) { i in
                    Text(Self.dayNames[i].prefix(2)).tag(i)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.bottom, 8)
            .glassEffect(.regular, in: .capsule)
            .padding(.horizontal)

            if model.isOffline { OfflineBanner(fetchedAt: model.fetchedAt, error: model.error).padding(.top, 8) }
            ScrollView {
                LazyVStack(spacing: 10) {
                    if lessons.isEmpty {
                        ContentUnavailableView("Frei", systemImage: "sun.max", description: Text("Keine Stunden am \(Self.dayNames[day])."))
                            .padding(.top, 40)
                    }
                    ForEach(lessons) { l in
                        LessonCard(lesson: l)
                            .opacity(hidden.contains(l.id) ? 0.45 : 1)
                            .contentShape(.rect)
                            .onTapGesture { selected = l }
                            .contextMenu {
                                if hidden.contains(l.id) {
                                    Button { hidden.remove(l.id); saveHidden() } label: { Label("Einblenden", systemImage: "eye") }
                                } else {
                                    Button(role: .destructive) { hidden.insert(l.id); saveHidden() } label: { Label("Ausblenden", systemImage: "eye.slash") }
                                }
                            }
                    }
                }
                .padding()
                .padding(.bottom, 80)
            }
            .scrollEdgeEffectStyle(.soft, for: .top)
        }
        .sensoryFeedback(.selection, trigger: day)
        .sheet(item: $selected) { l in
            LessonSheet(lesson: l, isHidden: hidden.contains(l.id)) {
                if hidden.contains(l.id) { hidden.remove(l.id) } else { hidden.insert(l.id) }
                saveHidden()
            }
            .presentationDetents([.height(300)])
            .presentationDragIndicator(.visible)
            .presentationBackground(.regularMaterial)
        }
    }

    private func load() async {
        await model.load(app: app) { try await TimetableParser().fetchHome(session: $0) }
    }

    private func openPendingLesson() {
        guard app.pendingTimetableFirstLesson, let first = lessons.first else { return }
        app.pendingTimetableFirstLesson = false
        selected = first
    }

    // Same settings key as the Flutter app (`hidden-lessons`, list of subject ids).
    private func loadHidden() {
        guard let id = app.activeAccountID else { hidden = []; return }
        hidden = Set(app.settings.get([String].self, accountID: id, key: "hidden-lessons") ?? [])
    }
    private func saveHidden() {
        guard let id = app.activeAccountID else { return }
        app.settings.set(Array(hidden), accountID: id, key: "hidden-lessons")
    }
}

/// Detail popover like the Flutter `student_timetable_item.dart` bottom sheet.
private struct LessonSheet: View {
    let lesson: TimetableSubject
    let isHidden: Bool
    let toggleHidden: () -> Void
    @Environment(\.dismiss) private var dismiss

    private var duration: String {
        let minutes = lesson.endTime.minutes - lesson.startTime.minutes
        if lesson.duration > 1 || minutes > 60 { return String(localized: "\(lesson.duration) Stunden") }
        return String(localized: "1 Stunde")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(alignment: .center) {
                Text(lesson.name ?? "–").font(.largeTitle.weight(.semibold))
                Spacer()
                Circle().fill(subjectColor(lesson.name)).frame(width: 28, height: 28)
                    .overlay(Circle().strokeBorder(.white.opacity(0.6), lineWidth: 1))
                Button {
                    toggleHidden(); dismiss()
                } label: {
                    Image(systemName: isHidden ? "eye" : "eye.slash").font(.title3)
                }
                .buttonStyle(.glass)
                .accessibilityLabel(isHidden ? "Einblenden" : "Ausblenden")
            }
            VStack(alignment: .leading, spacing: 14) {
                if let r = lesson.room, !r.isEmpty { detail("mappin.and.ellipse", r) }
                detail("clock", "\(lesson.startTime.formatted) – \(lesson.endTime.formatted) (\(duration))")
                if let t = lesson.teacher, !t.isEmpty { detail("person", t) }
                if let b = lesson.badge, !b.isEmpty { detail("calendar", String(localized: "\(b)-Woche")) }
                if isHidden { detail("eye.slash", String(localized: "Ausgeblendet")).foregroundStyle(.secondary) }
            }
            Spacer(minLength: 0)
        }
        .padding(24)
        .padding(.top, 8)
    }

    private func detail(_ symbol: String, _ text: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: symbol).font(.title3).frame(width: 28)
            Text(text).font(.body.weight(.medium))
        }
    }
}

/// Stable per-subject hue, like the Flutter `color_hash.dart`.
private func subjectColor(_ name: String?) -> Color {
    let h = (name ?? "").unicodeScalars.reduce(7) { ($0 &* 31 &+ Int($1.value)) & 0xFFFF }
    return Color(hue: Double(h % 360) / 360, saturation: 0.65, brightness: 0.85)
}

private struct LessonCard: View {
    let lesson: TimetableSubject
    var body: some View {
        HStack(spacing: 14) {
            VStack(spacing: 2) {
                Text(lesson.startTime.formatted).font(.subheadline.weight(.semibold).monospacedDigit())
                Text(lesson.endTime.formatted).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            .frame(width: 54)
            .padding(.vertical, 8)
            .glassEffect(.regular.tint(color.opacity(0.3)), in: .rect(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 3) {
                Text(lesson.name ?? "–").font(.headline)
                HStack(spacing: 12) {
                    if let r = lesson.room, !r.isEmpty { Label(r, systemImage: "door.left.hand.open") }
                    if let t = lesson.teacher, !t.isEmpty { Label(t, systemImage: "person") }
                }
                .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if let b = lesson.badge, !b.isEmpty {
                Text(b).font(.caption2.weight(.bold)).padding(.horizontal, 7).padding(.vertical, 3)
                    .glassEffect(.regular.tint(.accentColor), in: .capsule)
            }
            if lesson.duration > 1 {
                Text("\(lesson.duration)h").font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(.regularMaterial, in: .rect(cornerRadius: 16))
    }

    private var color: Color { subjectColor(lesson.name) }
}
