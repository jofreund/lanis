import SwiftUI
import LanisKit

struct CalendarView: View {
    @Environment(AppState.self) private var app
    @State private var model = AppletModel<[CalendarEvent]>(applet: .calendar)
    @State private var query = ""
    @State private var selected: CalendarEvent?
    @State private var period: PeriodMode = .month
    private var events: [CalendarEvent] { model.value ?? [] }

    enum PeriodMode: String, CaseIterable {
        case month, week
        var label: LocalizedStringKey { self == .month ? "Monat" : "Woche" }
    }

    /// School weeks run Mon–Sun regardless of the device locale's first weekday.
    private static let weekCalendar: Calendar = {
        var c = Calendar(identifier: .iso8601)
        c.timeZone = .current
        return c
    }()
    private var groupingCalendar: Calendar { period == .month ? Calendar.current : Self.weekCalendar }

    private var upcoming: [(period: Date, events: [CalendarEvent])] {
        let q = query.trimmingCharacters(in: .whitespaces)
        let cutoff = Calendar.current.startOfDay(for: .now)
        let filtered = events
            .filter { q.isEmpty ? $0.endTime >= cutoff : $0.title.localizedCaseInsensitiveContains(q) || $0.description.localizedCaseInsensitiveContains(q) }
            .sorted { $0.startTime < $1.startTime }
        let unit: Calendar.Component = period == .month ? .month : .weekOfYear
        let cal = groupingCalendar
        let grouped = Dictionary(grouping: filtered) { cal.dateInterval(of: unit, for: $0.startTime)?.start ?? .distantPast }
        return grouped.keys.sorted().map { ($0, grouped[$0]!) }
    }

    private func periodTitle(_ start: Date) -> String {
        guard period == .week else { return start.formatted(.dateTime.month(.wide).year()) }
        let cal = Self.weekCalendar
        let end = cal.date(byAdding: .day, value: 6, to: start) ?? start
        let span = "\(start.formatted(.dateTime.day().month(.abbreviated))) – \(end.formatted(.dateTime.day().month(.abbreviated)))"
        return String(localized: "KW \(cal.component(.weekOfYear, from: start)) · \(span)")
    }

    var body: some View {
        NavigationStack {
            Group {
                if model.loading && events.isEmpty {
                    ProgressView("Kalender laden …")
                } else if let error = model.error, events.isEmpty {
                    ContentUnavailableView("Fehler", systemImage: "exclamationmark.triangle", description: Text(error))
                } else if app.session == nil {
                    ContentUnavailableView("Nicht angemeldet", systemImage: "person.crop.circle.badge.questionmark")
                } else if upcoming.isEmpty {
                    ContentUnavailableView.search(text: query)
                } else {
                    list
                }
            }
            .navigationTitle("Kalender")
            .searchable(text: $query, prompt: "Termine suchen")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { Task { await load() } } label: { Label("Aktualisieren", systemImage: "arrow.clockwise") }
                        .disabled(model.loading || app.session == nil)
                }
            }
            .refreshable { await load() }
        }
        // Lifecycle modifiers live on the stable NavigationStack: inside the `Group` above they
        // would be re-created (and their tasks cancelled) whenever the branch switches.
        .task(id: app.supportedApplets) { await load() }
        .onChange(of: app.pendingCalendarFirstEvent) { _, _ in openPendingEvent() }
        .onChange(of: events.count) { _, _ in openPendingEvent() }
        .sheet(item: $selected) { EventSheet(event: $0) }
    }

    private var list: some View {
        VStack(spacing: 0) {
            Picker("Ansicht", selection: $period) {
                ForEach(PeriodMode.allCases, id: \.self) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.bottom, 8)

            List {
                if model.isOffline { OfflineBanner(fetchedAt: model.fetchedAt, error: model.error).listRowBackground(Color.clear).listRowInsets(EdgeInsets()) }
                ForEach(upcoming, id: \.period) { group in
                    Section(periodTitle(group.period)) {
                        ForEach(group.events) { e in
                            Button { selected = e } label: { EventRow(event: e) }.tint(.primary)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollEdgeEffectStyle(.soft, for: .top)
        }
    }

    private func load() async {
        await model.load(app: app) { try await CalendarParser().fetchHome(session: $0) }
    }

    private func openPendingEvent() {
        DebugTrace.log("calendar openPendingEvent flag=\(app.pendingCalendarFirstEvent) events=\(events.count) upcoming=\(upcoming.count)")
        guard app.pendingCalendarFirstEvent, let first = upcoming.first?.events.first else { return }
        app.pendingCalendarFirstEvent = false
        selected = first
    }
}

private struct EventRow: View {
    let event: CalendarEvent
    var body: some View {
        HStack(spacing: 12) {
            VStack(spacing: 0) {
                Text(event.startTime, format: .dateTime.day()).font(.title3.weight(.bold).monospacedDigit())
                Text(event.startTime, format: .dateTime.weekday(.abbreviated)).font(.caption2).foregroundStyle(.secondary)
            }
            .frame(width: 40)
            RoundedRectangle(cornerRadius: 2).fill(Color(argb: event.colorARGB)).frame(width: 4, height: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(event.title).font(.body.weight(.medium)).lineLimit(2)
                Text(timeText).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if event.isNew { Text("Neu").font(.caption2.weight(.bold)).padding(.horizontal, 6).padding(.vertical, 2).glassEffect(.regular.tint(.accentColor), in: .capsule) }
        }
    }
    private var timeText: String {
        if event.allDay {
            let days = Calendar.current.dateComponents([.day], from: event.startTime, to: event.endTime).day ?? 0
            return days > 1 ? String(localized: "Ganztägig · \(days) Tage") : String(localized: "Ganztägig")
        }
        return "\(event.startTime.formatted(date: .omitted, time: .shortened)) – \(event.endTime.formatted(date: .omitted, time: .shortened))"
    }
}

private struct EventSheet: View {
    let event: CalendarEvent
    @Environment(\.dismiss) private var dismiss

    private var description: String {
        event.description
            .replacingOccurrences(of: "<br\\s*/?>|</p>|</li>", with: "\n", options: .regularExpression)
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
    /// SPH all-day end is exclusive; show the last day inclusive.
    private var lastDay: Date { event.allDay ? (Calendar.current.date(byAdding: .day, value: -1, to: event.endTime) ?? event.endTime) : event.endTime }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if event.allDay {
                        LabeledContent("Beginn", value: event.startTime.formatted(date: .complete, time: .omitted))
                        if !Calendar.current.isDate(event.startTime, inSameDayAs: lastDay) {
                            LabeledContent("Ende", value: lastDay.formatted(date: .complete, time: .omitted))
                        }
                        LabeledContent("Dauer", value: "Ganztägig")
                    } else {
                        LabeledContent("Beginn", value: event.startTime.formatted(date: .abbreviated, time: .shortened))
                        LabeledContent("Ende", value: event.endTime.formatted(date: .abbreviated, time: .shortened))
                    }
                    if let place = event.place, !place.isEmpty { LabeledContent("Ort", value: place) }
                    if let c = event.category {
                        LabeledContent("Kategorie") {
                            HStack(spacing: 8) {
                                Circle().fill(Color(argb: c.colorARGB)).frame(width: 10, height: 10)
                                Text(c.name)
                            }
                        }
                    }
                }
                if !description.isEmpty {
                    Section("Beschreibung") {
                        Text(description).textSelection(.enabled)
                    }
                }
                if let m = event.lastModified {
                    Section {
                        LabeledContent("Zuletzt geändert", value: m.formatted(date: .numeric, time: .shortened))
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle(event.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(role: .close) { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

extension Color {
    init(argb: UInt32) {
        self.init(red: Double((argb >> 16) & 0xFF) / 255, green: Double((argb >> 8) & 0xFF) / 255,
                  blue: Double(argb & 0xFF) / 255, opacity: Double((argb >> 24) & 0xFF) / 255)
    }
}
