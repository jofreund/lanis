# Lanis — Native Swift / SwiftUI Rebuild Plan

Status: **Step 1 done; Phase 2 + first Phase 3 applet started** in `native/`. Everything else is a plan, not code.

## 0. What we are rebuilding

The Flutter app (~26k lines) is a thin UI over **`liblanis`** (pub package, ~8.4k lines of pure Dart).
Neither lives in this fork any more — both are read from upstream ([`lanis-mobile/lanis`](https://github.com/lanis-mobile/lanis), the `origin` remote, and [`lanis-mobile/liblanis`](https://github.com/lanis-mobile/liblanis)). Paths below refer to those repos:

| Layer | Flutter today | Size | Native equivalent |
|---|---|---|---|
| Session + crypto | `liblanis/session/{session,cryptor}.dart` — cookie login via `login.schulportal.hessen.de`, RSA‑PKCS1 key exchange, AES‑256‑CBC with OpenSSL `EVP_BytesToKey` (MD5) derivation, `<encoded>` tag decryption, 10 s keep‑alive | 540 | `LanisKit/Session` (URLSession + Security.framework + CommonCrypto) |
| Applet parsers | substitutions, calendar, timetable, conversations, lessons (student+teacher), data storage, study groups — HTML scraping + JSON | ~2.9k | `LanisKit/Applets/*` with SwiftSoup |
| Persistence | SQLite (accounts, shared settings, account settings, offline snapshots) + host `SecretStore` | ~700 | SwiftData + Keychain |
| Multi‑account registry | Riverpod providers | ~900 | `@Observable` `AccountStore` / `SessionController` |
| UI | 7 applets, login, account switcher, settings (~20 sub‑pages), Moodle WebView, notifications, background refresh | ~22k | SwiftUI, iOS 26+ Liquid Glass |
| Platform | `flutter_local_notifications`, `background_fetch`, `file_picker`, `share_plus`, Sentry/GlitchTip | — | UserNotifications, BGTaskScheduler, `.fileImporter`, ShareLink, Sentry‑cocoa |

The Dart sources are the **spec**: every parser has a one‑to‑one Swift port, verified with the same HTML fixtures.

## 1. Goals & non‑goals

- Goals: native look/feel on iOS 26/27 (Liquid Glass, `Tab`/`TabView` minimize‑on‑scroll, search tab role, glass toolbars, `NavigationSplitView` on iPad), instant launch, Swift 6 strict concurrency, offline snapshots, feature parity with the Flutter iOS build.
- Non‑goals (for now): Android (the Flutter app keeps shipping there from upstream `main`; this fork is native‑only), macOS Catalyst (possible later since `LanisKit` is platform‑neutral), widgets/Live Activities (Phase 7 stretch).

## 2. Target architecture

```
native/
├── Package.swift                 # LanisKit (library) + LanisKitTests — no UIKit, runs on macOS for `swift test`
├── Sources/LanisKit/
│   ├── Core/        Errors, AccountType, Account, Config, UserAgent
│   ├── Crypto/      SPHCryptor (RSA handshake, AES-CBC, EVP_BytesToKey)
│   ├── Session/     LanisSession (actor), LoginFlow, KeepAlive, HTMLDecoding
│   ├── Directory/   SchoolDirectory (school list)
│   ├── Applets/     AppletMeta, AppletFetcher<T> (cache/offline/refresh), one folder per applet
│   └── Storage/     SecretStore protocol, Keychain impl, OfflineSnapshotStore
├── Tests/LanisKitTests/          fixtures/*.html copied from Flutter tests
└── Lanis/                        # Xcode app
    ├── Lanis.xcodeproj           # synchronized root group, depends on local LanisKit
    └── Lanis/
        ├── App/          LanisApp, AppState (@Observable), Router (NavigationPath per tab)
        ├── Design/       Glass helpers, colors, typography, Haptics
        ├── Features/     Login, Home (TabView), Substitutions, Calendar, Timetable, Conversations, Lessons, Files, StudyGroups, Settings, Moodle
        └── Platform/     Notifications, BackgroundRefresh, Deep links
```

Principles
- **Strict concurrency**: `LanisSession` is an `actor`; parsers are `Sendable` pure functions `(String) throws -> Model`; UI state is `@Observable @MainActor`.
- **No Riverpod analogue**: one `SessionController` per signed‑in account, exposed via `Environment`. Applet view models own an `AppletFetcher<T>` that yields `AsyncStream<FetchState<T>>` (fetching / online / offline / error) — the same state machine as `AppletParser` in Dart.
- **Models are `Codable`** so offline snapshots are JSON in SwiftData, mirroring `applet_offline_data`.
- **Testing**: every parser gets the Flutter HTML fixtures; crypto gets round‑trip + OpenSSL‑vector tests; `swift test` on macOS in CI, UI tests on simulator.

## 3. Design language (iOS 26/27 Liquid Glass)

- Root: `TabView` with `Tab(...)` items, `.tabBarMinimizeBehavior(.onScrollDown)`, a `Tab(role: .search)` for calendar/conversation search, `.tabViewBottomAccessory` for the account chip.
- Navigation: `NavigationStack` per tab; iPad → `NavigationSplitView` with glass sidebar (replaces Flutter `NavigationRail`).
- Surfaces: `.glassEffect()` / `GlassEffectContainer` for floating cards (substitution day header, account chip, calendar event sheet), `.buttonStyle(.glass)` / `.glassProminent` for primary actions, `.toolbarSpacer` + grouped `ToolbarItemGroup`s, `.scrollEdgeEffectStyle(.soft)` on lists.
- Theming: replace the Flutter seed‑color picker with a single `AccentColor` + `tint` settings (system tint preferred, user accent override), AMOLED/dark handled by the system.
- Motion: `.matchedTransitionSource` + `.navigationTransition(.zoom)` for cards → detail; `.sensoryFeedback`.
- Anything iOS 27‑only is adopted behind `if #available(iOS 27, *)` once verified against the SDK — the baseline API is iOS 26.

## 4. Phases

| # | Phase | Deliverable | Est. |
|---|---|---|---|
| **1** | **Feasibility spike (done)** | `LanisKit`: cryptor, session login/handshake, school directory, substitutions (AJAX path). App: Liquid Glass tab shell, login + school picker, substitutions list, settings stub. Builds & runs on iOS 27 simulator. | 1 wk |
| 2 | Core hardening *(done: `AccountStore` + Keychain, account switcher, `SnapshotStore` offline snapshots with offline banner, `AccountSettings` per-account settings, String Catalog de→en for all UI strings, timetable hidden lessons; remaining: substitution filters, error-string catalog for `LanisError`)* | Keychain `SecretStore`, SwiftData accounts + settings, multi‑account switcher, session restore on launch, keep‑alive, error mapping → localized strings (port `intl_de/en.arb` to String Catalog). | 2 wk |
| 3 | Read‑only applets *(in progress: Calendar and Timetable verified live with a real account; calendar export, fuzzy search, month grid, timetable settings pending (hidden lessons done))* | Calendar (+ fuzzy search, ICS export), Timetable (student, week/own plan), Study groups, Data storage (browse + QuickLook). Offline snapshots for substitutions/timetable. | 3 wk |
| 4 | Interactive applets *(in progress: Lessons student overview + course detail (history/marks/exams/attendance) + homework toggle verified live; uploads, file deletion, conversations pending)* | Conversations (list, chat, rich text editor → `TextEditor` + AttributedString, new‑conversation configurator), Lessons student (course overview, uploads via `.fileImporter`, attendances) | 4 wk |
| 5 | Teacher + parent *(started: `lanis://<scope>/<segment>` deep links parsed and routed; `-LanisDeepLink` launch arg for automation)* | Lessons teacher (course folders, create entry), parent account gating, deep‑link scheme `lanis://` parity with `deep_link.dart` | 2 wk |
| 6 | Platform *(started: Moodle `WKWebView` with SAML SSO cookie injection verified live; `BGAppRefreshTask` + local notification for substitutions (device-only, simulator lacks BGTaskScheduler); notification permission in Settings)* | Push‑less local notifications via `BGAppRefreshTask` for substitutions/conversations, Moodle `WKWebView` with cookie bridging, ShareLink, Sentry, What's‑new, privacy policy | 2 wk |
| 7 | Ship | App Store Connect lane in `fastlane`, TestFlight with current testers, migration of stored accounts from Flutter (read `flutter_secure_storage` Keychain items once, then delete), feature‑flagged cut‑over; stretch: Lock‑screen widget for next substitution | 2 wk |

Total ≈ 16 engineer‑weeks. Phases 3/4 parallelise across people because each applet is an isolated folder in both `LanisKit` and the app.

## 5. Risks

1. **SPH HTML drift** — same risk as today; mitigated by fixture tests and keeping `liblanis` Dart as reference until parity.
2. **Xcode 27 beta** — project must also build with Xcode 26 GM until 27 ships; keep deployment target 26.1 (needed for `tabViewBottomAccessory(isEnabled:)`).
3. **Crypto compatibility** — `EVP_BytesToKey` MD5 derivation and PKCS#1 v1.5 RSA must be byte‑exact. Covered by round‑trip tests in Step 1; verify the handshake against the live server before Phase 2.
4. **Credentials migration** — Flutter stores passwords via `flutter_secure_storage`; the native app can read the same Keychain service if bundle ID and access group match. Verify on a device in Phase 7.
5. **Rich text editor** for conversations (Quill in Flutter) — iOS 26 `TextEditor(AttributedString)` should suffice; fallback is a WKWebView editor.

## 6. Step 1 — what exists now

See `native/README.md` for build instructions. Verified: `swift test` passes, app builds and launches on iPhone 17 Pro (iOS 27) with a glass tab bar, login sheet with searchable school picker, and a substitutions list fed by `LanisKit` once signed in.



Known gaps: the dedicated search tab was dropped in favour of `.searchable` on Calendar (the `role: .search` pill did not render next to 5 tabs — revisit); real‑account login not exercised (no test credentials); see `native/README.md`.
