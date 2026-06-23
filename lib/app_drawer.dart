import 'package:flutter/material.dart';

import 'err_theme.dart';

/// The app's navigation drawer. Replaces the cluster of app-bar icons the
/// tracker used to carry, giving Statistics, Settings, Help and About a single
/// discoverable home. Each entry closes the drawer, then runs its callback.
class ErrDrawer extends StatelessWidget {
  const ErrDrawer({
    super.key,
    required this.theme,
    required this.onStatistics,
    required this.onSettings,
    required this.onHelp,
    required this.onAbout,
  });

  final ErrTheme theme;
  final VoidCallback onStatistics;
  final VoidCallback onSettings;
  final VoidCallback onHelp;
  final VoidCallback onAbout;

  @override
  Widget build(BuildContext context) {
    final t = theme;
    return Drawer(
      backgroundColor: t.screenBackground,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
              child: Row(
                children: [
                  Icon(Icons.terrain, color: t.startActive, size: 28),
                  const SizedBox(width: 12),
                  Text(
                    'Err',
                    style: TextStyle(
                      color: t.statValue,
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            Divider(color: t.toggleBorder, height: 1),
            // The tracker is the current screen, so this entry just closes.
            _tile(context, Icons.show_chart, 'Track', null, current: true),
            _tile(context, Icons.bar_chart, 'Statistics', onStatistics),
            _tile(context, Icons.settings_outlined, 'Settings', onSettings),
            _tile(context, Icons.help_outline, 'Help', onHelp),
            _tile(context, Icons.info_outline, 'About', onAbout),
          ],
        ),
      ),
    );
  }

  Widget _tile(
    BuildContext context,
    IconData icon,
    String label,
    VoidCallback? onTap, {
    bool current = false,
  }) {
    final t = theme;
    return ListTile(
      leading: Icon(icon, color: current ? t.startActive : t.statIcon),
      title: Text(
        label,
        style: TextStyle(
          color: current ? t.startActive : t.statValue,
          fontWeight: current ? FontWeight.bold : FontWeight.normal,
        ),
      ),
      selected: current,
      onTap: () {
        Navigator.pop(context); // close the drawer
        onTap?.call();
      },
    );
  }
}
