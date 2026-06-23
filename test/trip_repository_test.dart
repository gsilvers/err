import 'dart:io';

import 'package:err/trip_repository.dart';
import 'package:err/trip_summary.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('isSummaryCsv', () {
    test('accepts a summary CSV', () {
      expect(TripRepository.isSummaryCsv('2026-06-22T14-30-45.csv'), isTrue);
    });

    test('excludes the debug flight recording', () {
      expect(
        TripRepository.isSummaryCsv('2026-06-22T14-30-45-debug.csv'),
        isFalse,
      );
    });

    test('excludes the GPX track', () {
      expect(TripRepository.isSummaryCsv('2026-06-22T14-30-45.gpx'), isFalse);
    });
  });

  group('parseStamp', () {
    test('restores only the time-half colons', () {
      final d = TripRepository.parseStamp('2026-06-22T14-30-45');
      expect(d, DateTime(2026, 6, 22, 14, 30, 45));
      expect(d!.isUtc, isFalse); // local, so month/year buckets match wall clock
    });

    test('returns null for a non-timestamp name', () {
      expect(TripRepository.parseStamp('garbage'), isNull);
    });
  });

  group('parseSummary', () {
    test('parses a well-formed summary', () {
      final t = TripRepository.parseSummary(
        fileName: '2026-06-22T14-30-45.csv',
        content: 'distance_km,elevation_gain_m,total_time\n'
            '1.234,56.7,01:23:45\n',
        csvPath: '/data/2026-06-22T14-30-45.csv',
      )!;
      expect(t.date, DateTime(2026, 6, 22, 14, 30, 45));
      expect(t.distanceMeters, closeTo(1234, 0.001));
      expect(t.elevationGainMeters, closeTo(56.7, 0.001));
      expect(t.duration, const Duration(hours: 1, minutes: 23, seconds: 45));
      expect(t.gpxPath, '/data/2026-06-22T14-30-45.gpx');
    });

    test('returns null when the data row is missing', () {
      final t = TripRepository.parseSummary(
        fileName: '2026-06-22T14-30-45.csv',
        content: 'distance_km,elevation_gain_m,total_time\n',
        csvPath: '/data/2026-06-22T14-30-45.csv',
      );
      expect(t, isNull);
    });

    test('returns null when a metric is not a number', () {
      final t = TripRepository.parseSummary(
        fileName: '2026-06-22T14-30-45.csv',
        content: 'distance_km,elevation_gain_m,total_time\n'
            'oops,56.7,01:23:45\n',
        csvPath: '/data/2026-06-22T14-30-45.csv',
      );
      expect(t, isNull);
    });
  });

  group('TripStats', () {
    final trips = [
      _trip(DateTime(2026, 6, 10), distM: 5000, gainM: 100, dur: 3600),
      _trip(DateTime(2026, 3, 1), distM: 8000, gainM: 200, dur: 5400),
      _trip(DateTime(2025, 7, 15), distM: 10000, gainM: 300, dur: 7200),
    ];
    final stats = TripStats(trips, reference: DateTime(2026, 6, 22));

    test('thisMonth covers only the current month', () {
      expect(stats.thisMonth.tripCount, 1);
      expect(stats.thisMonth.distanceMeters, 5000);
    });

    test('thisYear sums every trip in the current year', () {
      expect(stats.thisYear.tripCount, 2);
      expect(stats.thisYear.distanceMeters, 13000);
      expect(stats.thisYear.elevationGainMeters, 300);
      expect(stats.thisYear.duration, const Duration(seconds: 9000));
    });

    test('byYear is grouped, newest year first', () {
      final years = stats.byYear;
      expect(years.map((e) => e.key).toList(), [2026, 2025]);
      expect(years.first.value.tripCount, 2);
      expect(years.last.value.distanceMeters, 10000);
    });

    test('allTime spans every trip', () {
      expect(stats.allTime.tripCount, 3);
      expect(stats.allTime.distanceMeters, 23000);
    });
  });

  group('loadAll + delete (temp dir)', () {
    late Directory dir;
    late TripRepository repo;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('err_trips_');
      repo = TripRepository(dir);
      await _write(dir, '2026-06-22T14-30-45.csv',
          'distance_km,elevation_gain_m,total_time\n2.0,50.0,00:30:00\n');
      await _write(dir, '2026-06-22T14-30-45.gpx', '<gpx/>');
      await _write(dir, '2026-06-22T14-30-45-debug.csv', 'raw,debug\n1,2\n');
      await _write(dir, '2025-01-01T08-00-00.csv',
          'distance_km,elevation_gain_m,total_time\n3.0,90.0,01:00:00\n');
      await _write(dir, 'garbage.csv', 'not a trip');
    });

    tearDown(() async {
      if (await dir.exists()) await dir.delete(recursive: true);
    });

    test('lists valid trips newest-first, skipping debug/gpx/garbage',
        () async {
      final trips = await repo.loadAll();
      expect(trips.length, 2);
      expect(trips.first.date.year, 2026);
      expect(trips.last.date.year, 2025);
    });

    test('delete removes the csv, gpx and debug siblings', () async {
      final trips = await repo.loadAll();
      await repo.delete(trips.first); // the 2026 trip

      expect(
        File('${dir.path}/2026-06-22T14-30-45.csv').existsSync(),
        isFalse,
      );
      expect(
        File('${dir.path}/2026-06-22T14-30-45.gpx').existsSync(),
        isFalse,
      );
      expect(
        File('${dir.path}/2026-06-22T14-30-45-debug.csv').existsSync(),
        isFalse,
      );
      expect((await repo.loadAll()).length, 1);
    });
  });
}

TripSummary _trip(DateTime date,
        {required double distM, required double gainM, required int dur}) =>
    TripSummary(
      date: date,
      distanceMeters: distM,
      elevationGainMeters: gainM,
      duration: Duration(seconds: dur),
      gpxPath: '',
      csvPath: '',
    );

Future<void> _write(Directory dir, String name, String content) =>
    File('${dir.path}/$name').writeAsString(content);
