import SwiftUI

/// Stable per-subject hue, like the Flutter `color_hash.dart`.
///
/// Course names differ between applets — the timetable shows the bare subject (`D`, `Spo`),
/// while the course folders add a group (`D 06G1`, `GEO 06/1`). Hashing only the leading
/// subject token, case-insensitively, keeps the same course the same colour everywhere.
func subjectColor(_ name: String?) -> Color {
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
