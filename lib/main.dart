import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'app_drawer.dart';
import 'builtin_themes.dart';
import 'custom_theme_editor.dart';
import 'debug/debug_screen.dart';
import 'debug/diagnostics.dart';
import 'elevation_tracker.dart';
import 'err_theme.dart';
import 'help_screen.dart';
import 'settings_screen.dart';
import 'stats_screen.dart';
import 'theme_picker.dart';
import 'units.dart';

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
  bool _keepScreenOn = false;
  bool _showSpeed = true;
  bool _debugMode = false;
  String? _message;
  bool _messageIsError = false;

  double _distanceMeters = 0;
  double _currentSpeed = 0; // m/s, from the latest accepted GPS fix
  Duration _elapsed = Duration.zero;

  Position? _lastPosition;
  DateTime? _startTime;
  List<List<_TrackPoint>> _segments = [];
  ElevationTracker _elevation = ElevationTracker();
  final TrackingDiagnostics _diag = TrackingDiagnostics();
  int _teleportRejects = 0;
  SharedPreferences? _prefs;
  StreamSubscription<Position>? _positionSub;
  StreamSubscription<BarometerEvent>? _baroSub;
  Timer? _ticker;
  Timer? _clockTicker;

  @override
  void initState() {
    super.initState();
    _clockTicker = Timer.periodic(
      const Duration(seconds: 1),
      (_) => setState(() {}),
    );
    _diag.trackerSnapshot = () => _elevation.debugSnapshot();
    _diag.statsProvider = () => {
          'distance': _distanceMeters,
          'gain': _elevation.gainMeters,
          'elapsed': _elapsed.inSeconds,
          'points': _segments.fold<int>(0, (n, s) => n + s.length),
          'segments': _segments.length,
          'tracking': _isTracking,
        };
    _loadPrefs();
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _prefs = prefs;
      _keepScreenOn = prefs.getBool('keep_screen_on') ?? false;
      _debugMode = prefs.getBool('debug_mode') ?? false;
      _useImperial = prefs.getBool('use_imperial') ?? false;
      _showSpeed = prefs.getBool('show_speed') ?? true;
    });
  }

  void _setUseImperial(bool v) {
    setState(() => _useImperial = v);
    _prefs?.setBool('use_imperial', v);
  }

  void _setShowSpeed(bool v) {
    setState(() => _showSpeed = v);
    _prefs?.setBool('show_speed', v);
  }

  void _setDebugMode(bool v) {
    setState(() => _debugMode = v);
    _prefs?.setBool('debug_mode', v);
  }

  void _setKeepScreenOn(bool v) {
    setState(() => _keepScreenOn = v);
    _prefs?.setBool('keep_screen_on', v);
    if (_isTracking) {
      if (v) {
        WakelockPlus.enable();
      } else {
        WakelockPlus.disable();
      }
    }
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
    _currentSpeed = 0;
    _elapsed = Duration.zero;
    _lastPosition = null;
    _gpsReady = false;
    _elevation = ElevationTracker();
    _elevation.onEvent = (msg) => _diag.event('elev', msg);
    // Until the baro offset freezes, points carry raw GPS elevations that
    // can sit in a different reference frame than the fused stream (the
    // 51 m cliff at the start of the 2026-06-10 walk's GPX). Backfill them
    // into the fused frame the moment calibration completes.
    _elevation.onCalibrated = (offset) {
      for (final segment in _segments) {
        for (final p in segment) {
          if (!p.fused && p.rawBaro != null) {
            p.elevation = p.rawBaro! + offset;
          }
        }
      }
    };
    // A mid-track reference rebase (provider switch) shifts every recorded
    // elevation by the same delta, so the whole track stays in one
    // consistent frame instead of acquiring a cliff at the switch point.
    _elevation.onRebase = (delta) {
      for (final segment in _segments) {
        for (final p in segment) {
          p.elevation += delta;
        }
      }
    };
    _teleportRejects = 0;
    _segments = [[]];
    _startTime = DateTime.now();
    _diag.resetTrip();

    if (_keepScreenOn) await WakelockPlus.enable();

    if (_debugMode) {
      // Flight recorder: every raw sample + verdict, written beside the
      // GPX. Failures here must never block tracking.
      try {
        final dir = (Platform.isAndroid
                ? await getExternalStorageDirectory()
                : null) ??
            await getApplicationDocumentsDirectory();
        final stamp = _startTime!
            .toIso8601String()
            .replaceAll(':', '-')
            .substring(0, 19);
        _diag.startRecorder('${dir.path}/$stamp-debug.csv');
      } catch (_) {}
    }

    _positionSub = Geolocator.getPositionStream(
      locationSettings: Platform.isAndroid
          ? AndroidSettings(
              accuracy: LocationAccuracy.high,
              distanceFilter: 5,
              intervalDuration: const Duration(seconds: 3),
              foregroundNotificationConfig: const ForegroundNotificationConfig(
                notificationText: 'Err is recording your activity',
                notificationTitle: 'Tracking active',
                enableWakeLock: true,
              ),
            )
          : AppleSettings(
              accuracy: LocationAccuracy.bestForNavigation,
              distanceFilter: 5,
              activityType: ActivityType.fitness,
              pauseLocationUpdatesAutomatically: false,
              allowBackgroundLocationUpdates: true,
              showBackgroundLocationIndicator: true,
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
    ).listen(_onBarometer, onError: (_) {});

    // Timer and _isTracking flip happen in _onPosition once a fresh fix arrives.
  }

  void _onBarometer(BarometerEvent event) {
    // No setState — the 1 s clock ticker repaints the gain soon enough.
    final rawAlt = ElevationTracker.pressureToAltitude(event.pressure);
    _elevation.addBarometer(rawAlt, DateTime.now());
    _diag.baroSample(event.pressure, rawAlt);
  }

  void _onPosition(Position pos) {
    // Discard low-accuracy fixes — a 40 m horizontal error connecting two
    // sloppy points inflates distance just as badly as moving.
    if (pos.accuracy > 25) {
      _diag.gpsFix(pos, 'reject-accuracy',
          'REJECT acc>25 (${pos.accuracy.toStringAsFixed(1)} m)');
      return;
    }

    if (!_gpsReady) {
      // Discard positions acquired more than 5 s before we pressed Start —
      // those are stale cached fixes that would produce a phantom distance jump.
      final staleThreshold =
          _startTime!.subtract(const Duration(seconds: 5));
      if (pos.timestamp.isBefore(staleThreshold)) {
        _diag.gpsFix(pos, 'reject-stale', 'REJECT stale (cached pre-start fix)');
        return;
      }

      // Fresh fix — anchor here and begin active tracking.
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
        setState(() => _elapsed = DateTime.now().difference(_startTime!));
      });
      _elevation.addGps(pos.altitude, pos.altitudeAccuracy);
      _diag.gpsFix(pos, 'anchor',
          'ACCEPT anchor acc=${pos.accuracy.toStringAsFixed(1)} m — tracking begins');
      setState(() {
        _gpsReady = true;
        _startTime = DateTime.now();
        _lastPosition = pos;
        _currentSpeed = pos.speed;
        _segments.last.add(_TrackPoint(pos, _elevation.currentAltitude,
            rawBaro: _elevation.lastRawBarometricAltitude));
        _isTracking = true;
        _starting = false;
        _message = null;
      });
      return;
    }

    final last = _lastPosition;
    if (last != null) {
      final gapSec =
          pos.timestamp.difference(last.timestamp).inSeconds.abs();
      if (gapSec > 60) {
        // GPS was lost for more than 60 s — open a new segment so the gap
        // appears as a break in GPX viewers and is not counted as distance.
        _segments.add([]);
        _teleportRejects = 0;
        _diag.segmentSplit('gap ${gapSec}s');
      } else {
        final meters = Geolocator.distanceBetween(
          last.latitude,
          last.longitude,
          pos.latitude,
          pos.longitude,
        );
        // Reject teleports: a fix implying a speed far beyond what the GPS
        // receiver itself reports is a provider glitch, not movement.
        final implied = meters / max(gapSec, 1);
        final speedCap = max(pos.speed > 0 ? pos.speed * 3 : 0.0, 15.0);
        if (implied > speedCap) {
          _teleportRejects++;
          if (_teleportRejects < 3) {
            _diag.gpsFix(pos, 'teleport',
                'TELEPORT $_teleportRejects/3 implied=${implied.toStringAsFixed(1)} m/s cap=${speedCap.toStringAsFixed(1)}');
            return;
          }
          // Three impossible fixes in a row means the previous anchor was
          // the glitch — re-anchor here in a new segment, counting nothing.
          _segments.add([]);
          _teleportRejects = 0;
          _diag.segmentSplit('re-anchor after 3 teleports');
        } else {
          _teleportRejects = 0;
          _distanceMeters += meters;
        }
      }
    }

    _elevation.addGps(pos.altitude, pos.altitudeAccuracy);
    _diag.gpsFix(pos, 'accept',
        'ACCEPT acc=${pos.accuracy.toStringAsFixed(1)} m alt=${pos.altitude.toStringAsFixed(1)} m');
    setState(() {
      _lastPosition = pos;
      _currentSpeed = pos.speed;
      _segments.last.add(_TrackPoint(pos, _elevation.currentAltitude,
          rawBaro: _elevation.lastRawBarometricAltitude));
    });
  }

  Future<void> _stop() async {
    await _positionSub?.cancel();
    _positionSub = null;

    // iOS: geolocator's stopListening() calls stopUpdatingLocation() but never
    // resets allowsBackgroundLocationUpdates or showsBackgroundLocationIndicator
    // on the shared CLLocationManager singleton. Those flags persist, so if the
    // app is backgrounded during the cleanup window, iOS still shows the blue
    // indicator. Resetting them requires going through startUpdatingLocation —
    // the only code path that writes those properties — so we open a brief
    // stream with both flags false and immediately cancel it.
    if (Platform.isIOS) {
      final reset = Geolocator.getPositionStream(
        locationSettings: AppleSettings(
          accuracy: LocationAccuracy.lowest,
          allowBackgroundLocationUpdates: false,
          showBackgroundLocationIndicator: false,
        ),
      ).listen((_) {}, onError: (_) {});
      await reset.cancel();
    }

    await _baroSub?.cancel();
    _baroSub = null;
    _ticker?.cancel();
    _ticker = null;

    if (_keepScreenOn) await WakelockPlus.disable();

    setState(() {
      _isTracking = false;
      _starting = false;
      _gpsReady = false;
    });

    if (_segments.every((s) => s.isEmpty)) {
      await _diag.stopRecorder();
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
      // Rename the flight recorder to match the GPX stamp (which was
      // finalized at GPS lock, after the recorder opened).
      await _diag.stopRecorder(renameTo: '${dir.path}/$stamp-debug.csv');

      setState(() {
        _message = 'Saved $stamp.gpx + .csv';
        _messageIsError = false;
      });
    } catch (e) {
      await _diag.stopRecorder();
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
      ..writeln('    <name>Track $stamp</name>');
    for (final segment in _segments) {
      if (segment.isEmpty) continue;
      buf.writeln('    <trkseg>');
      for (final p in segment) {
        final pos = p.position;
        buf
          ..writeln(
              '      <trkpt lat="${pos.latitude}" lon="${pos.longitude}">')
          ..writeln('        <ele>${p.elevation.toStringAsFixed(2)}</ele>')
          ..writeln(
              '        <time>${pos.timestamp.toUtc().toIso8601String()}</time>')
          ..writeln('      </trkpt>');
      }
      buf.writeln('    </trkseg>');
    }
    buf
      ..writeln('  </trk>')
      ..writeln('</gpx>');
    await File('$dirPath/$stamp.gpx').writeAsString(buf.toString());
  }

  Future<void> _saveCsv(String dirPath, String stamp) async {
    final distKm = (_distanceMeters / 1000).toStringAsFixed(3);
    final elevM = _elevation.gainMeters.toStringAsFixed(1);
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
      // Switch to miles once past 0.1 mi (528 ft); show feet below that.
      if (feet < 528) return '${feet.toStringAsFixed(0)} ft';
      return '${(feet / 5280).toStringAsFixed(2)} mi';
    }
    // Switch to km once past 0.1 km (100 m); show meters below that.
    if (_distanceMeters < 100) {
      return '${_distanceMeters.toStringAsFixed(0)} m';
    }
    return '${(_distanceMeters / 1000).toStringAsFixed(2)} km';
  }

  String _fmtElevation() {
    if (_useImperial) {
      return '+${(_elevation.gainMeters * 3.28084).toStringAsFixed(0)} ft';
    }
    return '+${_elevation.gainMeters.toStringAsFixed(0)} m';
  }

  String _fmtTime() {
    final h = _elapsed.inHours.toString().padLeft(2, '0');
    final m = (_elapsed.inMinutes % 60).toString().padLeft(2, '0');
    final s = (_elapsed.inSeconds % 60).toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  String _fmtSpeed() => formatSpeed(_currentSpeed, imperial: _useImperial);

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

  void _openInfo() {
    final t = widget.theme;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: t.screenBackground,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: Row(
          children: [
            Icon(Icons.terrain, color: t.startActive, size: 22),
            const SizedBox(width: 8),
            Text('Err', style: TextStyle(color: t.statValue, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Version 0.1.0', style: TextStyle(color: t.statLabel, fontSize: 12)),
            const SizedBox(height: 14),
            _InfoRow(
              icon: Icons.straighten,
              iconColor: t.statIcon,
              textColor: t.statValue,
              text: 'Records distance, elevation gain, and time for any outdoor activity.',
            ),
            const SizedBox(height: 10),
            _InfoRow(
              icon: Icons.show_chart,
              iconColor: t.statIcon,
              textColor: t.statValue,
              text: 'Uses the barometric pressure sensor for accurate elevation, falling back to GPS when unavailable.',
            ),
            const SizedBox(height: 10),
            _InfoRow(
              icon: Icons.palette_outlined,
              iconColor: t.statIcon,
              textColor: t.statValue,
              text: 'Fully themeable — 38 built-in color themes ported from the ef-themes collection, plus custom theme creation. Tap the palette icon to switch.',
            ),
            const SizedBox(height: 10),
            _InfoRow(
              icon: Icons.save_alt,
              iconColor: t.statIcon,
              textColor: t.statValue,
              text: 'Saves each trip as a GPX and CSV file to Android/data/com.example.err/files/ on your device.',
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Close', style: TextStyle(color: t.startActive)),
          ),
        ],
      ),
    );
  }

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

  // ── Navigation ───────────────────────────────────────────────────────────

  void _openStats() => Navigator.push<void>(
        context,
        MaterialPageRoute(
          builder: (_) => StatsScreen(
            theme: widget.theme,
            useImperial: _useImperial,
          ),
        ),
      );

  void _openHelp() => Navigator.push<void>(
        context,
        MaterialPageRoute(builder: (_) => HelpScreen(theme: widget.theme)),
      );

  void _openDebugTools() => Navigator.push<void>(
        context,
        MaterialPageRoute(
          builder: (_) => DebugScreen(diagnostics: _diag, theme: widget.theme),
        ),
      );

  void _openSettings() => Navigator.push<void>(
        context,
        MaterialPageRoute(
          builder: (_) => SettingsScreen(
            theme: widget.theme,
            useImperial: _useImperial,
            keepScreenOn: _keepScreenOn,
            showSpeed: _showSpeed,
            debugMode: _debugMode,
            onUseImperialChanged: _setUseImperial,
            onKeepScreenOnChanged: _setKeepScreenOn,
            onShowSpeedChanged: _setShowSpeed,
            onDebugModeChanged: _setDebugMode,
            onOpenTheme: _openThemePicker,
            onOpenDebugTools: _openDebugTools,
          ),
        ),
      );

  // ── Lifecycle ────────────────────────────────────────────────────────────

  @override
  void dispose() {
    _positionSub?.cancel();
    _baroSub?.cancel();
    _ticker?.cancel();
    _clockTicker?.cancel();
    _diag.dispose();
    if (_keepScreenOn) WakelockPlus.disable().ignore();
    super.dispose();
  }

  // ── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final t = widget.theme;

    return Scaffold(
      backgroundColor: t.screenBackground,
      drawer: ErrDrawer(
        theme: t,
        onStatistics: _openStats,
        onSettings: _openSettings,
        onHelp: _openHelp,
        onAbout: _openInfo,
      ),
      appBar: AppBar(
        backgroundColor: t.appBarBackground,
        title: Text('Err', style: TextStyle(color: t.appBarTitle)),
        iconTheme: IconThemeData(color: t.appBarTitle),
        actions: [
          IconButton(
            icon: const Icon(Icons.bar_chart),
            color: t.appBarTitle,
            tooltip: 'Statistics',
            onPressed: _openStats,
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
                    _StatTile(
                      icon: Icons.straighten,
                      label: 'Distance',
                      value: _fmtDistance(),
                      iconColor: t.statDistance,
                      labelColor: t.statDistance,
                      valueColor: t.statValue,
                    ),
                    if (_isTracking && _showSpeed) ...[
                      const SizedBox(height: 28),
                      _StatTile(
                        icon: Icons.speed,
                        label: 'Speed',
                        value: _fmtSpeed(),
                        iconColor: t.statTime,
                        labelColor: t.statTime,
                        valueColor: t.statValue,
                      ),
                    ],
                    const SizedBox(height: 28),
                    _StatTile(
                      icon: Icons.trending_up,
                      label: 'Elevation Gained',
                      value: _fmtElevation(),
                      iconColor: t.statElevation,
                      labelColor: t.statElevation,
                      valueColor: t.statValue,
                    ),
                    const SizedBox(height: 28),
                    _StatTile(
                      icon: Icons.timer_outlined,
                      label: 'Time',
                      value: _fmtTime(),
                      iconColor: t.statTime,
                      labelColor: t.statTime,
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

// ─── Track point ─────────────────────────────────────────────────────────────

class _TrackPoint {
  _TrackPoint(this.position, double? fusedAltitude, {this.rawBaro})
      : fused = fusedAltitude != null,
        elevation = fusedAltitude ?? position.altitude;

  final Position position;

  /// Raw barometric altitude at capture time, kept so pre-calibration
  /// points can be backfilled into the fused frame once the offset freezes.
  final double? rawBaro;

  /// Whether [elevation] came from the fused stream (vs raw GPS fallback).
  final bool fused;

  /// The fused altitude at the time the point was recorded — the same value
  /// the elevation-gain figure is computed from, so the GPX and UI agree.
  /// Mutable: backfilled at calibration and shifted on reference rebases.
  double elevation;
}

// ─── Info row (used in about dialog) ─────────────────────────────────────────

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.iconColor,
    required this.textColor,
    required this.text,
  });

  final IconData icon;
  final Color iconColor;
  final Color textColor;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: iconColor),
        const SizedBox(width: 8),
        Expanded(
          child: Text(text, style: TextStyle(color: textColor, fontSize: 13, height: 1.4)),
        ),
      ],
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
