import SwiftUI
import LanisKit

struct LessonsView: View {
    @Environment(AppState.self) private var app
    @State private var model = AppletModel<[Lesson]>(applet: .lessons)
    @State private var path = NavigationPath()
    private var lessons: [Lesson] { model.value ?? [] }

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if !lessons.isEmpty {
                    List {
                        if model.isOffline { OfflineBanner(fetchedAt: model.fetchedAt, error: model.error).listRowBackground(Color.clear).listRowInsets(EdgeInsets()) }
                        ForEach(lessons) { lesson in
                            NavigationLink(value: lesson) { LessonRow(lesson: lesson) }
                        }
                    }
                    .listStyle(.insetGrouped)
                    .scrollEdgeEffectStyle(.soft, for: .top)
                    .navigationDestination(for: Lesson.self) { CourseDetailView(lesson: $0) }
                } else if model.loading {
                    ProgressView("Kursmappen laden …")
                } else if let error = model.error {
                    ContentUnavailableView("Fehler", systemImage: "exclamationmark.triangle", description: Text(error))
                } else if app.session == nil {
                    ContentUnavailableView("Nicht angemeldet", systemImage: "person.crop.circle.badge.questionmark")
                } else {
                    ContentUnavailableView("Keine Kursmappen", systemImage: "books.vertical")
                }
            }
            .navigationTitle("Mein Unterricht")
            .refreshable { await load() }
        }
        .task(id: app.dataToken) { await load(); openPendingCourse() }
        .onChange(of: app.pendingCourseID) { _, _ in openPendingCourse() }
    }

    private func load() async {
        await model.load(app: app) { try await LessonsStudentParser().fetchHome(session: $0) }
    }

    private func openPendingCourse() {
        guard let id = app.pendingCourseID,
              let lesson = lessons.first(where: { $0.courseID == id }) ?? lessons.first(where: { $0.name.caseInsensitiveCompare(id) == .orderedSame }) else { return }
        app.pendingCourseID = nil
        path.append(lesson)
    }
}

private struct LessonRow: View {
    let lesson: Lesson
    @Environment(SubjectColors.self) private var colors
    private var color: Color { colors.color(for: lesson.name) }
    var body: some View {
        HStack(spacing: 12) {
            Text(subjectCode(lesson.name))
                .font(.subheadline.weight(.bold))
                .minimumScaleFactor(0.6).lineLimit(1)
                .foregroundStyle(color.mix(with: .primary, by: 0.45))
                .frame(width: 42, height: 42)
                .background(color.opacity(0.22), in: .rect(cornerRadius: 11))
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(lesson.name).font(.headline)
                    Spacer()
                    if let hw = lesson.currentEntry?.homework, !hw.done {
                        Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.orange)
                    }
                }
                if let e = lesson.currentEntry {
                    HStack(spacing: 6) {
                        if let d = e.topicDate { Text(d, format: .dateTime.day().month()).foregroundStyle(.secondary) }
                        Text(e.topicTitle ?? "–").lineLimit(1)
                    }
                    .font(.subheadline)
                }
                HStack(spacing: 10) {
                    ForEach(lesson.teachers, id: \.self) { t in Label(t.kuerzel ?? "", systemImage: "person") }
                    if let f = lesson.currentEntry?.files.count, f > 0 { Label("\(f)", systemImage: "paperclip") }
                }
                .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

struct CourseDetailView: View {
    @Environment(AppState.self) private var app
    let lesson: Lesson
    @State private var detail: DetailedLesson?
    @State private var error: String?
    @State private var section: Section = .history
    @Environment(\.horizontalSizeClass) private var sizeClass

    enum Section: String, CaseIterable, Identifiable {
        case history = "Verlauf", marks = "Leistungen", exams = "Leistungskontrollen", attendance = "Anwesenheit"
        var id: String { rawValue }
        var symbol: String {
            switch self {
            case .history: "clock.arrow.circlepath"
            case .marks: "chart.bar"
            case .exams: "checkmark.seal"
            case .attendance: "person.crop.circle.badge.checkmark"
            }
        }
        /// Deep-link segment names (`lanis://student/lessons/<id>/exams`).
        init?(slug: String) {
            switch slug { case "history": self = .history; case "marks": self = .marks; case "exams": self = .exams; case "attendance": self = .attendance; default: return nil }
        }
    }

    var body: some View {
        Group {
            if let detail {
                VStack(spacing: 0) {
                    // "Leistungskontrollen" doesn't fit a quarter of a phone width, so compact widths
                    // show icons (full names stay as accessibility labels); regular widths show text.
                    Picker("Bereich", selection: $section) {
                        ForEach(Section.allCases) { s in
                            if sizeClass == .compact {
                                Image(systemName: s.symbol).accessibilityLabel(s.rawValue).tag(s)
                            } else {
                                Text(s.rawValue).tag(s)
                            }
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal).padding(.bottom, 8)
                    content(detail)
                }
            } else if let error {
                ContentUnavailableView("Fehler", systemImage: "exclamationmark.triangle", description: Text(error))
            } else {
                ProgressView("Kursmappe laden …")
            }
        }
        .navigationTitle(lesson.name)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if let slug = app.pendingCourseSection, let s = Section(slug: slug) { section = s; app.pendingCourseSection = nil }
            await load()
        }
    }

    @ViewBuilder private func content(_ d: DetailedLesson) -> some View {
        switch section {
        case .history:
            List(d.history) { entry in HistoryRow(entry: entry, courseID: d.courseID) }
                .listStyle(.insetGrouped)
        case .marks:
            List {
                if d.marks.isEmpty { ContentUnavailableView("Keine Leistungen", systemImage: "chart.bar") }
                ForEach(d.marks) { m in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack { Text(m.name); Spacer(); Text(m.mark).font(.headline.monospacedDigit()) }
                        Text(m.date).font(.caption).foregroundStyle(.secondary)
                        if let c = m.comment { Text(c).font(.caption) }
                    }
                }
            }
        case .exams:
            ExamsView(groups: d.exams, course: d.name)
        case .attendance:
            List {
                if d.attendances.isEmpty { ContentUnavailableView("Keine Daten", systemImage: "checkmark.circle") }
                ForEach(d.attendances.keys.sorted(), id: \.self) { k in LabeledContent(k, value: d.attendances[k] ?? "") }
            }
        }
    }

    private func load() async {
        guard let session = app.session else { return }
        do { detail = try await LessonsStudentParser().fetchDetail(session: session, coursePath: lesson.coursePath) }
        catch let e as LanisError { error = AppState.message(for: e) }
        catch { self.error = error.localizedDescription }
    }
}

/// Leistungskontrollen: hero card with countdown to the next exam, then grouped entries with date chips.
private struct ExamsView: View {
    let groups: [LessonExamGroup]
    let course: String

    private var today: Date { Calendar.current.startOfDay(for: .now) }
    private var upcoming: [LessonExamEntry] {
        let all = groups.flatMap(\.entries).filter { ($0.date ?? .distantPast) >= today }
        // Prefer the "Kommende" group's entries (they carry the hours); dedupe by date+kind.
        var seen = Set<String>()
        return all.sorted { ($0.date ?? .distantFuture) < ($1.date ?? .distantFuture) }
            .filter { seen.insert("\($0.date?.timeIntervalSince1970 ?? 0)|\($0.kind)").inserted }
    }

    /// SPH's "Alle" list repeats "Kommende" until exams are in the past; drop groups that add nothing.
    private var visibleGroups: [LessonExamGroup] {
        func key(_ e: LessonExamEntry) -> String { "\(e.date?.timeIntervalSince1970 ?? 0)|\(e.kind)" }
        return groups.filter { g in
            !groups.contains { other in other.id != g.id && other.entries.count >= g.entries.count && Set(g.entries.map(key)).isSubset(of: Set(other.entries.map(key))) && (other.entries.count > g.entries.count || other.name.hasPrefix("Kommende")) }
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if let next = upcoming.first, let date = next.date {
                    NextExamCard(entry: next, date: date, course: course, countAfter: max(0, upcoming.count - 1))
                } else if groups.isEmpty {
                    ContentUnavailableView("Keine Leistungskontrollen", systemImage: "checkmark.seal", description: Text("Für diesen Kurs sind keine Leistungskontrollen eingetragen."))
                }
                ForEach(visibleGroups) { group in
                    VStack(alignment: .leading, spacing: 8) {
                        Label(group.name.replacingOccurrences(of: "Leistungskontrolle(n)", with: "Leistungskontrollen"), systemImage: group.name.hasPrefix("Kommende") ? "calendar.badge.clock" : "list.bullet.rectangle")
                            .font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                            .padding(.horizontal, 4)
                        VStack(spacing: 0) {
                            ForEach(Array(group.entries.enumerated()), id: \.element.id) { i, e in
                                ExamRow(entry: e, isPast: (e.date ?? .distantFuture) < today)
                                if i < group.entries.count - 1 { Divider().padding(.leading, 70) }
                            }
                            if group.entries.isEmpty { Text("Keine Einträge").font(.subheadline).foregroundStyle(.secondary).padding() }
                        }
                        .background(.regularMaterial, in: .rect(cornerRadius: 18))
                    }
                }
            }
            .padding()
            .padding(.bottom, 80)
        }
        .scrollEdgeEffectStyle(.soft, for: .top)
    }
}

private struct NextExamCard: View {
    let entry: LessonExamEntry
    let date: Date
    let course: String
    let countAfter: Int

    private var days: Int { Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: .now), to: date).day ?? 0 }
    private var tint: Color { days <= 3 ? .red : days <= 10 ? .orange : .accentColor }
    private var countdown: String {
        switch days { case 0: String(localized: "Heute"); case 1: String(localized: "Morgen"); default: String(localized: "in \(days) Tagen") }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Label("Nächste Leistungskontrolle", systemImage: "pencil.and.ruler").font(.caption.weight(.semibold)).textCase(.uppercase).foregroundStyle(.secondary)
                Spacer()
                Text(countdown).font(.caption.weight(.bold)).padding(.horizontal, 8).padding(.vertical, 4)
                    .glassEffect(.regular.tint(tint).interactive(false), in: .capsule)
            }
            HStack(spacing: 14) {
                VStack(spacing: 0) {
                    Text(date, format: .dateTime.day()).font(.system(size: 38, weight: .bold, design: .rounded).monospacedDigit())
                    Text(date, format: .dateTime.month(.abbreviated)).font(.caption.weight(.semibold)).textCase(.uppercase).foregroundStyle(.secondary)
                }
                .frame(width: 72)
                .padding(.vertical, 6)
                .glassEffect(.regular.tint(tint.opacity(0.35)), in: .rect(cornerRadius: 16))
                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.kind).font(.title2.weight(.semibold))
                    Text(course).font(.subheadline).foregroundStyle(.secondary)
                    HStack(spacing: 12) {
                        Label(date.formatted(.dateTime.weekday(.wide)), systemImage: "calendar")
                        if let h = entry.hours { Label(h, systemImage: "clock") }
                    }
                    .font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            if countAfter > 0 {
                Text("Danach noch \(countAfter) weitere").font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .glassEffect(.regular.tint(tint.opacity(0.12)), in: .rect(cornerRadius: 22))
    }
}

private struct ExamRow: View {
    let entry: LessonExamEntry
    let isPast: Bool

    var body: some View {
        HStack(spacing: 14) {
            VStack(spacing: 0) {
                if let d = entry.date {
                    Text(d, format: .dateTime.day()).font(.headline.monospacedDigit())
                    Text(d, format: .dateTime.month(.abbreviated)).font(.caption2).foregroundStyle(.secondary)
                } else {
                    Image(systemName: "questionmark").font(.headline)
                }
            }
            .frame(width: 44)
            .padding(.vertical, 6)
            .background(isPast ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.tint.opacity(0.15)), in: .rect(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.kind).font(.body.weight(.medium))
                if let d = entry.date {
                    Text(d.formatted(.dateTime.weekday(.wide).day().month(.wide).year())).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if let h = entry.hours {
                Text(h).font(.caption.weight(.medium)).padding(.horizontal, 8).padding(.vertical, 4)
                    .background(.thinMaterial, in: .capsule)
            }
            if isPast { Image(systemName: "checkmark.circle.fill").foregroundStyle(.green) }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .opacity(isPast ? 0.6 : 1)
    }
}

private struct HistoryRow: View {
    @Environment(AppState.self) private var app
    @State var entry: LessonEntry
    let courseID: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                if let d = entry.topicDate { Text(d, format: .dateTime.weekday(.abbreviated).day().month()).font(.subheadline.weight(.semibold)) }
                if let h = entry.schoolHours { Text("· \(h) Std").font(.subheadline).foregroundStyle(.secondary) }
                Spacer()
                if let p = entry.presence {
                    let tint: Color = p.lowercased().contains("anwesend") ? .green : .red
                    Text(p).font(.caption.weight(.semibold))
                        .foregroundStyle(tint.mix(with: .primary, by: 0.35))
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(tint.opacity(0.16), in: .capsule)
                }
            }
            if let t = entry.topicTitle { Text(t).font(.body.weight(.medium)) }
            if let desc = entry.description, !desc.isEmpty { Text(desc).font(.subheadline) }
            if let hw = entry.homework {
                Button {
                    Task { await toggleHomework(!hw.done) }
                } label: {
                    Label { Text(hw.description).strikethrough(hw.done).foregroundStyle(hw.done ? .secondary : .primary) }
                    icon: { Image(systemName: hw.done ? "checkmark.circle.fill" : "circle").foregroundStyle(hw.done ? .green : .orange) }
                    .font(.subheadline)
                }
                .buttonStyle(.plain)
            }
            if !entry.files.isEmpty {
                HStack(spacing: 8) {
                    ForEach(entry.files) { f in
                        if let url = f.url { Link(destination: url) { Label(f.name ?? "Datei", systemImage: "paperclip").font(.caption) } }
                    }
                }
            }
            ForEach(entry.uploads) { u in
                Label("\(u.name) · \(u.status == .open ? "offen" : "geschlossen")\(u.deadline.map { " · bis \($0)" } ?? "")", systemImage: "tray.and.arrow.up")
                    .font(.caption).foregroundStyle(u.status == .open ? .orange : .secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private func toggleHomework(_ done: Bool) async {
        guard let session = app.session else { return }
        if (try? await LessonsStudentParser().setHomework(session: session, courseID: courseID, entryID: entry.entryID, done: done)) == true {
            entry.homework?.done = done
        }
    }
}
