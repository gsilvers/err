import 'package:flutter/material.dart';

import 'err_theme.dart';

/// The bottom control bar. The left button morphs with the tracking state —
/// Start → Pause → Resume — while the right button is always Stop. Kept in its
/// own widget so the state combinations are easy to unit-test.
class TrackingControls extends StatelessWidget {
  const TrackingControls({
    super.key,
    required this.theme,
    required this.isTracking,
    required this.paused,
    required this.starting,
    required this.onStart,
    required this.onPause,
    required this.onResume,
    required this.onStop,
  });

  final ErrTheme theme;
  final bool isTracking;
  final bool paused;
  final bool starting;
  final VoidCallback onStart;
  final VoidCallback onPause;
  final VoidCallback onResume;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    final t = theme;
    // Pause is the only "left" state that is not a go-action, so it gets the
    // toggle colour to read as a hold rather than a start.
    final isPause = isTracking && !paused;

    final String leftLabel;
    final Widget leftIcon;
    final VoidCallback? leftOnPressed;
    if (!isTracking) {
      leftLabel = 'Start';
      leftIcon = starting
          ? SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: t.startForeground,
              ),
            )
          : const Icon(Icons.play_arrow);
      leftOnPressed = starting ? null : onStart;
    } else if (paused) {
      leftLabel = 'Resume';
      leftIcon = const Icon(Icons.play_arrow);
      leftOnPressed = onResume;
    } else {
      leftLabel = 'Pause';
      leftIcon = const Icon(Icons.pause);
      leftOnPressed = onPause;
    }

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
        child: Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: leftOnPressed,
                style: FilledButton.styleFrom(
                  backgroundColor:
                      isPause ? t.toggleSelectedBackground : t.startActive,
                  disabledBackgroundColor: t.startDisabled,
                  foregroundColor:
                      isPause ? t.toggleSelectedText : t.startForeground,
                  disabledForegroundColor: t.startForeground.withAlpha(120),
                  padding: const EdgeInsets.symmetric(vertical: 18),
                ),
                icon: leftIcon,
                label: Text(leftLabel, style: const TextStyle(fontSize: 16)),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: FilledButton.icon(
                onPressed: (isTracking || starting) ? onStop : null,
                style: FilledButton.styleFrom(
                  backgroundColor: t.stopActive,
                  disabledBackgroundColor: t.stopDisabled,
                  foregroundColor: t.stopForeground,
                  disabledForegroundColor: t.stopForeground.withAlpha(120),
                  padding: const EdgeInsets.symmetric(vertical: 18),
                ),
                icon: const Icon(Icons.stop),
                label: const Text('Stop', style: TextStyle(fontSize: 16)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
