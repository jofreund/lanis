import Foundation

/// One substitution row. Field names follow the SPH JSON keys (see Dart `Substitution`).
public struct Substitution: Codable, Sendable, Hashable, Identifiable {
    public var id: String { "\(tag)|\(stunde)|\(klasse ?? "")|\(fach ?? "")|\(raum ?? "")|\(art ?? "")|\(hinweis ?? "")" }

    public let tag: String        // dd.MM.yyyy
    public let tagEN: String      // yyyy-MM-dd (AJAX) or dd_MM_yyyy (HTML path)
    public let stunde: String     // "1" or "1 - 2"
    public var vertreter, lehrer, klasse, klasseAlt, fach, fachAlt, raum, raumAlt, hinweis, hinweis2, art, lehrerKuerzel, vertreterKuerzel: String?
    public var hervorgehoben: [String]?

    public init(tag: String, tagEN: String, stunde: String, vertreter: String? = nil, lehrer: String? = nil,
                klasse: String? = nil, klasseAlt: String? = nil, fach: String? = nil, fachAlt: String? = nil,
                raum: String? = nil, raumAlt: String? = nil, hinweis: String? = nil, hinweis2: String? = nil,
                art: String? = nil, lehrerKuerzel: String? = nil, vertreterKuerzel: String? = nil, hervorgehoben: [String]? = nil) {
        self.tag = tag; self.tagEN = tagEN; self.stunde = stunde; self.vertreter = vertreter; self.lehrer = lehrer
        self.klasse = klasse; self.klasseAlt = klasseAlt; self.fach = fach; self.fachAlt = fachAlt; self.raum = raum
        self.raumAlt = raumAlt; self.hinweis = hinweis; self.hinweis2 = hinweis2; self.art = art
        self.lehrerKuerzel = lehrerKuerzel; self.vertreterKuerzel = vertreterKuerzel; self.hervorgehoben = hervorgehoben
    }
}

public struct SubstitutionInfo: Codable, Sendable, Hashable {
    public let header: String
    public var values: [String]
    public init(header: String, values: [String]) { self.header = header; self.values = values }
}

public struct SubstitutionDay: Codable, Sendable, Hashable, Identifiable {
    public var id: String { parsedDate }
    public let parsedDate: String  // dd.MM.yyyy
    public var substitutions: [Substitution]
    public var infos: [SubstitutionInfo]

    public init(parsedDate: String, substitutions: [Substitution] = [], infos: [SubstitutionInfo] = []) {
        self.parsedDate = parsedDate; self.substitutions = substitutions; self.infos = infos
    }

    public var date: Date {
        let parts = parsedDate.split(separator: ".").compactMap { Int($0) }
        guard parts.count == 3 else { return .distantPast }
        return Calendar.current.date(from: DateComponents(year: parts[2], month: parts[1], day: parts[0])) ?? .distantPast
    }

    public var isEmpty: Bool { substitutions.isEmpty && infos.isEmpty }
}

public struct SubstitutionPlan: Codable, Sendable, Hashable {
    public var days: [SubstitutionDay]
    public var lastUpdated: Date

    public init(days: [SubstitutionDay] = [], lastUpdated: Date = .now) {
        self.days = days; self.lastUpdated = lastUpdated
    }

    public mutating func add(_ day: SubstitutionDay) {
        days.append(day)
        days.sort { $0.date < $1.date }
    }

    public mutating func removeEmptyDays() { days.removeAll(where: \.isEmpty) }

    public var allSubstitutions: [Substitution] { days.flatMap(\.substitutions) }
}
