import SwiftUI
import WebKit
import LanisKit

/// Moodle inside a WKWebView, signed in via the SPH SAML chain (port of `moodle.dart`).
struct MoodleView: View {
    @Environment(AppState.self) private var app
    @State private var controller = MoodleWebController()
    @State private var error: String?
    @State private var loading = true

    var body: some View {
        ZStack {
            MoodleWebView(controller: controller)
            if loading { ProgressView("Moodle anmelden …").padding().glassEffect(in: .rect(cornerRadius: 16)) }
            if let error = error ?? controller.loadError {
                ContentUnavailableView("Moodle nicht erreichbar", systemImage: "exclamationmark.triangle", description: Text(error))
                    .background(.background)
            }
        }
        .navigationTitle("Moodle")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarVisibility(.hidden, for: .tabBar)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button { controller.webView.goBack() } label: { Label("Zurück", systemImage: "chevron.left") }.disabled(!controller.canGoBack)
                Button { controller.webView.reload() } label: { Label("Neu laden", systemImage: "arrow.clockwise") }
                Button { Task { await signIn() } } label: { Label("Neu anmelden", systemImage: "person.badge.key") }
            }
        }
        .task { await signIn() }
    }

    private func signIn() async {
        loading = true; error = nil
        do {
            guard let account = await app.activeClearTextAccount() else { throw LanisError.credentialsIncomplete }
            let result = try await MoodleSSO.perform(account: account, config: app.config)
            await controller.inject(result.cookies)
            controller.webView.load(URLRequest(url: result.homeURL))
        } catch let e as LanisError {
            error = AppState.message(for: e)
        } catch {
            self.error = error.localizedDescription
        }
        loading = false
    }
}

@Observable @MainActor
final class MoodleWebController: NSObject, WKNavigationDelegate {
    let webView: WKWebView
    var canGoBack = false
    var loadError: String?

    override init() {
        let cfg = WKWebViewConfiguration()
        cfg.websiteDataStore = .nonPersistent()   // cookies live only for this session, like the Flutter view
        webView = WKWebView(frame: .zero, configuration: cfg)
        super.init()
        webView.navigationDelegate = self
        webView.allowsBackForwardNavigationGestures = true
    }

    func inject(_ cookies: [HTTPCookie]) async {
        let store = webView.configuration.websiteDataStore.httpCookieStore
        for c in cookies { await store.setCookie(c) }
    }

    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction) async -> WKNavigationActionPolicy {
        guard let url = action.request.url else { return .allow }
        canGoBack = webView.canGoBack
        // Logout links would kill the SPH session too; external hosts open in Safari.
        if MoodleSSO.isHessenSchoolHost(url) {
            if url.path() == "/login/logout.php" || (url.path() == "/index.php" && url.query()?.contains("logout=all") == true) { return .cancel }
            return .allow
        }
        await UIApplication.shared.open(url)
        return .cancel
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { canGoBack = webView.canGoBack; loadError = nil }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        let host = webView.url?.host() ?? (error as? URLError)?.failingURL?.host() ?? "?"
        loadError = "\(host): \(error.localizedDescription)"
    }
}

struct MoodleWebView: UIViewRepresentable {
    let controller: MoodleWebController
    func makeUIView(context: Context) -> WKWebView { controller.webView }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
