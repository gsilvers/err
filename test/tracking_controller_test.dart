import 'package:err/debug/diagnostics.dart';
import 'package:err/tracking_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';

/// Fixed wall clock so the stale-fix gate is deterministic.
final _clock = DateTime(2026, 1, 1, 12);

Position _pos({
  required double lat,
  required double lon,
  required DateTime time,
  double accuracy = 5,
  double altitude = 100,
  double speed = 1.5,
}) => Position(
  latitude: lat,
  longitude: lon,
  timestamp: time,
  accuracy: accuracy,
  altitude: altitude,
  altitudeAccuracy: 5,
  heading: 0,
  headingAccuracy: 0,
  speed: speed,
  speedAccuracy: 0,
);

TrackingController _controller() =>
    TrackingController(diagnostics: TrackingDiagnostics(), now: () => _clock);

void main() {
  test('anchors on the first good fix and ignores a stale pre-start fix', () {
    final c = _controller()..beginAcquiring();
    expect(c.status, TrackingStatus.acquiring);

    // 10 s before start → stale, rejected.
    c.addPosition(
      _pos(lat: 1, lon: 1, time: _clock.subtract(const Duration(seconds: 10))),
    );
    expect(c.status, TrackingStatus.acquiring);
    expect(c.pointCount, 0);

    c.addPosition(_pos(lat: 1, lon: 1, time: _clock));
    expect(c.status, TrackingStatus.tracking);
    expect(c.pointCount, 1);
    expect(c.distanceMeters, 0);
  });

  test('rejects low-accuracy fixes', () {
    final c = _controller()..beginAcquiring();
    c.addPosition(_pos(lat: 1, lon: 1, time: _clock, accuracy: 40));
    expect(c.status, TrackingStatus.acquiring);
    expect(c.pointCount, 0);
  });

  test('accumulates distance between accepted fixes', () {
    final c = _controller()..beginAcquiring();
    c.addPosition(_pos(lat: 1.0, lon: 1.0, time: _clock));
    // ~11 m north, 3 s later.
    c.addPosition(
      _pos(lat: 1.0001, lon: 1.0, time: _clock.add(const Duration(seconds: 3))),
    );
    expect(c.distanceMeters, closeTo(11.1, 1.5));
    expect(c.segmentCount, 1);
    expect(c.pointCount, 2);
  });

  test('rejects teleports and re-anchors after three in a row', () {
    final c = _controller()..beginAcquiring();
    c.addPosition(_pos(lat: 1.0, lon: 1.0, time: _clock));
    // ~1.1 km jump every 3 s with a sane reported speed → teleport.
    for (var i = 1; i <= 3; i++) {
      c.addPosition(
        _pos(lat: 1.01, lon: 1.0, time: _clock.add(Duration(seconds: 3 * i))),
      );
    }
    expect(c.distanceMeters, 0); // no phantom distance counted
    expect(c.segmentCount, 2); // re-anchored in a fresh segment
    expect(c.pointCount, 2); // anchor + re-anchor
  });

  test('opens a new segment after a >60 s gap without counting distance', () {
    final c = _controller()..beginAcquiring();
    c.addPosition(_pos(lat: 1.0, lon: 1.0, time: _clock));
    c.addPosition(
      _pos(
        lat: 1.0001,
        lon: 1.0,
        time: _clock.add(const Duration(seconds: 90)),
      ),
    );
    expect(c.segmentCount, 2);
    expect(c.distanceMeters, 0);
  });

  test('pause ignores fixes; resume re-anchors counting no gap distance', () {
    final c = _controller()..beginAcquiring();
    c.addPosition(_pos(lat: 1.0, lon: 1.0, time: _clock));
    c.addPosition(
      _pos(lat: 1.0001, lon: 1.0, time: _clock.add(const Duration(seconds: 3))),
    );
    final afterFirstLeg = c.distanceMeters;
    expect(afterFirstLeg, closeTo(11.1, 1.5));

    c.pause();
    expect(c.status, TrackingStatus.paused);
    // Fix during pause is ignored.
    c.addPosition(
      _pos(lat: 1.001, lon: 1.0, time: _clock.add(const Duration(seconds: 6))),
    );
    expect(c.distanceMeters, afterFirstLeg);

    c.resume();
    expect(c.status, TrackingStatus.tracking);
    // First post-resume fix re-anchors (new segment, no distance for the gap).
    c.addPosition(
      _pos(lat: 1.002, lon: 1.0, time: _clock.add(const Duration(seconds: 9))),
    );
    expect(c.distanceMeters, afterFirstLeg);
    expect(c.segmentCount, 2);
    // A further fix accumulates again.
    c.addPosition(
      _pos(
        lat: 1.0021,
        lon: 1.0,
        time: _clock.add(const Duration(seconds: 12)),
      ),
    );
    expect(c.distanceMeters, greaterThan(afterFirstLeg));
  });

  test('finish snapshots the recording and returns to idle', () {
    final c = _controller()..beginAcquiring();
    c.addPosition(_pos(lat: 1.0, lon: 1.0, time: _clock));
    c.addPosition(
      _pos(lat: 1.0001, lon: 1.0, time: _clock.add(const Duration(seconds: 3))),
    );
    final recording = c.finish();
    expect(c.status, TrackingStatus.idle);
    expect(recording.isEmpty, isFalse);
    expect(recording.segments.first.length, 2);
    expect(recording.distanceMeters, closeTo(11.1, 1.5));
  });
}
