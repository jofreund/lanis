import SwiftUI

/// Small Liquid Glass helpers so feature views stay declarative.
extension View {
    /// Floating glass card used for day headers, account chip, empty states.
    func glassCard(tint: Color? = nil, interactive: Bool = false) -> some View {
        self
            .padding(.horizontal, 14).padding(.vertical, 10)
            .glassEffect(
                (tint.map { Glass.regular.tint($0) } ?? .regular).interactive(interactive),
                in: .rect(cornerRadius: 18)
            )
    }
}

enum Haptics {
    @MainActor static func success() {
        #if os(iOS)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        #endif
    }
}
