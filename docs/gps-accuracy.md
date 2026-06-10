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

### 4. Teleport rejection (distance)

**Problem:** Location providers occasionally emit a fix far from the true
position — a cached fix, a Wi-Fi-derived position, or a multipath glitch.
Connecting it to its neighbours adds a phantom out-and-back spike to distance.

**Fix:** A fix whose *implied* speed (distance from the previous fix divided
by the time gap) exceeds `max(3 × pos.speed, 15 m/s)` is rejected. The GPS
receiver's own Doppler-derived `pos.speed` is far more reliable than
position differences, so a large disagreement means the position jumped, not
the user. Three consecutive rejections mean the previous *anchor* point was
the glitch — recording re-anchors at the current fix in a new GPX segment,
counting nothing.

### 5. Fused elevation — one altitude stream for the UI *and* the GPX

**Problem (what v0.1 got wrong):** the on-screen gain came from the barometer
while the GPX stored raw GPS altitude — two unrelated data streams that could
disagree wildly (1 000 ft on screen vs 21 ft from the file). The barometer
algorithm was also a one-way ratchet: any transient pressure spike > 3 m
(wind gust, pocket handling) was banked permanently, while real slow climbs
below the per-sample threshold counted as zero.

Raw GPS altitude in the GPX had its own failure: Android location providers
mix two *reference frames* — MSL and the WGS84 ellipsoid, ~33 m apart in the
eastern US. A provider switch mid-activity shows up as an instant 33 m cliff
that is not real terrain.

**Fix:** all altitude data now flows through `ElevationTracker`
(`lib/elevation_tracker.dart`), which produces a single fused altitude stream
used for both the gain figure on screen and the `<ele>` values written to the
GPX — the two agree by construction.

The tracker mirrors what Strava/Garmin do on-device:

1. **Barometer for relative change, GPS for absolute anchor.** Pressure is
   converted with the international barometric formula
   (`44330 × (1 − (P/1013.25)^(1/5.255))`) and offset into the GPS frame by
   the *median* of the first 5 `(gps − baro)` differences, then frozen for
   the activity — later provider reference switches cannot bend the track.
   Samples are throttled to 1 Hz (the platform `samplingPeriod` is only a
   hint).
2. **EMA smoothing** (α = 0.3) so a transient spike never reaches the gain
   accumulator at full size.
3. **Sustained-climb hysteresis.** While not climbing, a running local
   minimum (the floor) follows every descent for free. A climb only starts
   counting once the smoothed altitude rises a full threshold — **3 m**
   (barometer) or **10 m** (GPS fallback) — above that floor. While a climb
   is active, every new high accrues, so slow steady ascents are captured in
   full; a threshold-sized descent ends the climb. Symmetric noise never
   confirms a climb and never counts.

### 6. GPS altitude fallback (no barometer)

When no barometer reading arrives, the tracker feeds smoothed GPS altitude
through the same hysteresis with the stricter 10 m threshold, plus:

- **Altitude accuracy gate** — fixes with `pos.altitudeAccuracy` ≥ 15 m are
  excluded (where the field is populated; ≤ 0 means unavailable and is
  allowed through).
- **Reference-switch guard** — a jump of more than 25 m between consecutive
  fixes is treated as a provider reference switch, not terrain: the tracker
  rebases to the new altitude without counting any gain.

---

## Filter pipeline summary

```
raw barometer reading
    │
    ├─ < 1 s since last sample?  → discard (throttle)
    ├─ no GPS calibration yet?   → record raw altitude only
    └─ fused alt = raw + frozen median(gps − baro)
           → EMA smooth → sustained-climb hysteresis (3 m) → gain


raw GPS fix
    │
    ├─ pos.accuracy > 25 m?  → discard
    ├─ pos.timestamp < startTime − 5 s?  → discard (stale cache, start only)
    ├─ implied speed > max(3 × pos.speed, 15 m/s)?  → reject
    │      (3 in a row → re-anchor in a new segment)
    ├─ gap > 60 s since previous fix?  → new GPX segment, no distance
    ├─ distance: Haversine to previous fix → add to distance
    └─ altitude → ElevationTracker:
           barometer active?  → calibrate offset only
           otherwise          → accuracy gate → 25 m jump guard
                              → EMA smooth → hysteresis (10 m) → gain

GPX <ele> = the tracker's fused altitude at each recorded point,
so gain recomputed from the file matches the gain shown in the app.
```

---

## Elevation source priority

| Priority | Source | Accuracy | Climb threshold |
|---|---|---|---|
| 1 (preferred) | Barometer (GPS-anchored, smoothed) | ~0.5 m | 3 m sustained |
| 2 (fallback) | GPS altitude (smoothed, jump-guarded) | 10–40 m | 10 m sustained |

---

## Remaining limitations

- **Absolute barometric drift** — atmospheric pressure changes with weather
  (~1 hPa/hr in a moving storm front ≈ ~8 m/hr of apparent altitude change).
  The sustained-climb filter absorbs most of it; for all-day hikes a
  server-side DEM correction would eliminate it entirely, but that requires
  infrastructure Err deliberately does not have.
- **Climbs smaller than the threshold** — rolling terrain with hills under
  3 m (barometer) or 10 m (GPS) of relief records no gain. This matches
  Strava/Garmin behaviour, which flatten the same micro-terrain.
- **Frozen calibration** — the baro↔GPS offset is fixed early in the
  activity. Absolute elevations in the GPX can be off by the initial GPS
  vertical error (~5–10 m); relative changes — and therefore gain — are
  unaffected.
