import 'dart:collection';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

/// One line in the debug log: a filter verdict, a sensor sample, or a
/// tracker event, timestamped.
class DebugEvent {
  DebugEvent(this.time, this.category, this.message);

  final DateTime time;
  final String category; // 'gps' | 'baro' | 'elev' | 'sys'
  final String message;
}

/// Collects every raw sample and every filter decision while tracking.
///
/// Three consumers share this single source: the live log tab, the
/// read-only REPL builtins, and the per-trip flight-recorder CSV. All data
/// stays on device, in line with the privacy-first philosophy.
class TrackingDiagnostics extends ChangeNotifier {
  static const eventCapacity = 500;
  static const fixHistoryCapacity = 300;

  final ListQueue<DebugEvent> events = ListQueue();
  final ListQueue<Map<String, Object?>> fixHistory = ListQueue();

  // Verdict counters for the current trip.
  int accepted = 0;
  int rejectedAccuracy = 0;
  int rejectedStale = 0;
  int rejectedTeleport = 0;
  int segmentSplits = 0;
  int baroSamples = 0;

  Map<String, Object?>? lastFix; // latest RAW fix, pre-filter
  Map<String, Object?>? lastBaro;
  DateTime? lastFixTime;

  /// Wired by the tracker screen so the REPL can read live state without
  /// the diagnostics holding widget references.
  Map<String, Object?> Function()? trackerSnapshot;
  Map<String, Object?> Function()? statsProvider;

  DateTime? _lastBaroSample;
  IOSink? _recorder;
  String? _recorderPath;
  int _unflushed = 0;

  /// Clears per-trip state. Called on Start.
  void resetTrip() {
    events.clear();
    fixHistory.clear();
    accepted = 0;
    rejectedAccuracy = 0;
    rejectedStale = 0;
    rejectedTeleport = 0;
    segmentSplits = 0;
    baroSamples = 0;
    lastFix = null;
    lastBaro = null;
    lastFixTime = null;
    _lastBaroSample = null;
    event('sys', 'trip started');
  }

  /// Records a raw GPS fix together with the filter's verdict.
  /// kind: 'accept' | 'anchor' | 'reject-accuracy' | 'reject-stale' |
  /// 'teleport'.
  void gpsFix(Position pos, String kind, String message) {
    switch (kind) {
      case 'accept':
      case 'anchor':
        accepted++;
      case 'reject-accuracy':
        rejectedAccuracy++;
      case 'reject-stale':
        rejectedStale++;
      case 'teleport':
        rejectedTeleport++;
    }
    final fix = fixToMap(pos)..['verdict'] = kind;
    lastFix = fix;
    lastFixTime = DateTime.now();
    fixHistory.addLast(fix);
    while (fixHistory.length > fixHistoryCapacity) {
      fixHistory.removeFirst();
    }
    event('gps', message, fix: pos);
  }

  /// Called when the track is split into a new GPX segment.
  void segmentSplit(String reason) {
    segmentSplits++;
    event('gps', 'SEGMENT split — $reason');
  }

  /// Records a barometer sample. Raw events can arrive far faster than the
  /// requested period, so this throttles to 1 Hz like the tracker does.
  void baroSample(double pressureHpa, double rawAltitude) {
    final now = DateTime.now();
    if (_lastBaroSample != null &&
        now.difference(_lastBaroSample!).inMilliseconds < 1000) {
      return;
    }
    _lastBaroSample = now;
    baroSamples++;
    lastBaro = {
      'hpa': pressureHpa,
      'alt-raw': rawAltitude,
      'fused': trackerSnapshot?.call()['fused'],
      'ts': now.toUtc().toIso8601String(),
    };
    // The ring log gets one line per 10 samples to stay readable; the
    // flight recorder gets every sample.
    if (baroSamples % 10 == 1) {
      event(
        'baro',
        'sample ${pressureHpa.toStringAsFixed(1)} hPa '
        '→ raw ${rawAltitude.toStringAsFixed(1)} m',
      );
    } else {
      _writeRow('baro', 'sample');
    }
  }

  /// Appends an event to the ring log (and the flight recorder if active).
  void event(String category, String message, {Position? fix}) {
    events.addLast(DebugEvent(DateTime.now(), category, message));
    while (events.length > eventCapacity) {
      events.removeFirst();
    }
    _writeRow(category, message, fix: fix);
    notifyListeners();
  }

  /// Latest raw fix as a map, with `age` (seconds) computed at call time.
  Map<String, Object?>? fixWithAge() {
    final fix = lastFix;
    if (fix == null) return null;
    return {
      ...fix,
      'age': lastFixTime == null
          ? null
          : DateTime.now().difference(lastFixTime!).inMilliseconds / 1000.0,
    };
  }

  Map<String, Object?> counters() => {
        'accept': accepted,
        'rej-acc': rejectedAccuracy,
        'rej-stale': rejectedStale,
        'rej-teleport': rejectedTeleport,
        'splits': segmentSplits,
        'baro-n': baroSamples,
      };

  static Map<String, Object?> fixToMap(Position pos) => {
        'lat': pos.latitude,
        'lon': pos.longitude,
        'acc': pos.accuracy,
        'alt': pos.altitude,
        'alt-acc': pos.altitudeAccuracy,
        'speed': pos.speed,
        'ts': pos.timestamp.toUtc().toIso8601String(),
        // Millisecond fraction is a provider fingerprint: in observed
        // tracks one source emits .000 timestamps, the other does not.
        'ms-frac':
            pos.timestamp.millisecond != 0 || pos.timestamp.microsecond != 0,
      };

  // ── Flight recorder ───────────────────────────────────────────────────

  bool get recording => _recorder != null;

  void startRecorder(String path) {
    stopRecorder();
    _recorderPath = path;
    _recorder = File(path).openWrite();
    _recorder!.writeln(
        'time,category,message,lat,lon,acc,alt,alt_acc,speed,fused,floor,climbing,gain,distance,ms_frac');
  }

  /// Closes the recorder, optionally renaming the file so its stamp
  /// matches the GPX (the GPX stamp is finalized at GPS lock, after the
  /// recorder already opened).
  Future<void> stopRecorder({String? renameTo}) async {
    final sink = _recorder;
    final path = _recorderPath;
    _recorder = null;
    _recorderPath = null;
    if (sink == null) return;
    await sink.flush();
    await sink.close();
    if (renameTo != null && path != null && renameTo != path) {
      try {
        await File(path).rename(renameTo);
      } catch (_) {} // keep the original file on failure
    }
  }

  void _writeRow(String category, String message, {Position? fix}) {
    final sink = _recorder;
    if (sink == null) return;
    final t = trackerSnapshot?.call() ?? const {};
    final stats = statsProvider?.call() ?? const {};
    String f(Object? v) => switch (v) {
          null => '',
          final double d => d.toStringAsFixed(d == d.roundToDouble() ? 0 : 6),
          _ => v.toString(),
        };
    sink.writeln([
      DateTime.now().toUtc().toIso8601String(),
      category,
      '"${message.replaceAll('"', "'")}"',
      f(fix?.latitude),
      f(fix?.longitude),
      f(fix?.accuracy),
      f(fix?.altitude),
      f(fix?.altitudeAccuracy),
      f(fix?.speed),
      f(t['fused']),
      f(t['floor']),
      f(t['climbing']),
      f(t['gain']),
      f(stats['distance']),
      // Provider fingerprint (see fixToMap): which location source emitted
      // this fix, inferable from the timestamp's millisecond fraction.
      fix == null
          ? ''
          : f(fix.timestamp.millisecond != 0 || fix.timestamp.microsecond != 0),
    ].join(','));
    if (++_unflushed >= 20) {
      _unflushed = 0;
      _recorder?.flush();
    }
  }

  @override
  void dispose() {
    stopRecorder();
    super.dispose();
  }
}
