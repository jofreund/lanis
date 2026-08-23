import SwiftUI
import UIKit
import LanisKit

/// Stable per-subject hue, like the Flutter `color_hash.dart`.
///
/// Course names differ between applets — the timetable shows the bare subject (`D`, `Spo`),
/// while the course folders add a group (`D 06G1`, `GEO 06/1`). Hashing only the leading
/// subject token, case-insensitively, keeps the same course the same colour everywhere.
func defaultSubjectColor(_ name: String?) -> Color {
    let key = subjectCode(name).lowercased()
    let h = key.unicodeScalars.reduce(7) { ($0 &* 31 &+ Int($1.value)) & 0xFFFF }
    return Color(hue: Double(h % 360) / 360, saturation: 0.65, brightness: 0.85)
}

/// The leading subject token of a course name (`"D 06G1"` → `"D"`), used as the colour key and as a badge label.
func subjectCode(_ name: String?) -> String {
    guard let name, !name.isEmpty else { return "–" }
    let token = name.split(whereSeparator: { $0 == " " || $0 == "-" }).first.map(String.init) ?? name
    return token.count > 4 ? String(token.prefix(4)) : token
}

/// User-chosen course colours, overriding `defaultSubjectColor`.
///
/// Keyed by the same subject token as the hashed default, so picking a colour for `D 06G1`
/// in the course list also recolours `D` in the timetable. Persisted per account via
/// `AccountSettings`, next to `hidden-lessons`.
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
        if let argb = overrides[Self.key(name)] { return Color(argb: argb) }
        return defaultSubjectColor(name)
    }

    func hasCustomColor(for name: String?) -> Bool { overrides[Self.key(name)] != nil }

    /// Stores `color` for the subject, or clears the override when `color` is nil.
    func setColor(_ color: Color?, for name: String?) {
        overrides[Self.key(name)] = color.map(Self.argb(of:))
        persist()
    }

    private func persist() {
        guard let settings, let accountID else { return }
        settings.set(overrides.isEmpty ? nil : overrides, accountID: accountID, key: Self.settingsKey)
    }

    private static func key(_ name: String?) -> String { subjectCode(name).lowercased() }

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
