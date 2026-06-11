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

    test('noise dip and rebound does not double-bank gain', () {
      // 2026-06-10 walk: a ~4 m fused dip ended a climb (resetting the
      // floor to the dip bottom) and the rebound 2.5 s later re-banked
      // 3.1 m of altitude already counted.
      final tracker = calibrated();
      var t = DateTime(2026, 1, 1, 0, 1);
      void baro(double alt) {
        tracker.addBarometer(alt, t);
        t = t.add(const Duration(seconds: 2));
      }

      for (var i = 0; i <= 30; i++) {
        baro(50 + i * 0.2); // sustained 6 m climb
      }
      final banked = tracker.gainMeters;
      expect(banked, greaterThan(4));
      for (var i = 0; i < 6; i++) {
        baro(52); // brief 4 m dip…
      }
      for (var i = 0; i < 20; i++) {
        baro(56); // …that rebounds to the climb high
      }
      expect(tracker.gainMeters, closeTo(banked, 1.0));
    });

    test('sustained post-calibration residual rebases without gain', () {
      final tracker = calibrated(); // baro 50 ↔ gps 100
      var rebase = 0.0;
      tracker.onRebase = (d) => rebase = d;
      tracker.addBarometer(50, DateTime(2026, 1, 1, 0, 1));
      // Provider switch: good fixes arrive ~37 m above the fused frame.
      for (var i = 0; i < 5; i++) {
        tracker.addGps(137, 4.0);
      }
      expect(rebase, closeTo(37, 1));
      tracker.addBarometer(50, DateTime(2026, 1, 1, 0, 2));
      expect(tracker.currentAltitude, closeTo(137, 1));
      expect(tracker.gainMeters, equals(0));
    });

    test('outliers and flapping residuals do not rebase', () {
      final tracker = calibrated();
      var rebased = false;
      tracker.onRebase = (_) => rebased = true;
      tracker.addBarometer(50, DateTime(2026, 1, 1, 0, 1));
      for (var i = 0; i < 4; i++) {
        tracker.addGps(137, 4.0); // four high — one short of the window
      }
      tracker.addGps(100, 4.0); // back in frame: clears the window
      tracker.addGps(63, 4.0); // opposite sign: clears again
      tracker.addGps(137, 40.0); // poor vertical accuracy: ignored
      expect(rebased, isFalse);
      expect(tracker.currentAltitude, closeTo(100, 1));
    });

    test('replays the 2026-06-10 walk: rebases once, sane gain', () {
      // Calibration locked onto a provider ~42 m below the frame the
      // barometer and the late-walk raw-GNSS fixes agreed on; the real
      // walk was flat for 17 min, then climbed ~13 m.
      final tracker = ElevationTracker();
      var rebase = 0.0;
      tracker.onRebase = (d) => rebase = d;
      final rng = Random(7);
      var t = DateTime(2026, 1, 1);
      void baro(double alt) {
        tracker.addBarometer(alt, t);
        t = t.add(const Duration(seconds: 2));
      }

      baro(127.5);
      for (var i = 0; i < 5; i++) {
        baro(127.5);
        tracker.addGps(85.4, 2.0); // wrong-frame provider calibrates
      }
      for (var i = 0; i < 500; i++) {
        baro(127.5 + (rng.nextDouble() - 0.5) * 2); // flat, ±1 m wobble
        if (i % 4 == 0) tracker.addGps(85.4 + (rng.nextDouble() - 0.5) * 4, 2.0);
      }
      expect(tracker.gainMeters, lessThan(2.0));
      for (var i = 0; i <= 100; i++) {
        final raw = 127.5 + i * 0.13; // real 13 m climb…
        baro(raw);
        if (i % 4 == 0) tracker.addGps(raw + 0.2, 5.0); // …as raw GNSS takes over
      }
      expect(rebase, closeTo(42, 3));
      expect(tracker.gainMeters, closeTo(13, 3));
      expect(tracker.currentAltitude, closeTo(140.7, 2));
    });
  });
}
