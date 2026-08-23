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
    @State private var mode: ViewMode = .day
    @State private var selectedGroup: LessonGroup?
    @State private var block = TimetableView.todayIndex >= 2 ? 1 : 0
    private var timetable: Timetable? { model.value }

    enum ViewMode: String, CaseIterable { case day, threeDays }
    struct LessonGroup: Identifiable { let lessons: [TimetableSubject]; var id: String { lessons.map(\.id).joined(separator: "|") } }

    private static var todayIndex: Int {
        let wd = Calendar.current.component(.weekday, from: .now) // 1 = Sunday
        return min(max(wd - 2, 0), 4)
    }
    private static let dayNames = ["Montag", "Dienstag", "Mittwoch", "Donnerstag", "Freitag", "Samstag", "Sonntag"]

    private var plan: [TimetableDay] {
        guard let t = timetable else { return [] }
        return (useOwn ? t.planForOwn : nil) ?? t.planForAll
    }
    private var lessons: [TimetableSubject] { lessons(for: day) }
    private func lessons(for index: Int) -> [TimetableSubject] {
        guard let t = timetable, index < plan.count else { return [] }
        return plan[index].filter { t.isCurrentWeek($0, sameWeek: thisWeek) && (showHidden || !hidden.contains($0.id)) }.sorted { $0.startTime < $1.startTime }
    }
    /// The two selectable blocks in 3-day mode: the first three days of the week and the last three.
    private var blockRanges: [[Int]] {
        guard !plan.isEmpty else { return [] }
        let last = max(plan.count - 3, 0)
        let first = Array(0..<min(3, plan.count))
        guard last > 0 else { return [first] }
        return [first, Array(last..<plan.count)]
    }
    private func blockLabel(_ days: [Int]) -> String {
        guard let f = days.first, let l = days.last else { return "" }
        return "\(Self.dayNames[f].prefix(2))–\(Self.dayNames[l].prefix(2))"
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
                    Button {
                        if mode == .day, let i = blockRanges.lastIndex(where: { $0.contains(day) }) { block = i }
                        mode = mode == .day ? .threeDays : .day
                    } label: {
                        Label(mode == .day ? "3 Tage" : "Ein Tag", systemImage: mode == .day ? "rectangle.split.3x1" : "rectangle")
                    }
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
            .task(id: app.dataToken) {
                loadHidden(); await load()
                if app.pendingTimetableFirstLesson { app.pendingTimetableFirstLesson = false; selected = lessons.first }
            }
        }
    }

    private func content(_ t: Timetable) -> some View {
        VStack(spacing: 0) {
            Group {
                if mode == .threeDays {
                    Picker("Zeitraum", selection: $block) {
                        ForEach(Array(blockRanges.enumerated()), id: \.offset) { i, days in
                            Text(blockLabel(days)).tag(i)
                        }
                    }
                } else {
                    Picker("Tag", selection: $day) {
                        ForEach(0..<plan.count, id: \.self) { i in
                            Text(Self.dayNames[i].prefix(2)).tag(i)
                        }
                    }
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.bottom, 8)

            if model.isOffline { OfflineBanner(fetchedAt: model.fetchedAt, error: model.error).padding(.top, 8) }
            if mode == .threeDays {
                TabView(selection: $block) {
                    ForEach(Array(blockRanges.enumerated()), id: \.offset) { i, days in
                        threeDayGrid(t, days: days).tag(i)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
            } else {
                TabView(selection: $day) {
                    ForEach(0..<plan.count, id: \.self) { i in
                        dayList(i).tag(i)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
            }
        }
        .onChange(of: plan.count, initial: true) { _, n in
            if day >= n { day = max(n - 1, 0) }
            if block >= blockRanges.count { block = max(blockRanges.count - 1, 0) }
        }
        .sensoryFeedback(.selection, trigger: day)
        .sensoryFeedback(.selection, trigger: block)
        .sensoryFeedback(.selection, trigger: mode)
        .sheet(item: $selected) { l in
            LessonSheet(lesson: l, isHidden: hidden.contains(l.id)) {
                if hidden.contains(l.id) { hidden.remove(l.id) } else { hidden.insert(l.id) }
                saveHidden()
            }
            .presentationDetents([.height(300)])
            .presentationDragIndicator(.visible)
            .presentationBackground(.regularMaterial)
        }
        .sheet(item: $selectedGroup) { g in
            ParallelSheet(lessons: g.lessons, hidden: hidden) { l in
                if hidden.contains(l.id) { hidden.remove(l.id) } else { hidden.insert(l.id) }
                saveHidden()
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
            .presentationBackground(.regularMaterial)
        }
    }

    private func dayList(_ index: Int) -> some View {
        let items = lessons(for: index)
        return ScrollView {
            LazyVStack(spacing: 10) {
                if items.isEmpty {
                    ContentUnavailableView("Frei", systemImage: "sun.max", description: Text("Keine Stunden am \(Self.dayNames[index])."))
                        .padding(.top, 40)
                }
                ForEach(items) { l in
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

    // MARK: - 3-day grid

    private static let hourHeight: CGFloat = 76
    private static let axisWidth: CGFloat = 36

    private func threeDayGrid(_ t: Timetable, days: [Int]) -> some View {
        // Span the whole week so both blocks keep the same scale while swiping.
        let shown = (0..<plan.count).flatMap { lessons(for: $0) }
        let slotStart = t.hours.map(\.startTime.minutes).min() ?? 8 * 60
        let slotEnd = t.hours.map(\.endTime.minutes).max() ?? 16 * 60
        let start = min(slotStart, shown.map(\.startTime.minutes).min() ?? slotStart)
        let end = max(slotEnd, shown.map(\.endTime.minutes).max() ?? slotEnd)
        let totalHeight = CGFloat(end - start) / 60 * Self.hourHeight

        return VStack(spacing: 0) {
            HStack(spacing: 6) {
                Spacer().frame(width: Self.axisWidth)
                ForEach(days, id: \.self) { i in
                    Text(Self.dayNames[i])
                        .font(.subheadline.weight(i == Self.todayIndex ? .bold : .semibold))
                        .foregroundStyle(i == Self.todayIndex ? Color.accentColor : .primary)
                        .frame(maxWidth: .infinity)
                        .lineLimit(1).minimumScaleFactor(0.7)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .padding(.leading, 8).padding(.trailing)
            .padding(.bottom, 6)

            ScrollView {
                HStack(alignment: .top, spacing: 6) {
                    timeAxis(start: start, end: end)
                    ForEach(days, id: \.self) { i in
                        dayColumn(lessons(for: i), start: start)
                            .frame(maxWidth: .infinity)
                    }
                }
                .frame(height: totalHeight)
                .padding(.leading, 8).padding(.trailing)
                .padding(.vertical, 8)
                .padding(.bottom, 80)
            }
            .scrollEdgeEffectStyle(.soft, for: .top)
        }
    }

    private func timeAxis(start: Int, end: Int) -> some View {
        let firstHour = Int(ceil(Double(start) / 60))
        let lastHour = end / 60
        return ZStack(alignment: .topLeading) {
            ForEach(Array(stride(from: firstHour, through: lastHour, by: 1)), id: \.self) { h in
                Text(String(format: "%02d:00", h))
                    .font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                    .frame(width: Self.axisWidth, alignment: .trailing)
                    .offset(y: CGFloat(h * 60 - start) / 60 * Self.hourHeight - 6)
            }
        }
        .frame(width: Self.axisWidth, alignment: .topLeading)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    /// A set of lessons that overlap in time (parallel courses) and are shown as one cell.
    private struct Cluster: Identifiable {
        let lessons: [TimetableSubject]
        var id: String { lessons.map(\.id).joined(separator: "|") }
        var start: TimeOfDay { lessons.map(\.startTime).min()! }
        var end: TimeOfDay { lessons.map(\.endTime).max()! }
    }
    private func cluster(_ lessons: [TimetableSubject]) -> [Cluster] {
        var out: [Cluster] = []
        var current: [TimetableSubject] = []
        var currentEnd = Int.min
        for l in lessons.sorted(by: { ($0.startTime, $0.endTime) < ($1.startTime, $1.endTime) }) {
            if l.startTime.minutes >= currentEnd, !current.isEmpty { out.append(Cluster(lessons: current)); current = [] }
            current.append(l)
            currentEnd = max(currentEnd, l.endTime.minutes)
        }
        if !current.isEmpty { out.append(Cluster(lessons: current)) }
        return out
    }

    private func dayColumn(_ lessons: [TimetableSubject], start: Int) -> some View {
        ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: 12).fill(.quaternary.opacity(0.35))
            ForEach(cluster(lessons)) { c in
                let top = CGFloat(c.start.minutes - start) / 60 * Self.hourHeight
                let height = max(CGFloat(c.end.minutes - c.start.minutes) / 60 * Self.hourHeight - 3, 22)
                Group {
                    if c.lessons.count == 1, let l = c.lessons.first {
                        GridLessonCell(lesson: l)
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
                    } else {
                        ParallelCell(lessons: c.lessons)
                            .contentShape(.rect)
                            .onTapGesture { selectedGroup = LessonGroup(lessons: c.lessons) }
                    }
                }
                .frame(height: height)
                .offset(y: top)
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
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
    @Environment(SubjectColors.self) private var colors

    private var colorBinding: Binding<Color> {
        Binding(get: { colors.color(for: lesson.name) },
                set: { colors.setColor($0, for: lesson.name) })
    }

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
                colorRow
                if isHidden { detail("eye.slash", String(localized: "Ausgeblendet")).foregroundStyle(.secondary) }
            }
            Spacer(minLength: 0)
        }
        .padding(24)
        .padding(.top, 8)
    }

    /// Colour override for the whole subject (`D 06G1` and `D` share one entry), not just this slot.
    private var colorRow: some View {
        HStack(spacing: 14) {
            Image(systemName: "paintpalette").font(.title3).frame(width: 28)
            Text("Farbe").font(.body.weight(.medium))
            Spacer()
            if colors.hasCustomColor(for: lesson.name) {
                Button("Zurücksetzen") { colors.setColor(nil, for: lesson.name) }
                    .font(.subheadline).buttonStyle(.borderless)
            }
            ColorPicker("Farbe", selection: colorBinding, supportsOpacity: false).labelsHidden()
        }
    }

    private func detail(_ symbol: String, _ text: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: symbol).font(.title3).frame(width: 28)
            Text(text).font(.body.weight(.medium))
        }
    }
}

/// Cell for several courses running in parallel (e.g. the class plan's elective groups).
private struct ParallelCell: View {
    let lessons: [TimetableSubject]
    private var names: [String] {
        var seen = Set<String>(), out: [String] = []
        for n in lessons.compactMap(\.name) where seen.insert(n).inserted { out.append(n) }
        return out
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: "square.stack.3d.up").font(.caption2)
                Text("\(lessons.count) Kurse").font(.caption.weight(.semibold))
            }
            Text(names.joined(separator: ", ")).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
            Spacer(minLength: 0)
        }
        .padding(6).padding(.leading, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.fill.secondary, in: .rect(cornerRadius: 8))
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 2).fill(.secondary).frame(width: 3).padding(.vertical, 4).padding(.leading, 2)
        }
        .clipped()
    }
}

/// Lists all parallel courses; tapping one pushes its detail inside the same sheet.
private struct ParallelSheet: View {
    let lessons: [TimetableSubject]
    let hidden: Set<String>
    let toggleHidden: (TimetableSubject) -> Void
    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(lessons) { l in
                        NavigationLink(value: l) {
                            LessonCard(lesson: l).opacity(hidden.contains(l.id) ? 0.45 : 1)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding()
            }
            .navigationTitle("\(lessons.count) parallele Kurse")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: TimetableSubject.self) { l in
                LessonSheet(lesson: l, isHidden: hidden.contains(l.id)) { toggleHidden(l) }
                    .navigationBarTitleDisplayMode(.inline)
            }
        }
    }
}

/// Compact block used in the 3-day grid; sized by lesson duration.
private struct GridLessonCell: View {
    let lesson: TimetableSubject
    @Environment(SubjectColors.self) private var colors
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(lesson.name ?? "–").font(.caption.weight(.semibold)).lineLimit(2)
            if let r = lesson.room, !r.isEmpty {
                Text(r).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(6)
        .padding(.leading, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(colors.color(for: lesson.name).opacity(0.22), in: .rect(cornerRadius: 8))
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 2).fill(colors.color(for: lesson.name)).frame(width: 3).padding(.vertical, 4).padding(.leading, 2)
        }
        .clipped()
    }
}

private struct LessonCard: View {
    let lesson: TimetableSubject
    @Environment(SubjectColors.self) private var colors
    var body: some View {
        // The time sits in a gutter and the lesson itself is a tinted block with a solid
        // colour bar — the same language as the 3-day grid, laid out as a row.
        HStack(spacing: 12) {
            VStack(spacing: 0) {
                Text(lesson.startTime.formatted).font(.subheadline.weight(.semibold).monospacedDigit())
                Text(lesson.endTime.formatted).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            .frame(width: 54)

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(lesson.name ?? "–").font(.headline)
                    HStack(spacing: 12) {
                        if let r = lesson.room, !r.isEmpty { Label(r, systemImage: "door.left.hand.open") }
                        if let t = lesson.teacher, !t.isEmpty { Label(t, systemImage: "person") }
                    }
                    .font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                if let b = lesson.badge, !b.isEmpty {
                    Text(b).font(.caption2.weight(.bold)).padding(.horizontal, 7).padding(.vertical, 3)
                        .glassEffect(.regular.tint(.accentColor), in: .capsule)
                }
                if lesson.duration > 1 {
                    Text("\(lesson.duration)h").font(.caption2).foregroundStyle(.secondary)
                }
            }
            .padding(10)
            .padding(.leading, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(color.opacity(0.22), in: .rect(cornerRadius: 12))
            .overlay(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 4).padding(.vertical, 6).padding(.leading, 3)
            }
            .clipped()
        }
    }

    private var color: Color { colors.color(for: lesson.name) }
}
