import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'trip_summary.dart';

/// Reads recorded activities back from disk and aggregates them.
///
/// The saved files are the source of truth — there is no database. Each call
/// to [loadAll] re-scans the directory, so a trip the user copied in or
/// deleted by hand is reflected immediately. Only the one-line summary CSVs
/// are read (never the GPX bodies), so scanning hundreds of trips is cheap.
class TripRepository {
  TripRepository(this.directory);

  final Directory directory;

  /// Resolve the same directory the tracker saves into: external storage on
  /// Android, the documents dir elsewhere.
  static Future<TripRepository> open() async {
    final dir = (Platform.isAndroid
            ? await getExternalStorageDirectory()
            : null) ??
        await getApplicationDocumentsDirectory();
    return TripRepository(dir);
  }

  /// All trips, newest first. Unparseable or partial files are skipped rather
  /// than aborting the scan.
  Future<List<TripSummary>> loadAll() async {
    if (!await directory.exists()) return [];

    final trips = <TripSummary>[];
    await for (final entity in directory.list()) {
      if (entity is! File) continue;
      final name = entity.uri.pathSegments.last;
      if (!isSummaryCsv(name)) continue;
      try {
        final summary = parseSummary(
          fileName: name,
          content: await entity.readAsString(),
          csvPath: entity.path,
        );
        if (summary != null) trips.add(summary);
      } catch (_) {
        // Corrupt file — leave it on disk, just don't list it.
      }
    }

    trips.sort((a, b) => b.date.compareTo(a.date));
    return trips;
  }

  /// Delete a trip's files (summary CSV, GPX track, and any debug recording).
  /// Missing siblings are ignored so a partially-deleted trip still clears.
  Future<void> delete(TripSummary trip) async {
    final stamp = stampOf(trip.csvPath);
    for (final path in [
      trip.csvPath,
      trip.gpxPath,
      '${directory.path}/$stamp-debug.csv',
    ]) {
      final f = File(path);
      if (await f.exists()) await f.delete();
    }
  }

  // ── Parsing (pure, unit-testable) ─────────────────────────────────────────

  /// A real summary CSV, excluding the `-debug.csv` flight recordings that
  /// share the `.csv` extension.
  static bool isSummaryCsv(String name) =>
      name.endsWith('.csv') && !name.endsWith('-debug.csv');

  /// The timestamp portion of a saved file path (`…/2026-06-22T14-30-45.csv`
  /// → `2026-06-22T14-30-45`).
  static String stampOf(String path) {
    final name = path.split('/').last;
    return name.endsWith('.csv') ? name.substring(0, name.length - 4) : name;
  }

  /// `2026-06-22T14-30-45` → local [DateTime]. The date half uses real ISO
  /// dashes; the time half's dashes were colons (filenames can't contain `:`),
  /// so only those are restored. Returns null if the stamp isn't a timestamp.
  static DateTime? parseStamp(String stamp) {
    final t = stamp.split('T');
    if (t.length != 2) return null;
    return DateTime.tryParse('${t[0]}T${t[1].replaceAll('-', ':')}');
  }

  /// Parse one summary CSV. [fileName] supplies the date; [content] supplies
  /// the metrics (`distance_km,elevation_gain_m,total_time`). Returns null if
  /// either is malformed.
  static TripSummary? parseSummary({
    required String fileName,
    required String content,
    required String csvPath,
  }) {
    final date = parseStamp(stampOf(fileName));
    if (date == null) return null;

    final lines = content.trim().split('\n');
    if (lines.length < 2) return null;
    final cells = lines[1].split(',');
    if (cells.length < 3) return null;

    final distanceKm = double.tryParse(cells[0].trim());
    final gain = double.tryParse(cells[1].trim());
    final duration = _parseHms(cells[2].trim());
    if (distanceKm == null || gain == null || duration == null) return null;

    return TripSummary(
      date: date,
      distanceMeters: distanceKm * 1000,
      elevationGainMeters: gain,
      duration: duration,
      gpxPath: '${csvPath.substring(0, csvPath.length - 4)}.gpx',
      csvPath: csvPath,
    );
  }

  static Duration? _parseHms(String hms) {
    final parts = hms.split(':');
    if (parts.length != 3) return null;
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    final s = int.tryParse(parts[2]);
    if (h == null || m == null || s == null) return null;
    return Duration(hours: h, minutes: m, seconds: s);
  }
}

/// Running total over a set of trips. Mutable so callers can fold into it.
class StatsBucket {
  int tripCount = 0;
  double distanceMeters = 0;
  double elevationGainMeters = 0;
  Duration duration = Duration.zero;

  void add(TripSummary t) {
    tripCount++;
    distanceMeters += t.distanceMeters;
    elevationGainMeters += t.elevationGainMeters;
    duration += t.duration;
  }
}

/// Aggregations over a loaded trip list. Pure and synchronous — the screen
/// loads once, then asks this for each view. [reference] defaults to now and
/// is injectable for tests.
class TripStats {
  TripStats(this.trips, {DateTime? reference})
      : reference = reference ?? DateTime.now();

  final List<TripSummary> trips;
  final DateTime reference;

  StatsBucket get thisMonth => _fold((t) =>
      t.date.year == reference.year && t.date.month == reference.month);

  StatsBucket get thisYear =>
      _fold((t) => t.date.year == reference.year);

  StatsBucket get allTime => _fold((_) => true);

  /// Per-year totals, most recent year first — this is the year-over-year view.
  List<MapEntry<int, StatsBucket>> get byYear {
    final byYear = <int, StatsBucket>{};
    for (final t in trips) {
      (byYear[t.date.year] ??= StatsBucket()).add(t);
    }
    final years = byYear.keys.toList()..sort((a, b) => b.compareTo(a));
    return [for (final y in years) MapEntry(y, byYear[y]!)];
  }

  StatsBucket _fold(bool Function(TripSummary) test) {
    final bucket = StatsBucket();
    for (final t in trips) {
      if (test(t)) bucket.add(t);
    }
    return bucket;
  }
}
