import 'package:err/debug/diagnostics.dart';
import 'package:err/debug/mini_lisp.dart';
import 'package:err/debug/repl_env.dart';
import 'package:err/elevation_tracker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';

Position fix({
  double lat = 40.62277,
  double lon = -75.36254,
  double acc = 8.2,
  double alt = 98.4,
  double speed = 1.38,
  DateTime? ts,
}) =>
    Position(
      latitude: lat,
      longitude: lon,
      timestamp: ts ?? DateTime.utc(2026, 6, 8, 11, 47, 18),
      accuracy: acc,
      altitude: alt,
      altitudeAccuracy: 11.0,
      heading: 0,
      headingAccuracy: 0,
      speed: speed,
      speedAccuracy: 0.5,
    );

void main() {
  late TrackingDiagnostics diag;
  late Interpreter interp;

  String run(String src) => printValue(interp.run(src));

  setUp(() {
    diag = TrackingDiagnostics();
    interp = Interpreter();
    installReplEnv(interp, diag);
  });

  test('builtins return nil before any data arrives', () {
    expect(run('(gps)'), 'nil');
    expect(run('(baro)'), 'nil');
    expect(run('(stats)'), 'nil');
    expect(run('(elev)'), 'nil');
    expect(run('(fix-age)'), 'nil');
    expect(run('(gps-history)'), 'nil');
  });

  test('(gps) exposes the latest raw fix with verdict and ms-frac', () {
    diag.gpsFix(fix(acc: 31.4), 'reject-accuracy', 'REJECT acc>25 (31.4 m)');
    expect(run("(cdr (assoc 'acc (gps)))"), '31.400');
    expect(run("(cdr (assoc 'verdict (gps)))"), '"reject-accuracy"');
    expect(run("(cdr (assoc 'ms-frac (gps)))"), 'nil'); // .000 timestamp
    diag.gpsFix(
        fix(ts: DateTime.utc(2026, 6, 8, 11, 45, 33, 506)), 'accept', 'ACCEPT');
    expect(run("(cdr (assoc 'ms-frac (gps)))"), 't');
    expect(run('(number? (cdr (assoc \'age (gps))))'), 't');
  });

  test('(gps-history n) is newest-first and composes with filter', () {
    for (final acc in [8.2, 7.9, 31.4, 8.8, 9.0]) {
      diag.gpsFix(fix(acc: acc), acc > 25 ? 'reject-accuracy' : 'accept', '-');
    }
    expect(run("(map (lambda (e) (cdr (assoc 'acc e))) (gps-history 3))"),
        '(9 8.800 31.400)');
    expect(
      run('(length (filter (lambda (e) (> (cdr (assoc \'acc e)) 25)) '
          '(gps-history 50)))'),
      '1',
    );
  });

  test('(counters) tracks verdicts', () {
    diag.gpsFix(fix(), 'accept', '-');
    diag.gpsFix(fix(), 'anchor', '-');
    diag.gpsFix(fix(acc: 40), 'reject-accuracy', '-');
    diag.gpsFix(fix(), 'teleport', '-');
    diag.segmentSplit('gap 90s');
    expect(run("(cdr (assoc 'accept (counters)))"), '2');
    expect(run("(cdr (assoc 'rej-acc (counters)))"), '1');
    expect(run("(cdr (assoc 'rej-teleport (counters)))"), '1');
    expect(run("(cdr (assoc 'splits (counters)))"), '1');
  });

  test('(elev) exposes ElevationTracker internals', () {
    final tracker = ElevationTracker();
    diag.trackerSnapshot = tracker.debugSnapshot;
    tracker.addGps(100, 8.0);
    expect(run("(cdr (assoc 'fused (elev)))"), '100');
    expect(run("(cdr (assoc 'climbing (elev)))"), 'nil');
    expect(run("(cdr (assoc 'baro (elev)))"), 'nil');
  });

  test('(stats) reads the wired provider', () {
    diag.statsProvider = () => {'distance': 1243.7, 'gain': 12.4, 'points': 213};
    expect(run("(cdr (assoc 'distance (stats)))"), '1243.700');
    expect(run("(cdr (assoc 'points (stats)))"), '213');
  });

  test("(log n 'category) filters the ring buffer, newest first", () {
    diag.event('sys', 'trip started');
    diag.gpsFix(fix(), 'accept', 'ACCEPT acc=8.2 m');
    diag.event('elev', 'BARO calibrated — offset 47.3 m');
    expect(run('(length (log 10))'), '3');
    expect(run("(length (log 10 'gps))"), '1');
    expect(run("(length (log 10 'elev))"), '1');
    expect(run('(log 1)'), contains('BARO calibrated'));
  });

  test('(help) lists commands', () {
    expect(run('(help)'), contains('(gps)'));
  });

  test('ring buffers are capped', () {
    for (var i = 0; i < TrackingDiagnostics.eventCapacity + 100; i++) {
      diag.event('sys', 'e$i');
    }
    expect(diag.events.length, TrackingDiagnostics.eventCapacity);
    for (var i = 0; i < TrackingDiagnostics.fixHistoryCapacity + 50; i++) {
      diag.gpsFix(fix(), 'accept', '-');
    }
    expect(diag.fixHistory.length, TrackingDiagnostics.fixHistoryCapacity);
  });
}
