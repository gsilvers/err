/// Unit formatting shared by the live tracker and the statistics screen, so
/// distances, elevations, durations and speeds read the same everywhere and
/// honour the one metric/imperial preference.
///
/// All inputs are SI (metres, metres/second, [Duration]); the imperial flag
/// only changes presentation. The summary CSVs are stored in SI, so callers
/// never have to convert before formatting.
library;

const double _metersPerFoot = 0.3048;
const double _metersPerMile = 1609.344;

/// Distance for totals: always km/mi (no metres/feet fallback). Suited to the
/// large numbers on the stats screen, where 0 m vs 80 m precision is moot.
String formatDistance(double meters, {required bool imperial}) {
  if (imperial) {
    return '${(meters / _metersPerMile).toStringAsFixed(2)} mi';
  }
  return '${(meters / 1000).toStringAsFixed(2)} km';
}

/// Cumulative elevation gain, rounded to whole feet/metres.
String formatElevation(double meters, {required bool imperial}) {
  if (imperial) {
    return '${(meters / _metersPerFoot).toStringAsFixed(0)} ft';
  }
  return '${meters.toStringAsFixed(0)} m';
}

/// H:MM:SS, with hours allowed to grow unbounded so yearly totals (hundreds
/// of hours) still render in one field.
String formatDuration(Duration d) {
  final h = d.inHours;
  final m = (d.inMinutes % 60).toString().padLeft(2, '0');
  final s = (d.inSeconds % 60).toString().padLeft(2, '0');
  return '${h.toString().padLeft(2, '0')}:$m:$s';
}

/// Instantaneous speed, one decimal. Negative inputs (geolocator's "unknown"
/// sentinel) clamp to zero.
String formatSpeed(double metersPerSecond, {required bool imperial}) {
  final v = metersPerSecond < 0 ? 0.0 : metersPerSecond;
  if (imperial) {
    return '${(v / _metersPerMile * 3600).toStringAsFixed(1)} mph';
  }
  return '${(v * 3.6).toStringAsFixed(1)} km/h';
}
