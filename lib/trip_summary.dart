/// A single recorded activity, reconstructed from the per-trip summary CSV
/// that the tracker writes on Stop. The `.gpx`/`.csv` files on disk stay the
/// source of truth — this is just a parsed, in-memory view of one of them.
class TripSummary {
  TripSummary({
    required this.date,
    required this.distanceMeters,
    required this.elevationGainMeters,
    required this.duration,
    required this.gpxPath,
    required this.csvPath,
  });

  /// Local start time, taken from the file stamp (e.g. `2026-06-22T14-30-45`).
  /// Naive/local on purpose — month and year buckets should match the user's
  /// wall clock, not UTC.
  final DateTime date;

  final double distanceMeters;
  final double elevationGainMeters;
  final Duration duration;

  /// Absolute path to the GPX track. May not exist if the user deleted it
  /// out from under us; only read on demand.
  final String gpxPath;

  /// Absolute path to the summary CSV this trip was parsed from.
  final String csvPath;
}
