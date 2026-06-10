import 'package:flutter/material.dart';

import 'err_theme.dart';

/// Full-screen help, reached from the bottom of the About dialog.
/// Explains tracking, how the stats are computed, saved files, themes,
/// and the hidden debug tools.
class HelpScreen extends StatelessWidget {
  const HelpScreen({super.key, required this.theme});

  final ErrTheme theme;

  @override
  Widget build(BuildContext context) {
    final t = theme;
    return Scaffold(
      backgroundColor: t.screenBackground,
      appBar: AppBar(
        backgroundColor: t.appBarBackground,
        title: Text('Help', style: TextStyle(color: t.appBarTitle)),
        iconTheme: IconThemeData(color: t.appBarTitle),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
        children: [
          _Section(
            theme: t,
            icon: Icons.play_arrow,
            title: 'Tracking a trip',
            children: [
              _Para(t,
                  'Press Start and keep a clear view of the sky. The app '
                  'waits for a fresh, accurate GPS fix ("Waiting for GPS '
                  'lock…") before the timer begins — cached or inaccurate '
                  'fixes are discarded so a trip never starts with a '
                  'phantom jump.'),
              _Para(t,
                  'Press Stop to finish. The trip is saved as a GPX track '
                  'and a CSV summary.'),
              _Para(t,
                  'The Metric / Imperial switch changes units at any time. '
                  '"Keep screen on" stops the display sleeping while '
                  'tracking; either way, tracking continues with the '
                  'screen off.'),
            ],
          ),
          _Section(
            theme: t,
            icon: Icons.straighten,
            title: 'The stats',
            children: [
              _Para(t,
                  'Distance — the sum of GPS-measured legs, after filtering '
                  '(below).'),
              _Para(t,
                  'Elevation Gained — total climb. On phones with a '
                  'barometric pressure sensor (most), the barometer '
                  'measures altitude change and GPS anchors it; otherwise '
                  'GPS altitude is used alone. Only sustained climbs '
                  'count — brief blips from sensor noise are ignored, the '
                  'same way Strava and Garmin measure. Expect smaller, '
                  'more honest numbers than apps that count every wiggle.'),
              _Para(t, 'Time — elapsed since the GPS lock.'),
            ],
          ),
          _Section(
            theme: t,
            icon: Icons.filter_alt_outlined,
            title: 'Accuracy filtering',
            children: [
              _Para(t,
                  'Raw GPS is noisy: positions wander several metres and '
                  'altitude is 2–4× worse. Err filters so the numbers '
                  'reflect movement, not noise:'),
              _Bullet(t, 'Fixes with worse than 25 m accuracy are ignored.'),
              _Bullet(t,
                  'Fixes implying impossible speed (GPS "teleports") are '
                  'rejected.'),
              _Bullet(t,
                  'A gap of more than 60 s splits the track into separate '
                  'segments, so missing data never counts as distance.'),
              _Bullet(t,
                  'Elevation gain only counts climbs that rise more than '
                  '3 m (barometer) or 10 m (GPS) above the most recent low '
                  'point.'),
              _Para(t,
                  'The elevations written to the GPX file are the same '
                  'fused values the gain figure is computed from, so the '
                  'app and the file always agree.'),
            ],
          ),
          _Section(
            theme: t,
            icon: Icons.save_alt,
            title: 'Saved files',
            children: [
              _Para(t,
                  'Each trip is saved to Android/data/com.example.err/files/ '
                  'on your device:'),
              _Bullet(t, '<date>.gpx — the track, openable in any GPX tool.'),
              _Bullet(t, '<date>.csv — distance, elevation gain, and time.'),
              _Bullet(t,
                  '<date>-debug.csv — every raw sample and filter decision '
                  '(only when debug mode is on).'),
              _Para(t,
                  'Nothing ever leaves your device: no accounts, no '
                  'uploads, no analytics.'),
            ],
          ),
          _Section(
            theme: t,
            icon: Icons.palette_outlined,
            title: 'Themes',
            children: [
              _Para(t,
                  'The palette icon opens the theme picker: 38 built-in '
                  'themes ported from the ef-themes collection, plus an '
                  'editor for your own.'),
            ],
          ),
          _Section(
            theme: t,
            icon: Icons.bug_report_outlined,
            title: 'Debug mode (for testing)',
            children: [
              _Para(t,
                  'Long-press the "Err" title in the app bar to toggle '
                  'debug mode. A bug icon appears, opening a screen with '
                  'two tabs:'),
              _Bullet(t,
                  'Log — a live stream of every GPS fix with the filter\'s '
                  'verdict (accepted, rejected and why), barometer '
                  'samples, and elevation-tracker events.'),
              _Bullet(t,
                  'REPL — a small lisp console for inspecting live state, '
                  'strictly read-only. Type (help) to list commands:'),
              _Mono(t,
                  '(stats)  (gps)  (gps-history n)\n'
                  '(fix-age)  (baro)  (elev)\n'
                  "(counters)  (log n 'gps)"),
              _Para(t,
                  'Trips started with debug mode on also write the '
                  '<date>-debug.csv flight-recorder file, which captures '
                  'everything that happened while the phone was in your '
                  'pocket. The log resets at each Start and stays '
                  'readable after Stop.'),
            ],
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({
    required this.theme,
    required this.icon,
    required this.title,
    required this.children,
  });

  final ErrTheme theme;
  final IconData icon;
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: theme.statIcon),
              const SizedBox(width: 8),
              Text(
                title,
                style: TextStyle(
                  color: theme.statValue,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ...children,
        ],
      ),
    );
  }
}

class _Para extends StatelessWidget {
  const _Para(this.theme, this.text);

  final ErrTheme theme;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: TextStyle(color: theme.statLabel, fontSize: 13, height: 1.45),
      ),
    );
  }
}

class _Bullet extends StatelessWidget {
  const _Bullet(this.theme, this.text);

  final ErrTheme theme;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('•  ',
              style: TextStyle(color: theme.statIcon, fontSize: 13)),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                  color: theme.statLabel, fontSize: 13, height: 1.45),
            ),
          ),
        ],
      ),
    );
  }
}

class _Mono extends StatelessWidget {
  const _Mono(this.theme, this.text);

  final ErrTheme theme;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: theme.toggleUnselectedBackground,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: theme.toggleBorder),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontFamily: 'monospace',
          fontSize: 12.5,
          height: 1.5,
          color: theme.statValue,
        ),
      ),
    );
  }
}
