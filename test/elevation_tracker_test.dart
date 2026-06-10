import 'dart:math';

import 'package:err/elevation_tracker.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('GPS-only fallback', () {
    test('flat ground with GPS noise accumulates ~no gain', () {
      final tracker = ElevationTracker();
      final rng = Random(42);
      // 30 min at one fix per 3 s, ±6 m vertical noise around 100 m.
      for (var i = 0; i < 600; i++) {
        tracker.addGps(100 + (rng.nextDouble() - 0.5) * 12, 8.0);
      }
      expect(tracker.gainMeters, lessThan(5.0));
    });

    test('slow sustained climb is fully captured', () {
      final tracker = ElevationTracker();
      // 50 m climb in 0.5 m steps — every step is below any per-sample
      // threshold; the old per-sample algorithm recorded 0 for this.
      for (var i = 0; i <= 100; i++) {
        tracker.addGps(100 + i * 0.5, 8.0);
      }
      expect(tracker.gainMeters, closeTo(50, 5));
    });

    test('descent then climb counts only the climb', () {
      final tracker = ElevationTracker();
      for (var i = 0; i <= 40; i++) {
        tracker.addGps(100.0 - i, 8.0); // down 40 m
      }
      for (var i = 0; i <= 40; i++) {
        tracker.addGps(60.0 + i, 8.0); // back up 40 m
      }
      expect(tracker.gainMeters, closeTo(40, 5));
    });

    test('reference switch between providers adds no gain', () {
      final tracker = ElevationTracker();
      // MSL-referenced fixes, then an ellipsoid-referenced provider takes
      // over ~33 m lower, then hands back. Seen in real GrapheneOS tracks.
      for (var i = 0; i < 10; i++) {
        tracker.addGps(131, 8.0);
      }
      for (var i = 0; i < 10; i++) {
        tracker.addGps(98, 8.0);
      }
      for (var i = 0; i < 10; i++) {
        tracker.addGps(131, 8.0);
      }
      expect(tracker.gainMeters, lessThan(1.0));
    });

    test('poor vertical accuracy fixes are ignored', () {
      final tracker = ElevationTracker();
      tracker.addGps(100, 8.0);
      tracker.addGps(120, 40.0); // garbage fix
      tracker.addGps(100, 8.0);
      expect(tracker.gainMeters, equals(0));
    });

    test('replays the 2026-06-08 GPX without phantom gain', () {
      // Raw <ele> values from the real recorded track: two provider
      // reference switches (−32 m, +45 m) around a gentle real descent.
      const eles = [
        131.25, 133.43, 132.93, 132.43, 130.96, 130.78, 130.52, // MSL frame
        98.43, 102.43, 100.43, 97.43, 96.43, 95.43, 93.42, // ellipsoid frame
        93.42, 93.42, 93.42, 94.42, 93.42, 93.42,
        138.68, // final cached fix, back in the MSL frame
      ];
      final tracker = ElevationTracker();
      for (final e in eles) {
        tracker.addGps(e, 8.0);
      }
      // True gain on this walk was on the order of 5–10 m; anything beyond
      // is sensor/reference noise that must not be counted.
      expect(tracker.gainMeters, lessThan(10.0));
    });
  });

  group('barometer fusion', () {
    // Feeds baro samples 2 s apart (past the 1 Hz throttle) and calibrates
    // the GPS offset so the fused stream becomes active.
    ElevationTracker calibrated({double baroAlt = 50, double gpsAlt = 100}) {
      final tracker = ElevationTracker();
      var t = DateTime(2026, 1, 1);
      for (var i = 0; i < 5; i++) {
        tracker.addBarometer(baroAlt, t);
        tracker.addGps(gpsAlt, 8.0);
        t = t.add(const Duration(seconds: 2));
      }
      return tracker;
    }

    test('fused altitude is anchored to the GPS frame', () {
      final tracker = calibrated();
      tracker.addBarometer(50, DateTime(2026, 1, 1, 0, 1));
      expect(tracker.currentAltitude, closeTo(100, 1));
    });

    test('transient pressure spike adds no gain', () {
      final tracker = calibrated();
      var t = DateTime(2026, 1, 1, 0, 1);
      // Wind gust / pocket handling: one +5 m spike, then back to base.
      // The old one-way ratchet banked every spike like this permanently.
      for (var i = 0; i < 50; i++) {
        tracker.addBarometer(i == 25 ? 55 : 50, t);
        t = t.add(const Duration(seconds: 2));
      }
      expect(tracker.gainMeters, equals(0));
    });

    test('sustained climb is captured', () {
      final tracker = calibrated();
      var t = DateTime(2026, 1, 1, 0, 1);
      for (var i = 0; i <= 60; i++) {
        tracker.addBarometer(50 + i * 0.5, t); // 30 m steady climb
        t = t.add(const Duration(seconds: 2));
      }
      expect(tracker.gainMeters, closeTo(30, 4));
    });

    test('GPS altitude is ignored once the barometer is active', () {
      final tracker = calibrated();
      var t = DateTime(2026, 1, 1, 0, 1);
      // GPS provider reference jumps ±33 m mid-track; baro stays flat.
      tracker.addGps(133, 8.0);
      tracker.addGps(67, 8.0);
      tracker.addBarometer(50, t);
      expect(tracker.gainMeters, equals(0));
      expect(tracker.currentAltitude, closeTo(100, 1));
    });

    test('sub-second samples are throttled', () {
      final tracker = calibrated();
      final t = DateTime(2026, 1, 1, 0, 1);
      tracker.addBarometer(50, t);
      // A 10 m spike arriving 100 ms later must be dropped, not smoothed in.
      tracker.addBarometer(60, t.add(const Duration(milliseconds: 100)));
      expect(tracker.currentAltitude, closeTo(100, 1));
    });
  });
}
