# Lanis — native iOS fork (personal project)

A personal, unofficial fork of [Lanis Mobile](https://github.com/lanis-mobile/lanis) that rebuilds
the app from the ground up as a native iOS app in Swift and SwiftUI.

**This is a hobby project for my own use.** It is not affiliated with, endorsed by, or supported by
the Lanis Mobile team, the Staatliches Schulamt, or Schulportal Hessen. It is not published to the
App Store and makes no promise of feature parity, stability, or continued maintenance. If you want
the real app, use the official one — it is excellent, actively maintained, and serves tens of
thousands of students daily:

- [App Store](https://apps.apple.com/de/app/lanis-mobile/id6511247743) · [Google Play](https://play.google.com/store/apps/details?id=io.github.alessioc42.sph) · [IzzyOnDroid](https://apt.izzysoft.de/fdroid/index/apk/io.github.alessioc42.sph) · [Website](https://lanis-mobile.github.io/)

Per upstream's request to fork authors, this build uses its own bundle identifier
(`com.jofreund.lanis-fork`) so it can never collide with the published apps.

## Credit

All of the hard work — years of reverse-engineering Schulportal Hessen, the login handshake and
crypto, and every HTML parser — belongs to the upstream Lanis Mobile project and its contributors:

- **[Alessio Caputo (@alessioC42)](https://github.com/alessioC42)** — creator and principal author
- **[@kurwjan](https://github.com/kurwjan)**, **[@Rajala1404](https://github.com/Rajala1404)**,
  **[@Vito0912](https://github.com/Vito0912)**, **[@CodeSpoof](https://github.com/CodeSpoof)** — major contributors
- and [everyone else who contributed](https://github.com/lanis-mobile/lanis/graphs/contributors)

This fork rewrites their work in a different language. It does not reverse-engineer anything new:
the Dart sources are the specification, and each Swift file names the upstream file and release it
was ported from. Any bug here is mine; anything that works is theirs.

## What this fork contains

```
native/          LanisKit (platform-neutral SPH client) + the SwiftUI iOS app
docs/native/     REBUILD_PLAN.md — architecture, phases, risks
```

The Flutter app and its Android target were removed from this fork — they keep shipping from
upstream, which is wired up here as the `origin` remote. See [`native/README.md`](native/README.md)
for build instructions and current status, and
[`docs/native/REBUILD_PLAN.md`](docs/native/REBUILD_PLAN.md) for the plan.

## Upstream as specification

The Dart sources remain the spec for every port — see the "Upstream reference" section in
[`native/README.md`](native/README.md).

- [`lanis-mobile/liblanis`](https://github.com/lanis-mobile/liblanis) — session, crypto, applet parsers
- [`lanis-mobile/lanis`](https://github.com/lanis-mobile/lanis) — the Flutter app (`origin`)

## Licence

GPL-3.0, inherited from upstream. The Swift port is a derivative work of GPL-3.0 code and remains
GPL-3.0. Copyright for the original work stays with the Lanis Mobile authors; see [`LICENSE`](LICENSE).
