import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sensors_plus/sensors_plus.dart';

void main() {
  runApp(const ErrApp());
}

class ErrApp extends StatelessWidget {
  const ErrApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Err',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.green),
      ),
      home: const TrackerScreen(),
    );
  }
}

class TrackerScreen extends StatefulWidget {
  const TrackerScreen({super.key});

  @override
  State<TrackerScreen> createState() => _TrackerScreenState();
}

class _TrackerScreenState extends State<TrackerScreen> {
  bool _isTracking = false;
  bool _starting = false;
  bool _gpsReady = false;
  bool _useImperial = false;
  String? _message;
  bool _messageIsError = false;

  double _distanceMeters = 0;
  double _elevationGainMeters = 0;
  Duration _elapsed = Duration.zero;

  Position? _lastPosition;
  DateTime? _startTime;
  final List<Position> _trackPoints = [];
  StreamSubscription<Position>? _positionSub;
  StreamSubscription<BarometerEvent>? _baroSub;
  double? _lastBaroAltitude;
  bool _baroAvailable = false;
  Timer? _ticker;
  Timer? _clockTicker;

  @override
  void initState() {
    super.initState();
    _clockTicker = Timer.periodic(
      const Duration(seconds: 1),
      (_) => setState(() {}),
    );
  }

  Future<void> _start() async {
    setState(() {
      _starting = true;
      _message = 'Waiting for GPS lock…';
      _messageIsError = false;
    });

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      setState(() {
        _message = 'Location permission denied.';
        _messageIsError = true;
        _starting = false;
      });
      return;
    }

    _distanceMeters = 0;
    _elevationGainMeters = 0;
    _elapsed = Duration.zero;
    _lastPosition = null;
    _gpsReady = false;
    _baroAvailable = false;
    _lastBaroAltitude = null;
    _trackPoints.clear();
    _startTime = DateTime.now();

    _positionSub = Geolocator.getPositionStream(
      locationSettings: Platform.isAndroid
          ? AndroidSettings(
              accuracy: LocationAccuracy.high,
              distanceFilter: 5,
              intervalDuration: const Duration(seconds: 3),
            )
          : AppleSettings(
              accuracy: LocationAccuracy.bestForNavigation,
              distanceFilter: 5,
              activityType: ActivityType.fitness,
              pauseLocationUpdatesAutomatically: false,
            ),
    ).listen(_onPosition, onError: (e) {
      setState(() {
        _message = 'GPS error: $e';
        _messageIsError = true;
      });
    });

    // Start barometer; errors mean the device has no sensor — fall back to GPS.
    _baroSub = Sensors().barometerEventStream(
      samplingPeriod: const Duration(seconds: 2),
    ).listen(_onBarometer, onError: (_) {
      _baroAvailable = false;
    });

    // Timer and _isTracking flip happen in _onPosition once a fresh fix arrives.
  }

  double _pressureToAltitude(double hPa) =>
      44330.0 * (1.0 - pow(hPa / 1013.25, 1.0 / 5.255));

  void _onBarometer(BarometerEvent event) {
    final alt = _pressureToAltitude(event.pressure);
    if (!_gpsReady) {
      // Keep the anchor fresh during the GPS-wait phase so the first
      // elevation delta after lock is computed from a clean baseline.
      _lastBaroAltitude = alt;
      _baroAvailable = true;
      return;
    }
    _baroAvailable = true;
    if (_lastBaroAltitude != null) {
      final altDiff = alt - _lastBaroAltitude!;
      // 3 m threshold: barometric accuracy is ~0.5 m, so 3 m is conservative
      // yet still filters out pressure fluctuations from handling the device.
      if (altDiff > 3.0) {
        setState(() => _elevationGainMeters += altDiff);
      }
    }
    _lastBaroAltitude = alt;
  }

  void _onPosition(Position pos) {
    // Discard low-accuracy fixes — a 40 m horizontal error connecting two
    // sloppy points inflates distance just as badly as moving.
    if (pos.accuracy > 25) return;

    if (!_gpsReady) {
      // Discard positions acquired more than 5 s before we pressed Start —
      // those are stale cached fixes that would produce a phantom distance jump.
      final staleThreshold =
          _startTime!.subtract(const Duration(seconds: 5));
      if (pos.timestamp.isBefore(staleThreshold)) return;

      // Fresh fix — anchor here and begin active tracking.
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
        setState(() => _elapsed = DateTime.now().difference(_startTime!));
      });
      setState(() {
        _gpsReady = true;
        _startTime = DateTime.now();
        _lastPosition = pos;
        _trackPoints.add(pos);
        _isTracking = true;
        _starting = false;
        _message = null;
      });
      return;
    }

    setState(() {
      if (_lastPosition != null) {
        _distanceMeters += Geolocator.distanceBetween(
          _lastPosition!.latitude,
          _lastPosition!.longitude,
          pos.latitude,
          pos.longitude,
        );
        // Only use GPS altitude when the barometer is unavailable — GPS
        // vertical noise (10–20 m) is far worse than the barometric sensor.
        if (!_baroAvailable) {
          final altDiff = pos.altitude - _lastPosition!.altitude;
          final accuracyOk = pos.altitudeAccuracy <= 0 ||
              pos.altitudeAccuracy < 15.0;
          if (altDiff > 10.0 && accuracyOk) {
            _elevationGainMeters += altDiff;
          }
        }
      }
      _lastPosition = pos;
      _trackPoints.add(pos);
    });
  }

  Future<void> _stop() async {
    await _positionSub?.cancel();
    _positionSub = null;
    await _baroSub?.cancel();
    _baroSub = null;
    _ticker?.cancel();
    _ticker = null;

    setState(() {
      _isTracking = false;
      _starting = false;
      _gpsReady = false;
      _baroAvailable = false;
    });

    if (_trackPoints.isEmpty) {
      setState(() {
        _message = 'No points recorded — nothing saved.';
        _messageIsError = true;
      });
      return;
    }

    try {
      // On Android use external storage so files are visible in the Files app
      // at Android/data/com.example.err/files/. Falls back to internal docs
      // on iOS and on Android if external storage is unavailable.
      final dir = (Platform.isAndroid
              ? await getExternalStorageDirectory()
              : null) ??
          await getApplicationDocumentsDirectory();
      final stamp = (_startTime ?? DateTime.now())
          .toIso8601String()
          .replaceAll(':', '-')
          .substring(0, 19);

      await _saveGpx(dir.path, stamp);
      await _saveCsv(dir.path, stamp);

      setState(() {
        _message = 'Saved $stamp.gpx + .csv';
        _messageIsError = false;
      });
    } catch (e) {
      setState(() {
        _message = 'Save failed: $e';
        _messageIsError = true;
      });
    }
  }

  Future<void> _saveGpx(String dirPath, String stamp) async {
    final buf = StringBuffer()
      ..writeln('<?xml version="1.0" encoding="UTF-8"?>')
      ..writeln(
          '<gpx version="1.1" creator="Err" xmlns="http://www.topografix.com/GPX/1/1">')
      ..writeln('  <trk>')
      ..writeln('    <name>Track $stamp</name>')
      ..writeln('    <trkseg>');
    for (final p in _trackPoints) {
      buf
        ..writeln(
            '      <trkpt lat="${p.latitude}" lon="${p.longitude}">')
        ..writeln(
            '        <ele>${p.altitude.toStringAsFixed(2)}</ele>')
        ..writeln(
            '        <time>${p.timestamp.toUtc().toIso8601String()}</time>')
        ..writeln('      </trkpt>');
    }
    buf
      ..writeln('    </trkseg>')
      ..writeln('  </trk>')
      ..writeln('</gpx>');
    await File('$dirPath/$stamp.gpx').writeAsString(buf.toString());
  }

  Future<void> _saveCsv(String dirPath, String stamp) async {
    final distKm = (_distanceMeters / 1000).toStringAsFixed(3);
    final elevM = _elevationGainMeters.toStringAsFixed(1);
    final h = _elapsed.inHours.toString().padLeft(2, '0');
    final m = (_elapsed.inMinutes % 60).toString().padLeft(2, '0');
    final s = (_elapsed.inSeconds % 60).toString().padLeft(2, '0');
    final csv = 'distance_km,elevation_gain_m,total_time\n'
        '$distKm,$elevM,$h:$m:$s\n';
    await File('$dirPath/$stamp.csv').writeAsString(csv);
  }

  String _fmtDistance() {
    if (_useImperial) {
      final feet = _distanceMeters * 3.28084;
      if (feet < 5280) return '${feet.toStringAsFixed(0)} ft';
      return '${(feet / 5280).toStringAsFixed(2)} mi';
    }
    if (_distanceMeters < 1000) return '${_distanceMeters.toStringAsFixed(0)} m';
    return '${(_distanceMeters / 1000).toStringAsFixed(2)} km';
  }

  String _fmtElevation() {
    if (_useImperial) {
      return '+${(_elevationGainMeters * 3.28084).toStringAsFixed(0)} ft';
    }
    return '+${_elevationGainMeters.toStringAsFixed(0)} m';
  }

  String _fmtTime() {
    final h = _elapsed.inHours.toString().padLeft(2, '0');
    final m = (_elapsed.inMinutes % 60).toString().padLeft(2, '0');
    final s = (_elapsed.inSeconds % 60).toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  String _fmtDateTime() {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    final now = DateTime.now();
    final date = '${months[now.month - 1]} ${now.day}, ${now.year}';
    final h = now.hour.toString().padLeft(2, '0');
    final m = now.minute.toString().padLeft(2, '0');
    final s = now.second.toString().padLeft(2, '0');
    return '$date  $h:$m:$s';
  }

  @override
  void dispose() {
    _positionSub?.cancel();
    _baroSub?.cancel();
    _ticker?.cancel();
    _clockTicker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: scheme.inversePrimary,
        title: const Text('Err'),
      ),
      body: Column(
        children: [
          Expanded(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Align(
                      alignment: Alignment.centerRight,
                      child: SegmentedButton<bool>(
                        segments: const [
                          ButtonSegment(value: false, label: Text('Metric')),
                          ButtonSegment(value: true, label: Text('Imperial')),
                        ],
                        selected: {_useImperial},
                        onSelectionChanged: (s) =>
                            setState(() => _useImperial = s.first),
                        showSelectedIcon: false,
                      ),
                    ),
                    const SizedBox(height: 28),
                    _StatTile(
                      icon: Icons.straighten,
                      label: 'Distance',
                      value: _fmtDistance(),
                    ),
                    const SizedBox(height: 28),
                    _StatTile(
                      icon: Icons.trending_up,
                      label: 'Elevation Gained',
                      value: _fmtElevation(),
                    ),
                    const SizedBox(height: 28),
                    _StatTile(
                      icon: Icons.timer_outlined,
                      label: 'Time',
                      value: _fmtTime(),
                    ),
                    const SizedBox(height: 28),
                    _StatTile(
                      icon: Icons.calendar_today_outlined,
                      label: 'Date & Time',
                      value: _fmtDateTime(),
                    ),
                    if (_message != null) ...[
                      const SizedBox(height: 28),
                      Text(
                        _message!,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: _messageIsError
                              ? Colors.red
                              : scheme.primary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
              child: Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed:
                          (_isTracking || _starting) ? null : _start,
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.green,
                        disabledBackgroundColor:
                            Colors.green.withAlpha(100),
                        padding:
                            const EdgeInsets.symmetric(vertical: 18),
                      ),
                      icon: _starting
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white),
                            )
                          : const Icon(Icons.play_arrow),
                      label: const Text('Start',
                          style: TextStyle(fontSize: 16)),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: (_isTracking || _starting) ? _stop : null,
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.red,
                        disabledBackgroundColor:
                            Colors.red.withAlpha(100),
                        padding:
                            const EdgeInsets.symmetric(vertical: 18),
                      ),
                      icon: const Icon(Icons.stop),
                      label: const Text('Stop',
                          style: TextStyle(fontSize: 16)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: scheme.onSurfaceVariant),
            const SizedBox(width: 6),
            Text(
              label,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          value,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.displaySmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: scheme.onSurface,
              ),
        ),
      ],
    );
  }
}
