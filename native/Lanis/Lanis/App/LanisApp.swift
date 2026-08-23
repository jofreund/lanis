import SwiftUI
import LanisKit

@main
struct LanisApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(appState)
                .environment(appState.subjectColors)
                .task {
                    DebugTrace.log("app start args=\(ProcessInfo.processInfo.arguments.dropFirst().joined(separator: " "))")
                    BackgroundRefresh.register(app: appState)
                    await appState.restore()
                    // `-LanisDeepLink lanis://common/moodle` for UI automation / debugging.
                    if let raw = UserDefaults.standard.string(forKey: "LanisDeepLink"), let url = URL(string: raw) {
                        appState.deepLink = AppState.parse(deepLink: url)
                        DebugTrace.log("launch arg \(raw) -> \(String(describing: appState.deepLink))")
                    }
                }
        }
    }
}
