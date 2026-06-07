# GPS Accuracy

This document explains how Err filters and processes raw GPS data to produce
distance and elevation numbers that are comparable to apps like Strava or Garmin.

---

## The problem with raw GPS

A phone's GPS receiver emits a new position fix every few seconds. Each fix
carries two kinds of error that, if ignored, inflate both distance and elevation:

| Error type | Typical magnitude | Effect if ignored |
|---|---|---|
| Horizontal position noise | 3–30 m (varies with sky view) | Phantom distance when points zigzag |
| Vertical (altitude) noise | 10–40 m | Phantom elevation gain on flat ground |

Consumer GPS chips are 2–4× less accurate vertically than horizontally, because
satellites are all above you — there is no geometry below. A fix with 8 m of
horizontal accuracy may have 20–30 m of vertical error.

---

## What Strava does (and why we can't do all of it)

Strava uses three techniques:

1. **Barometric altimeter blending** — modern phones have a pressure sensor;
   barometric altitude changes are much smoother than GPS altitude.
2. **Server-side DEM correction** — recorded tracks are matched against a
   terrain database and elevation is replaced with known ground truth.
3. **Minimum sustained-gain filter** — only altitude climbs above a threshold
   count, preventing transient spikes from accumulating.

Err is a local, offline app with no server component, so technique #2 is out of
scope. Technique #1 is possible via the `sensors_plus` package but adds
complexity; it is left as a future improvement. Err implements technique #3
along with the accuracy filters described below.

---

## How Err filters GPS data

### 1. Stale-position gate (trip start)

**Problem:** The platform location stream often emits the device's last cached
position as its first event. That cached fix may be minutes or hours old. Using
it as the trip's starting anchor, then connecting it to the first real satellite
fix, produces a huge phantom distance at the start of every recording.

**Fix:** On start, `_startTime` is recorded. `_onPosition` discards any fix
whose `timestamp` is more than 5 seconds before `_startTime`. The trip only
begins — timer starts, distance accumulates — when the first fresh fix arrives.
The UI shows "Waiting for GPS lock…" during this window.

```dart
final staleThreshold = _startTime!.subtract(const Duration(seconds: 5));
if (pos.timestamp.isBefore(staleThreshold)) return;
```

### 2. Horizontal accuracy gate

**Problem:** When GPS signal is weak (urban canyons, dense tree cover, indoors),
`pos.accuracy` — the estimated 1-sigma horizontal error radius — can reach
40–80 m. Connecting two such fixes may add 50–100 m of phantom distance even
when the user is standing still.

**Fix:** Any fix with `pos.accuracy > 25` metres is silently discarded.
25 m is a standard threshold used by most fitness apps; it accepts open-sky
fixes (typically 3–10 m) while rejecting degraded fixes.

```dart
if (pos.accuracy > 25) return;
```

### 3. Fused Location Provider on Android (no `forceLocationManager`)

**Problem:** The legacy Android `LocationManager` API is GPS-only. Google's
Fused Location Provider (FLP) is smarter — it blends GPS, Wi-Fi, cell-tower,
barometer, and motion sensors, producing lower-noise positions especially in
difficult environments.

The app previously forced the legacy provider (`forceLocationManager: true`) to
avoid receiving stale cached positions. That workaround is no longer necessary
because the stale-position gate (#1 above) handles the cache problem at the
stream level.

**Fix:** Remove `forceLocationManager: true` so Android uses FLP by default.

### 4. Elevation minimum threshold (10 m)

**Problem:** GPS altitude has 10–20 m of noise even under ideal conditions.
With a 2 m minimum change, roughly half of all position updates will show an
apparent upward gain due to random noise. Over a 30-minute activity (~600
updates at 3 s intervals), this accumulates 500–1 000 m of phantom elevation
gain on completely flat terrain.

**Back-of-envelope (flat 5 km run, old 2 m threshold):**

```
600 updates × ~50% trigger rate × ~3 m avg phantom gain ≈ 900 m phantom gain
```

**Fix:** Raise the minimum altitude change from 2 m to 10 m, matching Garmin's
default. Random GPS jitter rarely sustains a 10 m upward swing between
consecutive fixes, so only genuine terrain gains register.

```dart
// was: if (altDiff > 2.0 && accuracyOk)
if (altDiff > 10.0 && accuracyOk)
```

### 5. Altitude accuracy gate (existing)

`pos.altitudeAccuracy` (iOS 15+ / Android 14+) reports the estimated vertical
error in metres. If available and worse than 15 m, the fix is excluded from
elevation gain regardless of the altitude delta. On older OS versions that don't
populate this field, `altitudeAccuracy` is reported as ≤ 0 and the gate is
skipped (the threshold filter in #4 is the primary guard in that case).

```dart
final accuracyOk = pos.altitudeAccuracy <= 0 || pos.altitudeAccuracy < 15.0;
```

---

## Filter pipeline summary

```
raw GPS fix
    │
    ├─ pos.accuracy > 25 m?  → discard (horizontal noise)
    │
    ├─ pos.timestamp < startTime − 5 s?  → discard (stale cache, start only)
    │
    ├─ distance: Haversine between this fix and previous
    │
    └─ elevation:
           altDiff > 10 m?  → yes → accuracyOk?  → yes → add to gain
                                                 → no  → skip
                             → no  → skip
```

---

## Future improvements

- **Barometric altimeter** — integrate `sensors_plus` to read the pressure
  sensor and use barometric altitude changes instead of GPS altitude. This would
  reduce vertical noise to < 1 m under stable weather.
- **Outlier speed filter** — compute implied speed between consecutive fixes;
  discard segments where speed exceeds a plausible maximum (e.g., 50 m/s) to
  catch rare GPS teleportation events.
- **Smoothed elevation (Kalman or rolling window)** — apply a simple filter to
  the altitude series before computing gain, rather than relying solely on the
  minimum-change gate.
