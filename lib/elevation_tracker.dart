import 'dart:math';

/// Fuses barometric and GPS altitude into a single stream that drives both
/// the on-screen elevation gain and the elevations written to the GPX file,
/// so the two always agree.
///
/// Mirrors what Strava/Garmin do on-device:
/// - The barometer provides *relative* altitude change (~0.5 m resolution);
///   GPS anchors it to an *absolute* reference once, via a median offset
///   frozen early in the activity so later reference switches between
///   location providers (MSL vs WGS84 ellipsoid, ~33 m apart) can't bend it.
/// - Samples are smoothed with an exponential moving average so transient
///   pressure spikes (wind gusts, pocket handling) never reach the gain
///   accumulator.
/// - Gain uses a sustained-climb hysteresis: a running local minimum (the
///   "floor") follows every descent, and a climb only starts counting once
///   the smoothed altitude rises a full threshold above that floor. While a
///   climb is active every new high accrues, so slow steady ascents are
///   captured in full; the climb ends after a threshold-sized descent.
///   Symmetric noise never confirms a climb and never counts.
class ElevationTracker {
  /// EMA smoothing factor per accepted sample (samples arrive every 1–3 s).
  static const double _smoothing = 0.3;

  /// Minimum sustained rise before gain is committed.
  static const double baroGainThreshold = 3.0;
  static const double gpsGainThreshold = 10.0;

  /// A GPS altitude step this large between consecutive fixes is a reference
  /// switch between location providers, not terrain.
  static const double _gpsJumpThreshold = 25.0;

  /// GPS fixes collected (as gps − baro offsets) before the barometric
  /// calibration is frozen at their median.
  static const int _calibrationSamples = 5;

  /// International barometric formula: pressure (hPa) → altitude (m).
  static double pressureToAltitude(double hPa) =>
      44330.0 * (1.0 - pow(hPa / 1013.25, 1.0 / 5.255));

  double gainMeters = 0;
  bool baroAvailable = false;

  /// Optional hook for the debug tools — receives one-line event messages
  /// (calibration frozen, reference rebase, climb confirmed/ended).
  void Function(String message)? onEvent;

  /// The fused, smoothed altitude — written to the GPX as `<ele>`.
  /// Null until the first sample (or, with a barometer, until calibrated).
  double? get currentAltitude => _smoothed;

  double? _smoothed; // EMA of fused altitude
  double? _floor; // running local minimum while not climbing
  double? _climbHigh; // highest altitude of the active climb, null if none
  double? _lastRawBaro; // latest raw barometric altitude
  double? _baroOffset; // gps − baro, frozen after calibration
  final List<double> _calibration = [];
  double? _lastGpsAlt;
  DateTime? _lastBaroTime;
  int _rebases = 0;

  /// Read-only view of internal state for the debug tools.
  Map<String, Object?> debugSnapshot() => {
        'fused': _smoothed,
        'floor': _floor,
        'climbing': _climbHigh != null,
        'climb-high': _climbHigh,
        'gain': gainMeters,
        'baro': baroAvailable,
        'offset': _baroOffset,
        'cal-n': _calibration.length,
        'rebases': _rebases,
      };

  void addBarometer(double rawAltitude, DateTime time) {
    // samplingPeriod is only a hint to the OS — throttle to 1 Hz ourselves.
    if (_lastBaroTime != null &&
        time.difference(_lastBaroTime!).inMilliseconds < 1000) {
      return;
    }
    _lastBaroTime = time;
    baroAvailable = true;
    _lastRawBaro = rawAltitude;
    if (_baroOffset == null) return; // not yet anchored to GPS
    _update(rawAltitude + _baroOffset!, baroGainThreshold);
  }

  void addGps(double altitude, double altitudeAccuracy) {
    if (baroAvailable) {
      // The barometer drives altitude; GPS only anchors the absolute offset.
      // The looser 30 m gate is fine here — the median of several fixes
      // absorbs the noise, and the offset only shifts the whole track.
      if (_baroOffset == null &&
          _lastRawBaro != null &&
          (altitudeAccuracy <= 0 || altitudeAccuracy < 30.0)) {
        _calibration.add(altitude - _lastRawBaro!);
        if (_calibration.length >= _calibrationSamples) {
          final sorted = [..._calibration]..sort();
          _baroOffset = sorted[sorted.length ~/ 2];
          onEvent?.call('BARO calibrated — offset '
              '${_baroOffset!.toStringAsFixed(1)} m '
              '(median of $_calibrationSamples fixes)');
        }
      }
      return;
    }

    // GPS-only fallback (no barometer on this device).
    if (altitudeAccuracy > 0 && altitudeAccuracy >= 15.0) return;
    if (_lastGpsAlt != null &&
        (altitude - _lastGpsAlt!).abs() > _gpsJumpThreshold) {
      // Reference switch — rebase without counting it as climb or descent.
      _rebases++;
      onEvent?.call('REBASE — GPS altitude jumped '
          '${(altitude - _lastGpsAlt!).toStringAsFixed(1)} m '
          '(reference switch, not counted)');
      _lastGpsAlt = altitude;
      _smoothed = altitude;
      _floor = altitude;
      _climbHigh = null;
      return;
    }
    _lastGpsAlt = altitude;
    _update(altitude, gpsGainThreshold);
  }

  void _update(double altitude, double threshold) {
    _smoothed = _smoothed == null
        ? altitude
        : _smoothed! + _smoothing * (altitude - _smoothed!);
    final alt = _smoothed!;

    if (_climbHigh == null) {
      // Not climbing: the floor tracks every descent for free; a full
      // threshold of rise above it confirms a climb and banks the rise.
      if (_floor == null || alt < _floor!) {
        _floor = alt;
      } else if (alt - _floor! >= threshold) {
        gainMeters += alt - _floor!;
        _climbHigh = alt;
        onEvent?.call('CLIMB confirmed — banked '
            '${(alt - _floor!).toStringAsFixed(1)} m');
      }
    } else if (alt > _climbHigh!) {
      // Climbing: every new high counts, so slow ascents accrue in full.
      gainMeters += alt - _climbHigh!;
      _climbHigh = alt;
    } else if (_climbHigh! - alt >= threshold) {
      // A full threshold of descent ends the climb.
      _climbHigh = null;
      _floor = alt;
      onEvent?.call('CLIMB ended — total gain now '
          '${gainMeters.toStringAsFixed(1)} m');
    }
  }
}
