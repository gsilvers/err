import 'package:flutter/material.dart';

import 'err_theme.dart';
import 'theme_scope.dart';

/// The one home for everything configurable. Consolidates the controls that
/// used to clutter the tracker's body (units, keep-screen-on) and the hidden
/// long-press debug gesture, and routes to the theme picker and debug tools.
///
/// Holds local copies of each value so its own switches react instantly, and
/// calls back into the tracker (which persists and rebuilds) on every change.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    required this.useImperial,
    required this.keepScreenOn,
    required this.showSpeed,
    required this.debugMode,
    required this.onUseImperialChanged,
    required this.onKeepScreenOnChanged,
    required this.onShowSpeedChanged,
    required this.onDebugModeChanged,
    required this.onOpenTheme,
    required this.onOpenAppearance,
    required this.onOpenDebugTools,
  });

  final bool useImperial;
  final bool keepScreenOn;
  final bool showSpeed;
  final bool debugMode;
  final ValueChanged<bool> onUseImperialChanged;
  final ValueChanged<bool> onKeepScreenOnChanged;
  final ValueChanged<bool> onShowSpeedChanged;
  final ValueChanged<bool> onDebugModeChanged;
  final VoidCallback onOpenTheme;
  final VoidCallback onOpenAppearance;
  final VoidCallback onOpenDebugTools;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late bool _useImperial = widget.useImperial;
  late bool _keepScreenOn = widget.keepScreenOn;
  late bool _showSpeed = widget.showSpeed;
  late bool _debugMode = widget.debugMode;

  @override
  Widget build(BuildContext context) {
    final t = ErrThemeScope.of(context);
    return Scaffold(
      backgroundColor: t.screenBackground,
      appBar: AppBar(
        backgroundColor: t.appBarBackground,
        iconTheme: IconThemeData(color: t.appBarTitle),
        title: Text('Settings', style: TextStyle(color: t.appBarTitle)),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          _header(t, 'Units'),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: Align(
              alignment: Alignment.centerLeft,
              child: SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: false, label: Text('Metric')),
                  ButtonSegment(value: true, label: Text('Imperial')),
                ],
                selected: {_useImperial},
                showSelectedIcon: false,
                onSelectionChanged: (s) {
                  setState(() => _useImperial = s.first);
                  widget.onUseImperialChanged(s.first);
                },
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
          ),
          _header(t, 'Display'),
          _switchTile(
            t,
            icon: Icons.stay_current_portrait,
            title: 'Keep screen on',
            subtitle: 'Stop the screen sleeping while tracking',
            value: _keepScreenOn,
            onChanged: (v) {
              setState(() => _keepScreenOn = v);
              widget.onKeepScreenOnChanged(v);
            },
          ),
          _switchTile(
            t,
            icon: Icons.speed,
            title: 'Show speed while tracking',
            subtitle: 'Add a live speed tile to the main screen',
            value: _showSpeed,
            onChanged: (v) {
              setState(() => _showSpeed = v);
              widget.onShowSpeedChanged(v);
            },
          ),
          _navTile(
            t,
            icon: Icons.palette_outlined,
            title: 'Theme',
            subtitle: 'Switch or create a colour theme',
            onTap: widget.onOpenTheme,
          ),
          _navTile(
            t,
            icon: Icons.wallpaper_outlined,
            title: 'Appearance',
            subtitle: 'Background photo and edge images',
            onTap: widget.onOpenAppearance,
          ),
          _header(t, 'Developer'),
          _switchTile(
            t,
            icon: Icons.bug_report_outlined,
            title: 'Debug mode',
            subtitle: 'Record a flight log and reveal diagnostic tools',
            value: _debugMode,
            onChanged: (v) {
              setState(() => _debugMode = v);
              widget.onDebugModeChanged(v);
            },
          ),
          if (_debugMode)
            _navTile(
              t,
              icon: Icons.terminal,
              title: 'Open debug tools',
              subtitle: 'Filter log, diagnostics and REPL',
              onTap: widget.onOpenDebugTools,
            ),
        ],
      ),
    );
  }

  Widget _header(ErrTheme t, String text) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
    child: Text(
      text.toUpperCase(),
      style: TextStyle(
        color: t.statLabel,
        fontSize: 12,
        fontWeight: FontWeight.bold,
        letterSpacing: 0.8,
      ),
    ),
  );

  Widget _switchTile(
    ErrTheme t, {
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) => SwitchListTile(
    value: value,
    onChanged: onChanged,
    secondary: Icon(icon, color: t.statIcon),
    title: Text(title, style: TextStyle(color: t.statValue)),
    subtitle: Text(
      subtitle,
      style: TextStyle(color: t.statLabel, fontSize: 12),
    ),
    activeThumbColor: t.toggleSelectedBackground,
    inactiveTrackColor: t.toggleUnselectedBackground,
  );

  Widget _navTile(
    ErrTheme t, {
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) => ListTile(
    leading: Icon(icon, color: t.statIcon),
    title: Text(title, style: TextStyle(color: t.statValue)),
    subtitle: Text(
      subtitle,
      style: TextStyle(color: t.statLabel, fontSize: 12),
    ),
    trailing: Icon(Icons.chevron_right, color: t.statLabel),
    onTap: onTap,
  );
}
