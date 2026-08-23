import SwiftUI
import LanisKit

struct SubstitutionsView: View {
    @Environment(AppState.self) private var app
    @State private var model = AppletModel<SubstitutionPlan>(applet: .substitutions)
    private var plan: SubstitutionPlan? { model.value }

    var body: some View {
        NavigationStack {
            Group {
                if let plan, !plan.days.isEmpty {
                    planList(plan)
                } else if model.loading {
                    ProgressView("Vertretungsplan laden …")
                } else if let error = model.error {
                    ContentUnavailableView("Fehler", systemImage: "exclamationmark.triangle", description: Text(error))
                } else if app.session == nil {
                    ContentUnavailableView("Nicht angemeldet", systemImage: "person.crop.circle.badge.questionmark",
                                           description: Text("Melde dich an, um den Vertretungsplan zu sehen."))
                } else {
                    ContentUnavailableView("Keine Vertretungen", systemImage: "checkmark.seal",
                                           description: Text("Aktuell liegen keine Einträge vor."))
                }
            }
            .navigationTitle("Vertretungen")
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    Button {} label: { Label("Filter", systemImage: "line.3.horizontal.decrease.circle") }
                        .disabled(true) // Phase 2: port substitutions_filter_settings.dart
                }
            }
            .refreshable { await load() }
        }
        .task(id: app.dataToken) { await load() }
    }

    private func planList(_ plan: SubstitutionPlan) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14, pinnedViews: .sectionHeaders) {
                if model.isOffline { OfflineBanner(fetchedAt: model.fetchedAt, error: model.error).padding(.horizontal, -16) }
                ForEach(plan.days) { day in
                    Section {
                        if !day.infos.isEmpty { InfoCard(infos: day.infos) }
                        ForEach(day.substitutions) { s in SubstitutionRow(s) }
                    } header: {
                        DayHeader(day: day)
                    }
                }
                Text("Stand: \(plan.lastUpdated.formatted(date: .numeric, time: .shortened))")
                    .font(.footnote).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity).padding(.top, 8)
            }
            .padding(.horizontal)
            .padding(.bottom, 80)
        }
        .scrollEdgeEffectStyle(.soft, for: .top)
    }

    private func load() async {
        await model.load(app: app) { try await SubstitutionsParser().fetchHome(session: $0) }
    }
}

private struct DayHeader: View {
    let day: SubstitutionDay
    var body: some View {
        HStack {
            Text(day.date, format: .dateTime.weekday(.wide).day().month(.wide))
                .font(.headline)
            Spacer()
            Text("\(day.substitutions.count)")
                .font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
        }
        .glassCard()
        .padding(.vertical, 4)
    }
}

private struct InfoCard: View {
    let infos: [SubstitutionInfo]
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(infos, id: \.self) { info in
                Label(info.header, systemImage: "info.circle").font(.subheadline.weight(.semibold))
                ForEach(info.values, id: \.self) { v in
                    Text(stripTags(v)).font(.subheadline)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(.thinMaterial, in: .rect(cornerRadius: 16))
    }
    private func stripTags(_ s: String) -> String {
        s.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
    }
}

private struct SubstitutionRow: View {
    let s: Substitution
    init(_ s: Substitution) { self.s = s }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Text(s.stunde)
                .font(.title3.weight(.bold).monospacedDigit())
                .frame(minWidth: 44)
                .padding(.vertical, 6)
                .glassEffect(.regular.tint(accent.opacity(0.35)), in: .rect(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    if let klasse = s.klasse { Text(klasse).font(.headline) }
                    if let fach = s.fach { Text(fach).font(.headline) }
                    if let alt = s.fachAlt, alt != s.fach {
                        Text(alt).font(.subheadline).strikethrough().foregroundStyle(.secondary)
                    }
                }
                if let art = s.art {
                    Text(art).font(.subheadline.weight(.medium)).foregroundStyle(accent)
                }
                HStack(spacing: 12) {
                    if let raum = s.raum { Label(raum, systemImage: "door.left.hand.open") }
                    if let v = s.vertreter ?? s.vertreterKuerzel { Label(v, systemImage: "person") }
                    if let l = s.lehrer ?? s.lehrerKuerzel, l != s.vertreter { Label(l, systemImage: "person.slash").foregroundStyle(.secondary) }
                }
                .font(.caption).labelStyle(.titleAndIcon)
                if let h = s.hinweis, !h.isEmpty {
                    Text(h).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(.regularMaterial, in: .rect(cornerRadius: 16))
    }

    private var accent: Color {
        switch (s.art ?? "").lowercased() {
        case let a where a.contains("entfall") || a.contains("ausfall"): .red
        case let a where a.contains("vertretung"): .orange
        case let a where a.contains("raum"): .blue
        default: .accentColor
        }
    }
}
