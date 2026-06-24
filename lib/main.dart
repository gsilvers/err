import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'app_drawer.dart';
import 'appearance.dart';
import 'appearance_screen.dart';
import 'builtin_themes.dart';
import 'custom_theme_editor.dart';
import 'debug/debug_screen.dart';
import 'debug/diagnostics.dart';
import 'err_theme.dart';
import 'help_screen.dart';
import 'pref_keys.dart';
import 'settings_screen.dart';
import 'stats_screen.dart';
import 'storage.dart';
import 'theme_picker.dart';
import 'theme_scope.dart';
import 'tracking_controller.dart';
import 'tracking_controls.dart';
import 'trip_writer.dart';
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

    final id = prefs.getString(PrefKeys.selectedThemeId);
    List<ErrTheme> customs = [];
    try {
      customs =
          (jsonDecode(prefs.getString(PrefKeys.customThemes) ?? '[]') as List)
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
    _prefs?.setString(PrefKeys.selectedThemeId, t.id);
  }

  void _saveCustomTheme(ErrTheme t) {
    setState(() {
      _customThemes = [..._customThemes.where((c) => c.id != t.id), t];
    });
    _prefs?.setString(
      PrefKeys.customThemes,
      jsonEncode(_customThemes.map((c) => c.toJson()).toList()),
    );
  }

  void _deleteCustomTheme(String id) {
    setState(() {
      _customThemes = _customThemes.where((t) => t.id != id).toList();
    });
    _prefs?.setString(
      PrefKeys.customThemes,
      jsonEncode(_customThemes.map((c) => c.toJson()).toList()),
    );
    if (_theme.id == id) _applyTheme(builtinThemes.first);
  }

  @override
  Widget build(BuildContext context) {
    // The scope sits above the MaterialApp so every screen — including pushed
    // routes — reads the live theme from context and re-themes on change.
    return ErrThemeScope(
      theme: _theme,
      child: MaterialApp(
        title: 'Err',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          brightness: _theme.isDark ? Brightness.dark : Brightness.light,
        ),
        home: TrackerScreen(
          customThemes: _customThemes,
          onThemeChanged: _applyTheme,
          onSaveCustomTheme: _saveCustomTheme,
          onDeleteCustomTheme: _deleteCustomTheme,
        ),
      ),
    );
  }
}

// ─── Tracker screen ──────────────────────────────────────────────────────────

class TrackerScreen extends StatefulWidget {
  const TrackerScreen({
    super.key,
    required this.customThemes,
    required this.onThemeChanged,
    required this.onSaveCustomTheme,
    required this.onDeleteCustomTheme,
  });

  final List<ErrTheme> customThemes;
  final void Function(ErrTheme) onThemeChanged;
  final void Function(ErrTheme) onSaveCustomTheme;
  final void Function(String) onDeleteCustomTheme;

  @override
  State<TrackerScreen> createState() => _TrackerScreenState();
}

class _TrackerScreenState extends State<TrackerScreen> {
  // Pressed Start, still resolving permission / awaiting the first lock. This
  // covers the brief window before the controller flips to `acquiring`.
  bool _starting = false;
  bool _useImperial = false;
  bool _keepScreenOn = false;
  bool _showSpeed = true;
  bool _debugMode = false;
  String? _message;
  bool _messageIsError = false;

  final TrackingDiagnostics _diag = TrackingDiagnostics();
  late final TrackingController _controller;

  SharedPreferences? _prefs;
  AppearanceStore? _appearanceStore;
  AppearanceSettings _appearance = const AppearanceSettings();
  StreamSubscription<Position>? _positionSub;
  StreamSubscription<BarometerEvent>? _baroSub;
  Timer? _clockTicker;

  @override
  void initState() {
    super.initState();
    _controller = TrackingController(diagnostics: _diag);
    _controller.addListener(_onTrackingChanged);
    _clockTicker = Timer.periodic(
      const Duration(seconds: 1),
      (_) => setState(() {}),
    );
    _loadPrefs();
  }

  void _onTrackingChanged() {
    // Clear the "waiting for GPS" prompt the moment a lock is achieved.
    if (_controller.status == TrackingStatus.tracking &&
        _message == 'Waiting for GPS lock…') {
      _message = null;
    }
    setState(() {});
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final appearanceStore = await AppearanceStore.open();
    final appearance = appearanceStore.load();
    if (!mounted) return;
    setState(() {
      _prefs = prefs;
      _appearanceStore = appearanceStore;
      _appearance = appearance;
      _keepScreenOn = prefs.getBool(PrefKeys.keepScreenOn) ?? false;
      _debugMode = prefs.getBool(PrefKeys.debugMode) ?? false;
      _useImperial = prefs.getBool(PrefKeys.useImperial) ?? false;
      _showSpeed = prefs.getBool(PrefKeys.showSpeed) ?? true;
    });
  }

  void _setAppearance(AppearanceSettings s) {
    setState(() => _appearance = s);
    _appearanceStore?.save(s);
  }

  void _setUseImperial(bool v) {
    setState(() => _useImperial = v);
    _prefs?.setBool(PrefKeys.useImperial, v);
  }

  void _setShowSpeed(bool v) {
    setState(() => _showSpeed = v);
    _prefs?.setBool(PrefKeys.showSpeed, v);
  }

  void _setDebugMode(bool v) {
    setState(() => _debugMode = v);
    _prefs?.setBool(PrefKeys.debugMode, v);
  }

  void _setKeepScreenOn(bool v) {
    setState(() => _keepScreenOn = v);
    _prefs?.setBool(PrefKeys.keepScreenOn, v);
    if (_controller.isTracking) {
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

    final startTime = _controller.beginAcquiring();

    if (_keepScreenOn) await WakelockPlus.enable();

    if (_debugMode) {
      // Flight recorder: every raw sample + verdict, written beside the
      // GPX. Failures here must never block tracking.
      try {
        final dir = await appStorageDirectory();
        final stamp = startTime
            .toIso8601String()
            .replaceAll(':', '-')
            .substring(0, 19);
        _diag.startRecorder('${dir.path}/$stamp-debug.csv');
      } catch (_) {}
    }

    setState(() => _starting = false);

    _positionSub =
        Geolocator.getPositionStream(
          locationSettings: Platform.isAndroid
              ? AndroidSettings(
                  accuracy: LocationAccuracy.high,
                  distanceFilter: 5,
                  intervalDuration: const Duration(seconds: 3),
                  foregroundNotificationConfig:
                      const ForegroundNotificationConfig(
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
        ).listen(
          _controller.addPosition,
          onError: (e) {
            setState(() {
              _message = 'GPS error: $e';
              _messageIsError = true;
            });
          },
        );

    // Start barometer; errors mean the device has no sensor — fall back to GPS.
    _baroSub = Sensors()
        .barometerEventStream(samplingPeriod: const Duration(seconds: 2))
        .listen(
          (event) => _controller.addBarometerPressure(event.pressure),
          onError: (_) {},
        );

    // The controller flips to `tracking` once a fresh fix arrives.
  }

  void _pause() {
    if (!_controller.isTracking || _controller.isPaused) return;
    _controller.pause();
    setState(() {
      _message = 'Paused';
      _messageIsError = false;
    });
  }

  void _resume() {
    if (!_controller.isPaused) return;
    _controller.resume();
    setState(() => _message = null);
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

    if (_keepScreenOn) await WakelockPlus.disable();

    setState(() => _starting = false);
    final recording = _controller.finish();

    if (recording.isEmpty) {
      await _diag.stopRecorder();
      setState(() {
        _message = 'No points recorded — nothing saved.';
        _messageIsError = true;
      });
      return;
    }

    try {
      final dir = await appStorageDirectory();

      final stamp = (_controller.startTime ?? DateTime.now())
          .toIso8601String()
          .replaceAll(':', '-')
          .substring(0, 19);

      await TripWriter(dir).write(recording, stamp);
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

  // ── Formatting ───────────────────────────────────────────────────────────

  String _fmtDistance() =>
      formatLiveDistance(_controller.distanceMeters, imperial: _useImperial);

  String _fmtElevation() =>
      '+${formatElevation(_controller.elevationGainMeters, imperial: _useImperial)}';

  String _fmtTime() => formatDuration(_controller.elapsed);

  String _fmtSpeed() =>
      formatSpeed(_controller.currentSpeedMps, imperial: _useImperial);

  String _fmtDateTime() {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
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
    final t = ErrThemeScope.of(context);
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: t.screenBackground,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: Row(
          children: [
            Icon(Icons.terrain, color: t.startActive, size: 22),
            const SizedBox(width: 8),
            Text(
              'Err',
              style: TextStyle(color: t.statValue, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Version 0.1.0',
              style: TextStyle(color: t.statLabel, fontSize: 12),
            ),
            const SizedBox(height: 14),
            _InfoRow(
              icon: Icons.straighten,
              iconColor: t.statIcon,
              textColor: t.statValue,
              text:
                  'Records distance, elevation gain, and time for any outdoor activity.',
            ),
            const SizedBox(height: 10),
            _InfoRow(
              icon: Icons.show_chart,
              iconColor: t.statIcon,
              textColor: t.statValue,
              text:
                  'Uses the barometric pressure sensor for accurate elevation, falling back to GPS when unavailable.',
            ),
            const SizedBox(height: 10),
            _InfoRow(
              icon: Icons.palette_outlined,
              iconColor: t.statIcon,
              textColor: t.statValue,
              text:
                  'Fully themeable — 38 built-in color themes ported from the ef-themes collection, plus custom theme creation. Tap the palette icon to switch.',
            ),
            const SizedBox(height: 10),
            _InfoRow(
              icon: Icons.save_alt,
              iconColor: t.statIcon,
              textColor: t.statValue,
              text:
                  'Saves each trip as a GPX and CSV file to Android/data/com.example.err/files/ on your device.',
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
          activeTheme: ErrThemeScope.of(context),
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
                  baseTheme: ErrThemeScope.of(context),
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
    MaterialPageRoute(builder: (_) => StatsScreen(useImperial: _useImperial)),
  );

  void _openHelp() => Navigator.push<void>(
    context,
    MaterialPageRoute(builder: (_) => const HelpScreen()),
  );

  void _openDebugTools() => Navigator.push<void>(
    context,
    MaterialPageRoute(
      builder: (_) =>
          DebugScreen(diagnostics: _diag, theme: ErrThemeScope.of(context)),
    ),
  );

  void _openAppearance() {
    final store = _appearanceStore;
    if (store == null) return;
    Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => AppearanceScreen(
          store: store,
          settings: _appearance,
          onChanged: _setAppearance,
        ),
      ),
    );
  }

  void _openSettings() => Navigator.push<void>(
    context,
    MaterialPageRoute(
      builder: (_) => SettingsScreen(
        useImperial: _useImperial,
        keepScreenOn: _keepScreenOn,
        showSpeed: _showSpeed,
        debugMode: _debugMode,
        onUseImperialChanged: _setUseImperial,
        onKeepScreenOnChanged: _setKeepScreenOn,
        onShowSpeedChanged: _setShowSpeed,
        onDebugModeChanged: _setDebugMode,
        onOpenTheme: _openThemePicker,
        onOpenAppearance: _openAppearance,
        onOpenDebugTools: _openDebugTools,
      ),
    ),
  );

  // ── Lifecycle ────────────────────────────────────────────────────────────

  @override
  void dispose() {
    _positionSub?.cancel();
    _baroSub?.cancel();
    _clockTicker?.cancel();
    _controller.removeListener(_onTrackingChanged);
    _controller.dispose();
    _diag.dispose();
    if (_keepScreenOn) WakelockPlus.disable().ignore();
    super.dispose();
  }

  // ── Build ────────────────────────────────────────────────────────────────

  /// The optional background photo, blended over the theme background at the
  /// chosen opacity. Empty when no image is set.
  Widget _backgroundLayer() {
    final file = _appearanceStore?.backgroundFile(_appearance);
    if (file == null) return const SizedBox.shrink();
    return Positioned.fill(
      child: Opacity(
        opacity: _appearance.backgroundOpacity,
        child: Image.file(file, fit: _appearance.backgroundFit),
      ),
    );
  }

  /// Decorative images banded along any chosen edge. They sit above the
  /// background but below the stat content, so the numbers and buttons stay
  /// on top and readable.
  List<Widget> _edgeLayers() {
    final store = _appearanceStore;
    if (store == null) return const [];
    const band = 80.0;
    final layers = <Widget>[];
    for (final edge in DecorationEdge.values) {
      final file = store.imageFile(_appearance.edgeImage(edge));
      if (file == null) continue;
      final img = Image.file(file, fit: BoxFit.cover);
      layers.add(switch (edge) {
        DecorationEdge.top => Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: band,
          child: img,
        ),
        DecorationEdge.bottom => Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          height: band,
          child: img,
        ),
        DecorationEdge.left => Positioned(
          top: 0,
          bottom: 0,
          left: 0,
          width: band,
          child: img,
        ),
        DecorationEdge.right => Positioned(
          top: 0,
          bottom: 0,
          right: 0,
          width: band,
          child: img,
        ),
      });
    }
    return layers;
  }

  @override
  Widget build(BuildContext context) {
    final t = ErrThemeScope.of(context);

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
      body: Stack(
        fit: StackFit.expand,
        children: [
          _backgroundLayer(),
          ..._edgeLayers(),
          Column(
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
                        if (_controller.isTracking && _showSpeed) ...[
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
              TrackingControls(
                theme: t,
                isTracking: _controller.isTracking,
                paused: _controller.isPaused,
                starting: _starting || _controller.isAcquiring,
                onStart: _start,
                onPause: _pause,
                onResume: _resume,
                onStop: _stop,
              ),
            ],
          ),
        ],
      ),
    );
  }
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
          child: Text(
            text,
            style: TextStyle(color: textColor, fontSize: 13, height: 1.4),
          ),
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
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: labelColor),
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
