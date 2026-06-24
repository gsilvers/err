import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import 'debug/diagnostics.dart';
import 'elevation_tracker.dart';
import 'trip_writer.dart';

/// The lifecycle of a recording. Replaces the loose boolean flags the tracker
/// widget used to juggle (`_starting`/`_isTracking`/`_paused`/`_gpsReady`).
enum TrackingStatus { idle, acquiring, tracking, paused }

/// One recorded fix: the raw [Position] plus the fused elevation at capture
/// time. Mutable elevation so it can be backfilled at calibration / shifted on
/// a reference rebase.
class _RecordedPoint {
  _RecordedPoint(this.position, double? fusedAltitude, {this.rawBaro})
    : fused = fusedAltitude != null,
      elevation = fusedAltitude ?? position.altitude;

  final Position position;
  final double? rawBaro;
  final bool fused;
  double elevation;
}

/// The tracking engine, lifted out of the widget so the fix-filtering and
/// distance/elevation/pause logic can be unit-tested by feeding it synthetic
/// positions.
///
/// It owns the per-trip state and the [ElevationTracker]; it does **not** own
/// the platform streams, permissions, wakelock or file I/O — the host widget
/// drives those and forwards each [Position] to [addPosition] and each
/// barometric pressure reading to [addBarometerPressure].
///
/// The accuracy/stale/teleport gates and the 60 s segment split are documented
/// in `docs/gps-accuracy.md`.
class TrackingController extends ChangeNotifier {
  TrackingController({required this.diagnostics, DateTime Function()? now})
    : _now = now ?? DateTime.now {
    diagnostics.trackerSnapshot = () => _elevation.debugSnapshot();
    diagnostics.statsProvider = () => {
      'distance': _distanceMeters,
      'gain': _elevation.gainMeters,
      'elapsed': _watch.elapsed.inSeconds,
      'points': pointCount,
      'segments': _segments.length,
      'tracking': isTracking,
    };
  }

  final TrackingDiagnostics diagnostics;
  final DateTime Function() _now;

  /// Active (unpaused) tracking time — a [Stopwatch] only advances while
  /// running, so pausing/resuming excludes paused time for free.
  final Stopwatch _watch = Stopwatch();

  TrackingStatus _status = TrackingStatus.idle;
  double _distanceMeters = 0;
  double _currentSpeed = 0; // m/s, from the latest accepted fix
  bool _resumeAnchorPending = false;
  Position? _lastPosition;
  DateTime? _startTime;
  List<List<_RecordedPoint>> _segments = [];
  ElevationTracker _elevation = ElevationTracker();
  int _teleportRejects = 0;

  TrackingStatus get status => _status;
  bool get isTracking =>
      _status == TrackingStatus.tracking || _status == TrackingStatus.paused;
  bool get isAcquiring => _status == TrackingStatus.acquiring;
  bool get isPaused => _status == TrackingStatus.paused;

  double get distanceMeters => _distanceMeters;
  double get currentSpeedMps => _currentSpeed;
  double get elevationGainMeters => _elevation.gainMeters;
  Duration get elapsed => _watch.elapsed;

  /// Trip start time (re-anchored at GPS lock); used for the saved filename.
  DateTime? get startTime => _startTime;

  int get segmentCount => _segments.length;
  int get pointCount => _segments.fold<int>(0, (n, s) => n + s.length);
  bool get hasPoints => _segments.any((s) => s.isNotEmpty);

  /// Reset all per-trip state and wait for a fresh GPS lock. Returns the start
  /// time (the host uses it for the debug-recorder filename).
  DateTime beginAcquiring() {
    _distanceMeters = 0;
    _currentSpeed = 0;
    _watch
      ..stop()
      ..reset();
    _resumeAnchorPending = false;
    _lastPosition = null;
    _teleportRejects = 0;
    _segments = [[]];
    _elevation = ElevationTracker();
    _elevation.onEvent = (msg) => diagnostics.event('elev', msg);
    // Until the baro offset freezes, points carry raw GPS elevations that can
    // sit in a different reference frame than the fused stream. Backfill them
    // into the fused frame the moment calibration completes.
    _elevation.onCalibrated = (offset) {
      for (final segment in _segments) {
        for (final p in segment) {
          if (!p.fused && p.rawBaro != null) p.elevation = p.rawBaro! + offset;
        }
      }
    };
    // A mid-track reference rebase shifts every recorded elevation by the same
    // delta, so the whole track stays in one consistent frame.
    _elevation.onRebase = (delta) {
      for (final segment in _segments) {
        for (final p in segment) {
          p.elevation += delta;
        }
      }
    };
    _startTime = _now();
    diagnostics.resetTrip();
    _status = TrackingStatus.acquiring;
    notifyListeners();
    return _startTime!;
  }

  /// Feed a barometric pressure reading (hPa). No-op while paused.
  void addBarometerPressure(double pressure) {
    if (_status == TrackingStatus.paused) return;
    final rawAlt = ElevationTracker.pressureToAltitude(pressure);
    _elevation.addBarometer(rawAlt, _now());
    diagnostics.baroSample(pressure, rawAlt);
    // No notify — gain repaints via the host's 1 s ticker, as before.
  }

  /// Feed a GPS fix through the filter pipeline.
  void addPosition(Position pos) {
    if (_status == TrackingStatus.paused) return; // ignore fixes while paused

    // Discard low-accuracy fixes — a 40 m horizontal error connecting two
    // sloppy points inflates distance just as badly as moving.
    if (pos.accuracy > 25) {
      diagnostics.gpsFix(
        pos,
        'reject-accuracy',
        'REJECT acc>25 (${pos.accuracy.toStringAsFixed(1)} m)',
      );
      return;
    }

    if (_status == TrackingStatus.acquiring) {
      // Discard positions acquired more than 5 s before Start — those are stale
      // cached fixes that would produce a phantom distance jump.
      final staleThreshold = _startTime!.subtract(const Duration(seconds: 5));
      if (pos.timestamp.isBefore(staleThreshold)) {
        diagnostics.gpsFix(
          pos,
          'reject-stale',
          'REJECT stale (cached pre-start fix)',
        );
        return;
      }

      // Fresh fix — anchor here and begin active tracking.
      _watch
        ..reset()
        ..start();
      _elevation.addGps(pos.altitude, pos.altitudeAccuracy);
      diagnostics.gpsFix(
        pos,
        'anchor',
        'ACCEPT anchor acc=${pos.accuracy.toStringAsFixed(1)} m — tracking begins',
      );
      _startTime = _now();
      _lastPosition = pos;
      _currentSpeed = pos.speed;
      _appendPoint(pos);
      _status = TrackingStatus.tracking;
      notifyListeners();
      return;
    }

    if (_resumeAnchorPending) {
      // First fix after a resume: re-anchor in a new segment so the paused
      // interval is a break in the GPX, and count no distance for it.
      _resumeAnchorPending = false;
      _segments.add([]);
      _teleportRejects = 0;
      _elevation.addGps(pos.altitude, pos.altitudeAccuracy);
      diagnostics.gpsFix(
        pos,
        'resume',
        'ACCEPT resume re-anchor — new segment',
      );
      _lastPosition = pos;
      _currentSpeed = pos.speed;
      _appendPoint(pos);
      notifyListeners();
      return;
    }

    final last = _lastPosition;
    if (last != null) {
      final gapSec = pos.timestamp.difference(last.timestamp).inSeconds.abs();
      if (gapSec > 60) {
        // GPS lost for over 60 s — open a new segment so the gap is a break in
        // GPX viewers and is not counted as distance.
        _segments.add([]);
        _teleportRejects = 0;
        diagnostics.segmentSplit('gap ${gapSec}s');
      } else {
        final meters = Geolocator.distanceBetween(
          last.latitude,
          last.longitude,
          pos.latitude,
          pos.longitude,
        );
        // Reject teleports: a fix implying a speed far beyond what the receiver
        // itself reports is a provider glitch, not movement.
        final implied = meters / max(gapSec, 1);
        final speedCap = max(pos.speed > 0 ? pos.speed * 3 : 0.0, 15.0);
        if (implied > speedCap) {
          _teleportRejects++;
          if (_teleportRejects < 3) {
            diagnostics.gpsFix(
              pos,
              'teleport',
              'TELEPORT $_teleportRejects/3 implied=${implied.toStringAsFixed(1)} m/s cap=${speedCap.toStringAsFixed(1)}',
            );
            return;
          }
          // Three impossible fixes in a row means the previous anchor was the
          // glitch — re-anchor here in a new segment, counting nothing.
          _segments.add([]);
          _teleportRejects = 0;
          diagnostics.segmentSplit('re-anchor after 3 teleports');
        } else {
          _teleportRejects = 0;
          _distanceMeters += meters;
        }
      }
    }

    _elevation.addGps(pos.altitude, pos.altitudeAccuracy);
    diagnostics.gpsFix(
      pos,
      'accept',
      'ACCEPT acc=${pos.accuracy.toStringAsFixed(1)} m alt=${pos.altitude.toStringAsFixed(1)} m',
    );
    _lastPosition = pos;
    _currentSpeed = pos.speed;
    _appendPoint(pos);
    notifyListeners();
  }

  void pause() {
    if (_status != TrackingStatus.tracking) return;
    _watch.stop();
    _status = TrackingStatus.paused;
    _currentSpeed = 0;
    notifyListeners();
  }

  void resume() {
    if (_status != TrackingStatus.paused) return;
    _watch.start();
    _status = TrackingStatus.tracking;
    _resumeAnchorPending = true;
    notifyListeners();
  }

  /// Stop and snapshot the recording. Check [TripRecording.isEmpty] /
  /// [hasPoints] to decide whether to save. Status returns to idle.
  TripRecording finish() {
    _watch.stop();
    _status = TrackingStatus.idle;
    final recording = _recording();
    notifyListeners();
    return recording;
  }

  void _appendPoint(Position pos) {
    _segments.last.add(
      _RecordedPoint(
        pos,
        _elevation.currentAltitude,
        rawBaro: _elevation.lastRawBarometricAltitude,
      ),
    );
  }

  TripRecording _recording() => TripRecording(
    segments: [
      for (final segment in _segments)
        [
          for (final p in segment)
            TrackPoint(
              latitude: p.position.latitude,
              longitude: p.position.longitude,
              elevation: p.elevation,
              time: p.position.timestamp,
            ),
        ],
    ],
    distanceMeters: _distanceMeters,
    elevationGainMeters: _elevation.gainMeters,
    elapsed: _watch.elapsed,
  );
}
