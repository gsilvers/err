# Agent Guide for Err

This file helps AI coding agents understand how to work with the Err repository.

## Project Overview

Err is a free, privacy-first Android app for tracking outdoor activities (cycling, hiking, running) as an alternative to Strava and Garmin. See `README.org` for full context on goals and philosophy.

## Tech Stack

- **Language:** Kotlin
- **Platform:** Android (minSdk 24, targetSdk 35)
- **Build system:** Gradle with Kotlin DSL (`.gradle.kts` files)
- **UI:** XML layouts with AppCompat + Material Components

## Project Structure

```
app/src/main/
  java/com/example/helloworld/   # Application source (package will evolve)
  res/layout/                    # XML layouts
  res/values/                    # Strings, themes, colors
  AndroidManifest.xml
app/build.gradle.kts             # App-level dependencies and Android config
build.gradle.kts                 # Root build file (plugin versions)
settings.gradle.kts              # Project modules and repository config
gradle.properties                # Gradle and Android flags
```

## Building

The project is built via GitHub Actions — see `.github/workflows/build.yml`. There is no Gradle wrapper committed; the CI uses `gradle/actions/setup-gradle` with a pinned Gradle version.

To build locally you need:
- JDK 17
- Android SDK with platform 35 and build tools installed
- Gradle 8.7+

```bash
gradle assembleDebug
```

The debug APK is output to `app/build/outputs/apk/debug/app-debug.apk`.

## Key Principles to Respect

- **Free, forever.** Do not introduce dependencies, SDKs, or patterns that would push toward monetisation or paywalls.
- **Privacy first.** All data stays local on the device. Do not add any analytics, telemetry, crash reporters, or network calls that send user data anywhere without explicit user action.
- **Simplicity over features.** Err is for casual users, not athletes. Avoid feature creep and keep the UI straightforward.
- **No gamification.** Do not add leaderboards, segments, challenges, or competitive features.

## Contribution Rules

- All code must be licensed under AGPL-3.0 (see `LICENSE`)
- Open PRs against `main` — do not push branches directly
- The CI build must pass before a PR can be merged
- `@gsilvers` is the sole maintainer and must review all external PRs (see `.github/CODEOWNERS`)

## What Agents Should Avoid

- Adding tracking, analytics, or third-party data SDKs
- Changing the package name or applicationId without discussion
- Modifying the license or stripping AGPL headers
- Adding subscription, IAP, or payment logic of any kind
