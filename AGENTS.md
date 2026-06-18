# Agent Guide for Err

This file helps AI coding agents understand how to work with the Err repository.

## Project Overview

Err is a free, privacy-first app for tracking outdoor activities (cycling, hiking, running) as an alternative to Strava and Garmin. See `README.org` for full context on goals and philosophy.

## Tech Stack

- **Language:** Dart
- **Framework:** Flutter (stable channel)
- **Dart SDK:** `^3.11.5` (see `pubspec.yaml`)
- **Platforms:** Android is the primary target today; iOS is a stated future goal. The host projects live in `android/` and `ios/`.
- **UI:** Flutter widgets (Material Design), built entirely in Dart — no XML layouts.
- **Key packages:** `geolocator` (location), `sensors_plus` (barometer/accelerometer), `path_provider`, `shared_preferences`, `wakelock_plus`, `flutter_colorpicker`.

## Project Structure

```
lib/                      # All application source (Dart)
  main.dart               # App root, tracking screen, GPX/CSV export
  elevation_tracker.dart  # Fuses barometer + GPS elevation
  err_theme.dart          # Theme model
  builtin_themes.dart     # Bundled themes
  theme_picker.dart       # Theme selection UI
  custom_theme_editor.dart
  debug/                  # Hidden debug tools (filter log, lisp REPL, flight recorder)
test/                     # flutter_test widget and unit tests
android/                  # Android host project (Gradle, Kotlin MainActivity, manifest)
ios/                      # iOS host project
pubspec.yaml              # Package metadata and dependencies
analysis_options.yaml     # Analyzer + lint config (flutter_lints)
.github/workflows/build.yml  # CI: builds and releases the Android APK
```

The Android `applicationId`/`namespace` is currently `com.example.err`.

## Building & Testing

You need the **Flutter SDK** (stable channel); it bundles the matching Dart SDK. Building the Android APK additionally requires the Android SDK and a JDK (per Flutter's standard Android toolchain).

```bash
flutter pub get          # install dependencies
flutter analyze          # static analysis / lints
flutter test             # run the test suite
flutter run              # run on a connected device or emulator
flutter build apk        # build a release APK locally
```

CI (`.github/workflows/build.yml`) runs on pushes to `main` (and via manual dispatch). It uses `subosito/flutter-action` on the stable channel, runs `flutter pub get`, then `flutter build apk --release`, signs it with the release keystore, and publishes the resulting `build/app/outputs/flutter-apk/app-release.apk` as a GitHub release. Releases are distributed via Obtainium and as a manual APK download (e.g. on GrapheneOS).

## Key Principles to Respect

- **Free, forever.** Do not introduce dependencies, SDKs, or patterns that would push toward monetisation or paywalls.
- **Privacy first.** All data stays local on the device. Do not add any analytics, telemetry, crash reporters, or network calls that send user data anywhere without explicit user action.
- **Simplicity over features.** Err is for casual users, not athletes. Avoid feature creep and keep the UI straightforward.
- **No gamification.** Do not add leaderboards, segments, challenges, or competitive features.
- **Data is the user's.** Export stays in simple, interoperable formats (GPX, CSV).

## Contribution Rules

- All code must be licensed under AGPL-3.0 (see `LICENSE`)
- Open PRs against `main` — do not push branches directly
- The CI build must pass before a PR can be merged
- `@gsilvers` is the sole maintainer and must review all PRs (see `.github/CODEOWNERS`)

## What Agents Should Avoid

- Adding tracking, analytics, or third-party data SDKs
- Changing the package name or `applicationId` without discussion
- Modifying the license or stripping AGPL headers
- Adding subscription, IAP, or payment logic of any kind
