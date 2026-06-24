import 'dart:io';

import 'units.dart';

/// One recorded point: position plus the fused elevation at capture time.
class TrackPoint {
  const TrackPoint({
    required this.latitude,
    required this.longitude,
    required this.elevation,
    required this.time,
  });

  final double latitude;
  final double longitude;
  final double elevation;

  /// Capture time; written to the GPX in UTC.
  final DateTime time;
}

/// A finished recording, ready to serialise. Segments mirror the GPX
/// `<trkseg>`s (a gap, pause, or re-anchor opens a new one).
class TripRecording {
  const TripRecording({
    required this.segments,
    required this.distanceMeters,
    required this.elevationGainMeters,
    required this.elapsed,
  });

  final List<List<TrackPoint>> segments;
  final double distanceMeters;
  final double elevationGainMeters;
  final Duration elapsed;

  bool get isEmpty => segments.every((s) => s.isEmpty);
}

/// Writes a recording to disk as a GPX track and a one-line CSV summary,
/// named `<stamp>.gpx` / `<stamp>.csv`. The write-side counterpart to
/// [TripRepository]: pure I/O and string building, unit-testable against a
/// temp directory.
class TripWriter {
  const TripWriter(this.directory);

  final Directory directory;

  /// Write the GPX + CSV for [trip]. Returns false (writing nothing) when the
  /// recording has no points.
  Future<bool> write(TripRecording trip, String stamp) async {
    if (trip.isEmpty) return false;
    await _writeGpx(trip, stamp);
    await _writeCsv(trip, stamp);
    return true;
  }

  Future<void> _writeGpx(TripRecording trip, String stamp) async {
    final buf = StringBuffer()
      ..writeln('<?xml version="1.0" encoding="UTF-8"?>')
      ..writeln(
        '<gpx version="1.1" creator="Err" xmlns="http://www.topografix.com/GPX/1/1">',
      )
      ..writeln('  <trk>')
      ..writeln('    <name>Track $stamp</name>');
    for (final segment in trip.segments) {
      if (segment.isEmpty) continue;
      buf.writeln('    <trkseg>');
      for (final p in segment) {
        buf
          ..writeln('      <trkpt lat="${p.latitude}" lon="${p.longitude}">')
          ..writeln('        <ele>${p.elevation.toStringAsFixed(2)}</ele>')
          ..writeln('        <time>${p.time.toUtc().toIso8601String()}</time>')
          ..writeln('      </trkpt>');
      }
      buf.writeln('    </trkseg>');
    }
    buf
      ..writeln('  </trk>')
      ..writeln('</gpx>');
    await File('${directory.path}/$stamp.gpx').writeAsString(buf.toString());
  }

  Future<void> _writeCsv(TripRecording trip, String stamp) async {
    final distKm = (trip.distanceMeters / 1000).toStringAsFixed(3);
    final elevM = trip.elevationGainMeters.toStringAsFixed(1);
    final time = formatDuration(trip.elapsed);
    final csv =
        'distance_km,elevation_gain_m,total_time\n$distKm,$elevM,$time\n';
    await File('${directory.path}/$stamp.csv').writeAsString(csv);
  }
}
