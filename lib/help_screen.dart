import 'package:flutter/material.dart';

import 'err_theme.dart';
import 'theme_scope.dart';

/// In-app help. Plain, themed, scrollable prose — what the tracker does, how
/// its numbers are kept honest, and where the data lives. Content is curated
/// from `docs/gps-accuracy.md` and the project's privacy goals.
class HelpScreen extends StatelessWidget {
  const HelpScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final t = ErrThemeScope.of(context);
    return Scaffold(
      backgroundColor: t.screenBackground,
      appBar: AppBar(
        backgroundColor: t.appBarBackground,
        iconTheme: IconThemeData(color: t.appBarTitle),
        title: Text('Help', style: TextStyle(color: t.appBarTitle)),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        children: [
          _Section(
            theme: t,
            icon: Icons.play_arrow,
            title: 'Getting started',
            body: 'Press Start to begin. Err waits for a fresh GPS lock — '
                'shown as "Waiting for GPS lock…" — then records distance, '
                'elevation gain, and time. Press Stop to finish and save.',
          ),
          _Section(
            theme: t,
            icon: Icons.straighten,
            title: 'Accurate by design',
            body: 'Raw GPS is noisy, so Err filters it the way Strava and '
                'Garmin do, all on your device:',
            bullets: const [
              'Fixes with poor accuracy (over 25 m) are ignored.',
              'A stale cached fix at the start is discarded so the trip does '
                  'not begin with a phantom jump.',
              'Impossible "teleport" jumps are rejected using the receiver\'s '
                  'own speed.',
              'Elevation comes from the barometer (about 0.5 m resolution), '
                  'anchored to GPS, falling back to GPS altitude when no '
                  'pressure sensor is present.',
            ],
          ),
          _Section(
            theme: t,
            icon: Icons.trending_up,
            title: 'Elevation gain',
            body: 'Only sustained climbs count — 3 m with the barometer, 10 m '
                'on GPS fallback — so wind gusts and sensor noise do not '
                'inflate the number. Rolling terrain below that threshold '
                'records no gain, matching how Strava and Garmin flatten the '
                'same micro-terrain.',
          ),
          _Section(
            theme: t,
            icon: Icons.bar_chart,
            title: 'Statistics',
            body: 'Open Statistics from the menu to see totals for this month '
                'and this year, a year-by-year breakdown, and a history of '
                'every activity. Long-press a history entry to delete that '
                'saved trip.',
          ),
          _Section(
            theme: t,
            icon: Icons.save_alt,
            title: 'Your data stays yours',
            body: 'Each trip is saved as a GPX track and a CSV summary in the '
                'app\'s files folder on your device. There are no accounts and '
                'no network — nothing is uploaded anywhere. The files are '
                'plain and portable, so you can copy them off or open them in '
                'any GPX tool.',
          ),
          _Section(
            theme: t,
            icon: Icons.palette_outlined,
            title: 'Themes',
            body: 'Err ships with dozens of colour themes ported from the '
                'ef-themes collection, plus a custom theme editor. Change them '
                'in Settings → Theme.',
          ),
          _Section(
            theme: t,
            icon: Icons.tips_and_updates_outlined,
            title: 'Tips',
            body: 'For long activities, turn on "Keep screen on" in Settings. '
                'The barometer needs a few samples to calibrate, so elevation '
                'settles in the first minute of a trip.',
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
    required this.body,
    this.bullets = const [],
  });

  final ErrTheme theme;
  final IconData icon;
  final String title;
  final String body;
  final List<String> bullets;

  @override
  Widget build(BuildContext context) {
    final t = theme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 20, color: t.statIcon),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    color: t.statValue,
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            body,
            style: TextStyle(color: t.statLabel, fontSize: 14, height: 1.45),
          ),
          for (final b in bullets)
            Padding(
              padding: const EdgeInsets.only(top: 8, left: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('•  ', style: TextStyle(color: t.statIcon, fontSize: 14)),
                  Expanded(
                    child: Text(
                      b,
                      style: TextStyle(
                          color: t.statLabel, fontSize: 14, height: 1.4),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
