import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:path_provider/path_provider.dart';

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
      _message = null;
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
    _trackPoints.clear();
    _startTime = DateTime.now();

    _positionSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 5,
      ),
    ).listen(_onPosition, onError: (e) {
      setState(() {
        _message = 'GPS error: $e';
        _messageIsError = true;
      });
    });

    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      setState(() => _elapsed = DateTime.now().difference(_startTime!));
    });

    setState(() {
      _isTracking = true;
      _starting = false;
    });
  }

  void _onPosition(Position pos) {
    setState(() {
      if (_lastPosition != null) {
        _distanceMeters += Geolocator.distanceBetween(
          _lastPosition!.latitude,
          _lastPosition!.longitude,
          pos.latitude,
          pos.longitude,
        );
        final altDiff = pos.altitude - _lastPosition!.altitude;
        if (altDiff > 0) _elevationGainMeters += altDiff;
      }
      _lastPosition = pos;
      _trackPoints.add(pos);
    });
  }

  Future<void> _stop() async {
    await _positionSub?.cancel();
    _positionSub = null;
    _ticker?.cancel();
    _ticker = null;

    setState(() => _isTracking = false);

    if (_trackPoints.isEmpty) {
      setState(() {
        _message = 'No points recorded — nothing saved.';
        _messageIsError = true;
      });
      return;
    }

    try {
      final dir = await getApplicationDocumentsDirectory();
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
                      onPressed: _isTracking ? _stop : null,
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
