import SwiftUI
import UIKit
import LanisKit

/// Stable per-subject hue, like the Flutter `color_hash.dart`.
///
/// Hashes the canonical subject key so the same course keeps its colour across applets
/// (see `subjectKey`).
func defaultSubjectColor(_ name: String?) -> Color {
    let h = subjectKey(name).unicodeScalars.reduce(7) { ($0 &* 31 &+ Int($1.value)) & 0xFFFF }
    return Color(hue: Double(h % 360) / 360, saturation: 0.65, brightness: 0.85)
}

/// The leading subject token of a course name (`"D 06G1"` → `"D"`), used as a badge label.
func subjectCode(_ name: String?) -> String {
    let token = leadingToken(name)
    if token.isEmpty { return "–" }
    return token.count > 4 ? String(token.prefix(4)) : token
}

/// Canonical colour key for a course name.
///
/// The applets name the same course differently: the timetable carries the school's
/// abbreviation (`M`, `Spo`, `PoWi`), the course folders the written-out subject plus a group
/// (`Mathematik 10a`, `GEO 06/1`). Hashing the raw name would give one course two colours, so
/// the leading token is folded (diacritics, case, trailing group digits) and looked up in
/// `subjectAliases`. Unknown subjects fall back to the folded token, i.e. the previous
/// behaviour — abbreviation and long form only share a colour if the table knows the pair.
func subjectKey(_ name: String?) -> String {
    let folded = leadingToken(name)
        .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "de"))
        .replacingOccurrences(of: "ß", with: "ss")
    // Cut at the first non-letter so `M2`, `D06G1` and `PoWi-GK` reduce to the subject itself.
    let letters = String(folded.prefix { $0.isLetter })
    return subjectAliases[letters] ?? (letters.isEmpty ? "–" : letters)
}

/// First whitespace/dash-separated token of a course name.
private func leadingToken(_ name: String?) -> String {
    guard let name else { return "" }
    let token = name.split(whereSeparator: { $0 == " " || $0 == "-" }).first.map(String.init) ?? name
    return token
}

/// Abbreviation → canonical subject, for the subjects Hessen's schools use in SPH.
/// Everything else keeps its own token as key.
private let subjectAliases: [String: String] = {
    let groups: [String: [String]] = [
        "deutsch": ["d", "de", "deu", "deutsch"],
        "mathematik": ["m", "ma", "mat", "math", "mathe", "mathematik"],
        "englisch": ["e", "en", "eng", "engl", "englisch"],
        "franzoesisch": ["f", "fr", "fra", "franz", "franzosisch"],
        "latein": ["l", "la", "lat", "latein"],
        "spanisch": ["spa", "span", "spanisch"],
        "russisch": ["ru", "rus", "russ", "russisch"],
        "italienisch": ["it", "ita", "ital", "italienisch"],
        "biologie": ["b", "bio", "biol", "biologie"],
        "chemie": ["c", "ch", "che", "chem", "chemie"],
        "physik": ["ph", "phy", "phys", "physik"],
        "informatik": ["if", "inf", "info", "informatik"],
        "politikundwirtschaft": ["pw", "powi", "pouw", "politik", "politikundwirtschaft"],
        "geschichte": ["g", "ge", "ges", "gesch", "geschichte"],
        "erdkunde": ["ek", "erd", "erdkunde", "geo", "geografie", "geographie"],
        "religion": ["rel", "ev", "eva", "ka", "kath", "kr", "religion"],
        "ethik": ["eth", "ethi", "ethik"],
        "sport": ["sp", "spo", "spor", "sport"],
        "kunst": ["k", "ku", "kun", "kunst"],
        "musik": ["mu", "mus", "musi", "musik"],
        "darstellendesspiel": ["ds", "dsp", "darstellendes", "darstellendesspiel"],
        "wirtschaft": ["wi", "wir", "wirtschaft"],
        "arbeitslehre": ["al", "arbeitslehre"],
    ]
    var map: [String: String] = [:]
    for (canonical, variants) in groups {
        map[canonical] = canonical
        for v in variants { map[v] = canonical }
    }
    return map
}()

/// User-chosen course colours, overriding `defaultSubjectColor`.
///
/// Keyed by the same canonical subject as the hashed default, so picking a colour for
/// `Mathematik 10a` in the course list also recolours `M` in the timetable. Persisted per
/// account via `AccountSettings`, next to `hidden-lessons`.
@Observable @MainActor
final class SubjectColors {
    static let settingsKey = "subject-colors"

    private var overrides: [String: UInt32] = [:]   // subject token → ARGB
    private var settings: AccountSettings?
    private var accountID: Int?

    /// Points the store at an account; pass `nil` while signed out.
    func bind(settings: AccountSettings, accountID: Int?) {
        self.settings = settings
        self.accountID = accountID
        overrides = accountID.flatMap { settings.get([String: UInt32].self, accountID: $0, key: Self.settingsKey) } ?? [:]
    }

    func color(for name: String?) -> Color {
        if let argb = stored(for: name) { return Color(argb: argb) }
        return defaultSubjectColor(name)
    }

    func hasCustomColor(for name: String?) -> Bool { stored(for: name) != nil }

    /// Override for the subject, honouring colours picked before the keys became canonical.
    private func stored(for name: String?) -> UInt32? {
        overrides[Self.key(name)] ?? overrides[Self.legacyKey(name)]
    }

    /// Stores `color` for the subject, or clears the override when `color` is nil.
    func setColor(_ color: Color?, for name: String?) {
        overrides[Self.legacyKey(name)] = nil   // a fresh pick supersedes the pre-canonical entry
        overrides[Self.key(name)] = color.map(Self.argb(of:))
        persist()
    }

    private func persist() {
        guard let settings, let accountID else { return }
        settings.set(overrides.isEmpty ? nil : overrides, accountID: accountID, key: Self.settingsKey)
    }

    private static func key(_ name: String?) -> String { subjectKey(name) }
    private static func legacyKey(_ name: String?) -> String { subjectCode(name).lowercased() }

    /// ColorPicker hands back extended-range sRGB; clamp before packing into 8-bit channels.
    private static func argb(of color: Color) -> UInt32 {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a) else { return 0xFF80_8080 }
        let channel = { (v: CGFloat) in UInt32((v * 255).rounded().clamped(to: 0...255)) }
        return 0xFF00_0000 | (channel(r) << 16) | (channel(g) << 8) | channel(b)
    }
}

private extension CGFloat {
    func clamped(to range: ClosedRange<CGFloat>) -> CGFloat { Swift.min(Swift.max(self, range.lowerBound), range.upperBound) }
}
