# Lanis native (Swift / SwiftUI) — Step 1 spike

See [`docs/native/REBUILD_PLAN.md`](../docs/native/REBUILD_PLAN.md) for the full plan.

```
native/
├── Package.swift          LanisKit — platform-neutral SPH client (port of liblanis)
├── Sources/LanisKit/      Crypto, Session, Directory, Applets/Substitutions, Storage
├── Tests/LanisKitTests/   unit tests + live tests (LANIS_LIVE=1)
└── Lanis/                 iOS app (Xcode 27, iOS 26.1+ deployment target, Mac Catalyst enabled, Liquid Glass)
```

## Build & test

```bash
cd native && swift test                 # unit tests (macOS host)
cd native && LANIS_LIVE=1 swift test --filter LiveTests   # hits real SPH: school list + RSA/AES handshake
```

```bash
cd native/Lanis && xcodebuild -project Lanis.xcodeproj -scheme Lanis \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' CODE_SIGNING_ALLOWED=NO build
```

Or open `native/Lanis/Lanis.xcodeproj` in Xcode 27 and run.

## What works (Step 1)

- `SPHCryptor`: RSA PKCS#1 key exchange, OpenSSL‑compatible AES‑256‑CBC (`EVP_BytesToKey`/MD5), `<encoded>` tag decryption — byte‑exact with `openssl enc`, handshake verified against the live server.
- `LanisSession` actor: login redirect flow, user data + account type parsing, fast‑travel menu, 10 s keep‑alive, cryptor init.
- `SchoolDirectory`, `SubstitutionsParser` (AJAX + non‑AJAX paths), `CalendarParser` (categories, events, detail, iCal export link), `TimetableParser` (rowspan layout, A/B week badge, own vs class plan, break synthesis), `LessonsStudentParser` (course overview, detail view with history/marks/exams/attendance, homework toggle), `KeychainSecretStore`, `AccountStore` (multi‑account JSON registry + Keychain passwords), `SnapshotStore` (per-account applet snapshots for `allowOffline` applets), `AccountSettings` (per-account key/value, same `hidden-lessons` key as Flutter).
- App: `AppletModel<T>` = snapshot-first load → refresh → offline fallback with a glass "Offline · Stand …" banner; `Localizable.xcstrings` (German source, English translations, verified via `-AppleLanguages (en)`); timetable lessons can be hidden via context menu.
- App: Liquid Glass `TabView` with bottom accessory account chip (tap = account switcher menu), login sheet + searchable school picker, substitutions list, calendar list with search + event sheet, timetable with day picker / week toggle / own-vs-class plan, Mein Unterricht course list + detail with homework check-off, settings with account management (swipe to remove) and diagnostics.

## Verified with a real account (2026‑08‑22)

- Login, user data, account type and the RSA/AES handshake succeed; `kalender.php` + `getEvents` `stundenplan.php` (via its `detail_klasse` redirect) and `meinunterricht.php` (overview + `sus_view` detail) return real data that renders in the Calendar, Timetable and Unterricht tabs.
- SPH reports applet errors as **HTTP 200 pages titled "Fehler - Schulportal Hessen"** ("Die Funktion ist für diesen Account nicht freigeschaltet"). `LanisSession.checkErrorPage` maps these to `LanisError.unsupportedApplet`; the tab bar only shows applets present in the fast‑travel menu (`LanisSession.supportedApplets`), like the Flutter drawer.
- Requesting an unsupported applet rotates the `sid` cookie, which made a concurrent request bounce via `302 forward.php`. `getHTML` now follows same‑host redirects (≤ 4 hops) and never fetches unsupported applets.
- HTTP trace: `log stream --predicate 'subsystem == "io.github.alessioc42.sph.native"'` (cookie values redacted).

## Moodle & platform

- `MoodleSSO.perform` replays the Flutter SAML chain (`mo<id>` → llngproxy → `saml/singleSignOn` POST with `SPH-Sessionpdata._url` → artifact → `login/index.php`); the resulting cookies are injected into a non-persistent `WKWebsiteDataStore`. Verified live: Moodle renders signed in. Hosts under `*.hessen.de` stay in the web view (some schools host Moodle on `*.schule.hessen.de`); logout links are blocked; other hosts open in Safari.
- `BackgroundRefresh` registers `io.github.alessioc42.sph.native.refresh` (`Config/Info.plist` carries `BGTaskSchedulerPermittedIdentifiers` + `UIBackgroundModes=fetch`, merged into the generated plist). The simulator reports "BGTaskScheduler is not available" — test on a device.
- Deep links: `lanis://common/moodle`, `lanis://common/settings`, `lanis://<scope>/{calendar,timetable,lessons,substitutions,conversations}`. For automation: `xcrun simctl launch booted io.github.alessioc42.sph.native -LanisDeepLink lanis://common/moodle`.

## Known gaps / to verify

- Background refresh + notifications are unverified on a real device.
- `Tab(role: .search)` did not render as a separate pill next to 5 tabs; search now lives on the Calendar tab via `.searchable`. Revisit for a global search.
- Substitution filters and localized `LanisError` messages: Phase 2 remainder.
