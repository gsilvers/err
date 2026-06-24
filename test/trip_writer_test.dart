import 'dart:io';

import 'package:err/trip_repository.dart';
import 'package:err/trip_writer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('err_writer_');
  });

  tearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  TripRecording recording({List<List<TrackPoint>>? segments}) => TripRecording(
    segments:
        segments ??
        [
          [
            TrackPoint(
              latitude: 1.5,
              longitude: -2.5,
              elevation: 100.0,
              time: DateTime.utc(2026, 6, 23, 12),
            ),
          ],
          [
            TrackPoint(
              latitude: 1.6,
              longitude: -2.6,
              elevation: 110.456,
              time: DateTime.utc(2026, 6, 23, 12, 5),
            ),
          ],
        ],
    distanceMeters: 1234.0,
    elevationGainMeters: 56.7,
    elapsed: const Duration(hours: 1, minutes: 23, seconds: 45),
  );

  const stamp = '2026-06-23T12-00-00';

  test('writes a GPX with one trkseg per non-empty segment', () async {
    await TripWriter(dir).write(recording(), stamp);
    final gpx = await File('${dir.path}/$stamp.gpx').readAsString();

    expect('<trkseg>'.allMatches(gpx).length, 2);
    expect(gpx, contains('creator="Err"'));
    expect(gpx, contains('<trkpt lat="1.5" lon="-2.5">'));
    expect(gpx, contains('<ele>110.46</ele>')); // 2 decimals
    expect(gpx, contains('<time>2026-06-23T12:00:00.000Z</time>')); // UTC
  });

  test('writes a one-line CSV summary', () async {
    await TripWriter(dir).write(recording(), stamp);
    final csv = await File('${dir.path}/$stamp.csv').readAsString();
    expect(csv, 'distance_km,elevation_gain_m,total_time\n1.234,56.7,01:23:45\n');
  });

  test('writes nothing for an all-empty recording', () async {
    final wrote = await TripWriter(
      dir,
    ).write(recording(segments: [[], []]), stamp);
    expect(wrote, isFalse);
    expect(File('${dir.path}/$stamp.gpx').existsSync(), isFalse);
    expect(File('${dir.path}/$stamp.csv').existsSync(), isFalse);
  });

  test('the CSV it writes round-trips through TripRepository', () async {
    await TripWriter(dir).write(recording(), stamp);
    final csv = await File('${dir.path}/$stamp.csv').readAsString();
    final summary = TripRepository.parseSummary(
      fileName: '$stamp.csv',
      content: csv,
      csvPath: '${dir.path}/$stamp.csv',
    )!;
    expect(summary.distanceMeters, closeTo(1234, 0.001));
    expect(summary.elevationGainMeters, closeTo(56.7, 0.001));
    expect(summary.duration, const Duration(hours: 1, minutes: 23, seconds: 45));
  });
}
