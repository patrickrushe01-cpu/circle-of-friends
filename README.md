# circle-of-friends

Circle of Friends — a mobile app for iOS and Android that visualizes your
ten closest relationships as a radar screen. Contacts sit on concentric
rings, with distance from center reflecting recent interaction frequency
via calls, texts, calendar, email, and manual check-ins. Built with
Flutter and Kotlin, refreshing hourly, fully on-device.

See [DESIGN.md](DESIGN.md) for the full architecture, data schema, scoring
algorithm, screen-by-screen UX, and phased build plan.

## Status

Phase 1–3 scaffold: project structure, data layer, scoring engine, all
four screens (onboarding, radar, check-in, settings), the Android native
call/SMS module, and the cross-platform calendar + email collectors are
all in place. Not yet wired up:

- **Gmail OAuth client**: `GmailEmailProvider` needs a real OAuth client
  ID registered in Google Cloud Console (with the `gmail.metadata` scope
  enabled) before "Connect" in Settings will do anything — see DESIGN.md
  §11. Only an IMAP-generic provider is left as future work; Gmail is the
  only concrete `EmailProvider` today.
- `flutter_local_notifications` timezone-aware scheduling (currently uses
  local `DateTime` as a placeholder — see `notification_service.dart`).
- Generated Isar (`*.g.dart`) files — run `flutter pub get && dart run
  build_runner build` once dependencies are fetched.
- iOS platform project (`ios/`) and Android Gradle wrapper — run `flutter
  create .` in the project root to generate the standard platform
  boilerplate this scaffold builds on top of, then re-apply the
  `AndroidManifest.xml` permissions and `MainActivity.kt` from this repo.
- This container has no Flutter/Android SDK or a device/emulator, so none
  of the above has been run or built here — do that locally first.

## Getting started

```
flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter create .   # generates ios/ and the Gradle wrapper this scaffold expects
flutter run
```

See DESIGN.md §11 for developer account and tooling setup (Apple
Developer, Google Play Console).
