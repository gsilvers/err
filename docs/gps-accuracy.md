# GPS Accuracy

This document explains how Err filters and processes raw GPS and sensor data to
produce distance and elevation numbers that are comparable to apps like Strava
or Garmin.

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

## What Strava does

Strava uses three techniques:

1. **Barometric altimeter blending** — modern phones have a pressure sensor;
   barometric altitude changes are far smoother than GPS altitude (~0.5 m
   resolution vs. 10–20 m for GPS).
2. **Server-side DEM correction** — recorded tracks are matched against a
   terrain database and elevation is replaced with known ground truth.
3. **Minimum sustained-gain filter** — only altitude climbs above a threshold
   count, preventing transient spikes from accumulating.

Err is a local, offline app with no server component, so technique #2 is out of
scope. Err implements #1 and #3.

---

## How Err filters GPS and sensor data

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
25 m accepts open-sky fixes (typically 3–10 m) while rejecting degraded ones.

```dart
if (pos.accuracy > 25) return;
```

### 3. Fused Location Provider on Android

**Problem:** The legacy Android `LocationManager` API is GPS-only. Google's
Fused Location Provider (FLP) is smarter — it blends GPS, Wi-Fi, cell-tower,
barometer, and motion sensors, producing lower-noise positions especially in
difficult environments.

**Fix:** Do not set `forceLocationManager: true`. FLP is used by default,
and the stale-position timestamp gate (#1) handles the cache concern that
previously motivated the override.

### 4. Barometric altimeter for elevation (primary source)

**Problem:** GPS altitude has 10–20 m of noise even under ideal conditions.
With a naive 2 m minimum change, roughly half of all position updates trip the
threshold from random noise alone — accumulating 500–1 000 m of phantom
elevation gain on completely flat terrain over a 30-minute activity.

**Fix:** Err uses the device's barometric pressure sensor as the primary source
for elevation gain. Pressure changes are converted to altitude using the
international barometric formula:

```
altitude (m) = 44330 × (1 − (P / 1013.25) ^ (1 / 5.255))
```

The sensor is sampled every 2 seconds. Elevation gain is accumulated when the
barometric altitude rises by more than **3 m** between samples — conservative
enough to filter pressure fluctuations from handling the device, but responsive
to real terrain.

```dart
double _pressureToAltitude(double hPa) =>
    44330.0 * (1.0 - pow(hPa / 1013.25, 1.0 / 5.255));

// In _onBarometer:
if (altDiff > 3.0) _elevationGainMeters += altDiff;
```

The barometric sensor is present on all modern iPhones and the vast majority of
Android devices (including all Pixel models). If the sensor is unavailable, Err
falls back to GPS altitude with a stricter 10 m threshold (see §5).

During the GPS-wait phase the barometer anchor is kept current, so the first
elevation delta after lock is computed from a clean baseline.

### 5. GPS altitude fallback (barometer unavailable)

When `_baroAvailable` is false — meaning no barometer reading has been received
yet — GPS altitude is used with a **10 m minimum threshold**.

**Back-of-envelope showing why 2 m was wrong (flat 5 km run):**

```
600 updates × ~50% trigger rate × ~3 m average phantom gain ≈ 900 m phantom gain
```

10 m matches Garmin's default minimum and is sufficient to filter random GPS
vertical jitter while still registering genuine terrain climbs.

```dart
if (!_baroAvailable) {
  final altDiff = pos.altitude - _lastPosition!.altitude;
  final accuracyOk = pos.altitudeAccuracy <= 0 || pos.altitudeAccuracy < 15.0;
  if (altDiff > 10.0 && accuracyOk) _elevationGainMeters += altDiff;
}
```

### 6. Altitude accuracy gate

`pos.altitudeAccuracy` (iOS 15+ / Android 14+) reports the estimated vertical
error in metres. If available and worse than 15 m, the GPS fix is excluded from
the fallback elevation calculation. On older OS versions where this field is not
populated, `altitudeAccuracy` is reported as ≤ 0 and the gate is skipped — the
10 m threshold in §5 is the primary guard in that case.

---

## Filter pipeline summary

```
raw barometer reading (every 2 s)
    │
    ├─ !_gpsReady?  → update anchor only, no gain accumulated
    │
    └─ altDiff > 3 m?  → add to elevation gain
                       → mark _baroAvailable = true


raw GPS fix
    │
    ├─ pos.accuracy > 25 m?  → discard
    │
    ├─ pos.timestamp < startTime − 5 s?  → discard (stale cache, start only)
    │
    ├─ distance: Haversine to previous fix → add to distance
    │
    └─ elevation (only when !_baroAvailable):
           altDiff > 10 m AND accuracyOk?  → add to elevation gain
```

---

## Elevation source priority

| Priority | Source | Accuracy | Threshold |
|---|---|---|---|
| 1 (preferred) | Barometric pressure sensor | ~0.5 m | 3 m gain |
| 2 (fallback) | GPS altitude | 10–40 m | 10 m gain |

---

## Remaining limitations

- **Absolute barometric drift** — atmospheric pressure changes with weather
  (~1 hPa/hr in a moving storm front ≈ ~8 m/hr of apparent altitude change).
  For activities under ~3 hours this is negligible. For all-day hikes a
  server-side DEM correction would eliminate it.
- **Device handling pressure** — squeezing a phone can transiently raise
  internal pressure. The 3 m threshold filters most of these but not all.
  A short rolling average over the barometric readings would help; left as a
  future improvement.
- **Speed sanity filter** — GPS teleportation events (two fixes implying an
  impossible speed) are not yet detected. Adding a check for implied speed
  > 50 m/s would be a small additional improvement to distance accuracy.
