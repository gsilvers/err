# Err Architecture

This document explains how the Err codebase is organised, so a new contributor
can find their way around and add code in the right place. It is the
developer-facing companion to `README.org` (the *why*) and `AGENTS.md` (the
ground rules and build/test commands).

It describes both the structure as it exists today **and** the layering we are
deliberately moving toward (roadmap item #6, "Refactor and code cleanup"). Where
the two differ, that is called out explicitly — see
[Where this is heading](#where-this-is-heading).

---

## Big picture

Err is a single-purpose Flutter app. Its heart is one **tracker screen** that
records a GPS + barometer activity and saves it as a GPX track and a CSV
summary. Around it sit a few secondary screens — Statistics, Settings, Help,
Appearance, Theme, and hidden Debug tools — reached from a navigation drawer.

There is **no backend, no account, and no network**. Everything is computed and
stored on the device. The saved files are the source of truth; the app reads
them back rather than keeping a separate database.

---

## Layers

The code is organised into four layers. **Dependencies point downward only** —
a lower layer never imports a higher one.

```
┌───────────────────────────────────────────────────────────┐
│ UI            Flutter widgets & screens                     │
│               main.dart (TrackerScreen), *_screen.dart,     │
│               theme_picker, app_drawer, tracking_controls   │
└───────────────┬───────────────────────────────────────────┘
                │
┌───────────────▼───────────────┐   (planned) session state held as a
│ Controllers                    │   ChangeNotifier; the widget is a thin
│                                │   listener. Today this lives inside the
└───────────────┬───────────────┘   tracker widget — see "Where this is heading".
                │
┌───────────────▼───────────────────────────────┐
│ Repositories / stores                          │   own all persistence & platform I/O
│ trip_repository, appearance (AppearanceStore)  │   (files, shared_preferences, path_provider)
└──────────┬──────────────────────┬──────────────┘
           │                      │
┌──────────▼──────────┐  ┌────────▼───────────────────┐
│ Domain / algorithms │  │ Models & pure helpers       │
│ elevation_tracker,  │  │ err_theme, builtin_themes,  │
│ debug/*             │  │ trip_summary, units,        │
│                     │  │ appearance (AppearanceSettings)│
└─────────────────────┘  └────────────────────────────┘
```

1. **Models & pure helpers** — immutable value types and pure functions. No
   widgets, no I/O. Trivially unit-testable.
2. **Domain / algorithms** — how the numbers are computed. Pure-ish: takes
   inputs, produces outputs, no widgets.
3. **Repositories / stores** — the only place that touches the filesystem,
   `shared_preferences`, or `path_provider`. They take plain inputs (e.g. a
   file path) so they carry no platform-channel dependencies and stay
   unit-testable against a temp directory.
4. **UI** — Flutter widgets. They read from models/repositories, render, and
   route. They should hold as little logic as possible.

The guiding rule: **anything worth testing lives outside a widget**, in one of
the lower layers, so it can be unit-tested without pumping a widget tree.

---

## Module map

| File | Layer | Role |
|---|---|---|
| `lib/main.dart` | UI (+ engine/IO, see below) | `ErrApp` root + theme state; `TrackerScreen`, the recording screen. Today this also holds the tracking engine and GPX/CSV writing. |
| `lib/tracking_controls.dart` | UI | The Start / Pause / Resume / Stop control bar. |
| `lib/stats_screen.dart` | UI | Statistics: month/year totals, year-over-year, history. |
| `lib/settings_screen.dart` | UI | Settings: units, display toggles, theme, appearance, debug. |
| `lib/help_screen.dart` | UI | In-app help. |
| `lib/appearance_screen.dart` | UI | Pick/tune background and edge decoration images. |
| `lib/theme_picker.dart` | UI | Theme selection bottom sheet. |
| `lib/custom_theme_editor.dart` | UI | Custom theme colour editor. |
| `lib/app_drawer.dart` | UI | Navigation drawer. |
| `lib/debug/debug_screen.dart` | UI | Hidden diagnostics screen. |
| `lib/elevation_tracker.dart` | Domain | Fuses barometer + GPS into one elevation stream. |
| `lib/debug/diagnostics.dart` | Domain | Flight recorder + live tracking diagnostics. |
| `lib/debug/mini_lisp.dart` | Domain | Tiny Lisp interpreter (read-only debug REPL). |
| `lib/debug/repl_env.dart` | Domain | REPL environment for the debug tools. |
| `lib/trip_repository.dart` | Repository | Reads saved trips back from disk; `TripStats` aggregates them. |
| `lib/appearance.dart` | Model + Repository | `AppearanceSettings` (model) and `AppearanceStore` (persistence + image files). |
| `lib/err_theme.dart` | Model | `ErrTheme` and its colour-slot helpers. |
| `lib/builtin_themes.dart` | Model/data | The bundled themes, ported from ef-themes. |
| `lib/trip_summary.dart` | Model | One recorded activity, parsed from its summary CSV. |
| `lib/units.dart` | Pure helpers | Distance/elevation/duration/speed formatting. |

---

## Key flows

### Recording lifecycle (the tracker)

```
Start → request location permission → "acquiring": wait for a fresh GPS lock
      → tracking: each fix is filtered (accuracy gate, stale-fix gate,
        teleport rejection, 60 s segment split) and elevation is fused
      → Pause / Resume: a Stopwatch measures active time only; resume
        re-anchors in a new GPX segment so the gap isn't counted
      → Stop → write <stamp>.gpx + <stamp>.csv
```

The *why* behind every filter (the 25 m accuracy gate, teleport rejection, the
barometer/GPS fusion and rebasing) is documented in
[`docs/gps-accuracy.md`](./gps-accuracy.md). Those comments and that doc encode
hard-won fixes — preserve them through any refactor.

### Reading statistics

The Statistics screen asks `TripRepository` to scan the save directory and parse
the one-line summary CSVs; `TripStats` buckets them by month and year. The files
stay the source of truth, so a trip copied in or deleted by hand is reflected
immediately.

### Settings, theme, and appearance

These are persisted in `shared_preferences` and flow down to the screens that
need them. Appearance images are copied into an app-private `decorations/`
folder; only the filename is stored.

---

## Persistence map

| What | Where |
|---|---|
| Theme choice & custom themes | `shared_preferences`: `selected_theme_id`, `custom_themes` |
| Settings | `shared_preferences`: `use_imperial`, `keep_screen_on`, `show_speed`, `debug_mode` |
| Appearance (bg + edge images, opacity, fit) | `shared_preferences`: `appearance` (JSON) |
| Recorded trips | `<stamp>.gpx` + `<stamp>.csv` (+ `<stamp>-debug.csv` in debug mode) in the app's external/documents dir |
| Decoration images | `<app documents>/decorations/` |

---

## Conventions

- **Plain Flutter only.** No state-management framework (Bloc/Riverpod/etc.) and
  no new dependencies without discussion — see the principles in `AGENTS.md`.
  Where shared state is genuinely needed, use `ChangeNotifier` /
  `InheritedNotifier`.
- **Small, single-purpose files.** Match the style of the existing focused files
  (`units`, `trip_repository`, `appearance`, `tracking_controls`).
- **Logic lives outside widgets** so it can be unit-tested.
- **Preserve the "why" comments**, especially around GPS and elevation.
- **Everything stays local**, and exports stay portable (GPX/CSV).

---

## Testing

`test/` mirrors `lib/`. The pure layers (models, domain, repositories) get unit
tests; widgets get focused widget tests.

One gotcha: real file or `shared_preferences` I/O inside a `testWidgets` body
must run inside `tester.runAsync(...)` — `testWidgets` uses a fake-async zone in
which real I/O futures never complete, which otherwise hangs the test.

Run `flutter analyze` and `flutter test` before every PR (see `AGENTS.md`).

---

## Where this is heading

Today, `lib/main.dart` is ~1,200 lines and its `TrackerScreen` state mixes three
concerns the layering above keeps apart: the **UI**, the **tracking engine**
(GPS/sensor streaming, distance/teleport/segment logic, the pause state
machine), and **file writing** (GPX/CSV). The tracking lifecycle is currently
encoded in a handful of boolean flags rather than an explicit state.

The "Refactor and code cleanup" roadmap item moves it toward the target above, in
small, behaviour-preserving steps:

- Extract a **`TrackingController`** (`ChangeNotifier`) that owns the recording
  session, the fix-filtering, and the pause logic, exposing an immutable
  snapshot with a `TrackingStatus` enum instead of loose booleans. The widget
  becomes a thin listener — and the core algorithm finally becomes
  unit-testable by feeding it synthetic position streams.
- Extract a **`TripWriter`** (the write-side symmetry with `TripRepository`).
- Centralise the duplicated platform-directory resolution and the
  `shared_preferences` keys.
- Collapse formatting to a single source (`units.dart`).
- Introduce an `InheritedNotifier` for theme/settings to remove constructor
  prop-drilling (and fix pushed screens not live-updating on theme change).

See [`docs/roadmap-priorities.org`](./roadmap-priorities.org) for status.
