import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'builtin_themes.dart';
import 'custom_theme_editor.dart';
import 'err_theme.dart';
import 'theme_picker.dart';

void main() {
  runApp(const ErrApp());
}

// ─── App root ────────────────────────────────────────────────────────────────

class ErrApp extends StatefulWidget {
  const ErrApp({super.key});

  @override
  State<ErrApp> createState() => _ErrAppState();
}

class _ErrAppState extends State<ErrApp> {
  ErrTheme _theme = builtinThemes.first;
  List<ErrTheme> _customThemes = [];
  SharedPreferences? _prefs;

  @override
  void initState() {
    super.initState();
    _loadPrefs();
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    _prefs = prefs;

    final id = prefs.getString('selected_theme_id');
    List<ErrTheme> customs = [];
    try {
      customs = (jsonDecode(prefs.getString('custom_themes') ?? '[]') as List)
          .map((j) => ErrTheme.fromJson(j as Map<String, dynamic>))
          .toList();
    } catch (_) {}

    ErrTheme active = builtinThemes.firstWhere(
      (t) => t.id == id,
      orElse: () => builtinThemes.first,
    );
    if (id != null && active.id != id) {
      try {
        active = customs.firstWhere((t) => t.id == id);
      } catch (_) {}
    }

    setState(() {
      _customThemes = customs;
      _theme = active;
    });
  }

  void _applyTheme(ErrTheme t) {
    setState(() => _theme = t);
    _prefs?.setString('selected_theme_id', t.id);
  }

  void _saveCustomTheme(ErrTheme t) {
    setState(() {
      _customThemes = [
        ..._customThemes.where((c) => c.id != t.id),
        t,
      ];
    });
    _prefs?.setString(
      'custom_themes',
      jsonEncode(_customThemes.map((c) => c.toJson()).toList()),
    );
  }

  void _deleteCustomTheme(String id) {
    setState(() {
      _customThemes = _customThemes.where((t) => t.id != id).toList();
    });
    _prefs?.setString(
      'custom_themes',
      jsonEncode(_customThemes.map((c) => c.toJson()).toList()),
    );
    if (_theme.id == id) _applyTheme(builtinThemes.first);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Err',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness:
            _theme.isDark ? Brightness.dark : Brightness.light,
      ),
      home: TrackerScreen(
        theme: _theme,
        customThemes: _customThemes,
        onThemeChanged: _applyTheme,
        onSaveCustomTheme: _saveCustomTheme,
        onDeleteCustomTheme: _deleteCustomTheme,
      ),
    );
  }
}

// ─── Tracker screen ──────────────────────────────────────────────────────────

class TrackerScreen extends StatefulWidget {
  const TrackerScreen({
    super.key,
    required this.theme,
    required this.customThemes,
    required this.onThemeChanged,
    required this.onSaveCustomTheme,
    required this.onDeleteCustomTheme,
  });

  final ErrTheme theme;
  final List<ErrTheme> customThemes;
  final void Function(ErrTheme) onThemeChanged;
  final void Function(ErrTheme) onSaveCustomTheme;
  final void Function(String) onDeleteCustomTheme;

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

  // ── GPS start/stop ──────────────────────────────────────────────────────

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

  // ── File saving ─────────────────────────────────────────────────────────

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
        ..writeln('      <trkpt lat="${p.latitude}" lon="${p.longitude}">')
        ..writeln('        <ele>${p.altitude.toStringAsFixed(2)}</ele>')
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
    final csv =
        'distance_km,elevation_gain_m,total_time\n$distKm,$elevM,$h:$m:$s\n';
    await File('$dirPath/$stamp.csv').writeAsString(csv);
  }

  // ── Formatting ───────────────────────────────────────────────────────────

  String _fmtDistance() {
    if (_useImperial) {
      final feet = _distanceMeters * 3.28084;
      if (feet < 5280) return '${feet.toStringAsFixed(0)} ft';
      return '${(feet / 5280).toStringAsFixed(2)} mi';
    }
    if (_distanceMeters < 1000) {
      return '${_distanceMeters.toStringAsFixed(0)} m';
    }
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

  // ── Theme picker ─────────────────────────────────────────────────────────

  void _openThemePicker() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => SizedBox(
        height: MediaQuery.of(context).size.height * 0.78,
        child: ThemePickerSheet(
          activeTheme: widget.theme,
          customThemes: widget.customThemes,
          onSelect: (t) {
            widget.onThemeChanged(t);
            Navigator.pop(context);
          },
          onEdit: (t) {
            Navigator.pop(context);
            Navigator.push<void>(
              context,
              MaterialPageRoute(
                builder: (_) => CustomThemeEditorScreen(
                  editing: t,
                  onSave: widget.onSaveCustomTheme,
                ),
              ),
            );
          },
          onDelete: (id) {
            widget.onDeleteCustomTheme(id);
            Navigator.pop(context);
          },
          onNew: () {
            Navigator.pop(context);
            Navigator.push<void>(
              context,
              MaterialPageRoute(
                builder: (_) => CustomThemeEditorScreen(
                  baseTheme: widget.theme,
                  onSave: (t) {
                    widget.onSaveCustomTheme(t);
                    widget.onThemeChanged(t);
                  },
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  // ── Lifecycle ────────────────────────────────────────────────────────────

  @override
  void dispose() {
    _positionSub?.cancel();
    _baroSub?.cancel();
    _ticker?.cancel();
    _clockTicker?.cancel();
    super.dispose();
  }

  // ── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final t = widget.theme;

    return Scaffold(
      backgroundColor: t.screenBackground,
      appBar: AppBar(
        backgroundColor: t.appBarBackground,
        title: Text('Err', style: TextStyle(color: t.appBarTitle)),
        iconTheme: IconThemeData(color: t.appBarTitle),
        actions: [
          IconButton(
            icon: const Icon(Icons.palette_outlined),
            color: t.appBarTitle,
            tooltip: 'Theme',
            onPressed: _openThemePicker,
          ),
        ],
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
                        style: ButtonStyle(
                          backgroundColor: WidgetStateProperty.resolveWith(
                            (states) => states.contains(WidgetState.selected)
                                ? t.toggleSelectedBackground
                                : t.toggleUnselectedBackground,
                          ),
                          foregroundColor: WidgetStateProperty.resolveWith(
                            (states) => states.contains(WidgetState.selected)
                                ? t.toggleSelectedText
                                : t.toggleUnselectedText,
                          ),
                          side: WidgetStateProperty.all(
                            BorderSide(color: t.toggleBorder),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 28),
                    _StatTile(
                      icon: Icons.straighten,
                      label: 'Distance',
                      value: _fmtDistance(),
                      iconColor: t.statIcon,
                      labelColor: t.statLabel,
                      valueColor: t.statValue,
                    ),
                    const SizedBox(height: 28),
                    _StatTile(
                      icon: Icons.trending_up,
                      label: 'Elevation Gained',
                      value: _fmtElevation(),
                      iconColor: t.statIcon,
                      labelColor: t.statLabel,
                      valueColor: t.statValue,
                    ),
                    const SizedBox(height: 28),
                    _StatTile(
                      icon: Icons.timer_outlined,
                      label: 'Time',
                      value: _fmtTime(),
                      iconColor: t.statIcon,
                      labelColor: t.statLabel,
                      valueColor: t.statValue,
                    ),
                    const SizedBox(height: 28),
                    _StatTile(
                      icon: Icons.calendar_today_outlined,
                      label: 'Date & Time',
                      value: _fmtDateTime(),
                      iconColor: t.statIcon,
                      labelColor: t.statLabel,
                      valueColor: t.statValue,
                    ),
                    if (_message != null) ...[
                      const SizedBox(height: 28),
                      Text(
                        _message!,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: _messageIsError
                              ? t.messageError
                              : t.messageInfo,
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
                        backgroundColor: t.startActive,
                        disabledBackgroundColor: t.startDisabled,
                        foregroundColor: t.startForeground,
                        disabledForegroundColor:
                            t.startForeground.withAlpha(120),
                        padding:
                            const EdgeInsets.symmetric(vertical: 18),
                      ),
                      icon: _starting
                          ? SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: t.startForeground,
                              ),
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
                        backgroundColor: t.stopActive,
                        disabledBackgroundColor: t.stopDisabled,
                        foregroundColor: t.stopForeground,
                        disabledForegroundColor:
                            t.stopForeground.withAlpha(120),
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

// ─── Stat tile ───────────────────────────────────────────────────────────────

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.iconColor,
    required this.labelColor,
    required this.valueColor,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color iconColor;
  final Color labelColor;
  final Color valueColor;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: iconColor),
            const SizedBox(width: 6),
            Text(
              label,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: labelColor),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          value,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.displaySmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: valueColor,
              ),
        ),
      ],
    );
  }
}
