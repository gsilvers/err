import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:err/builtin_themes.dart';
import 'package:err/tracking_controls.dart';

void main() {
  Widget host({
    required bool isTracking,
    required bool paused,
    required bool starting,
    VoidCallback? onStart,
    VoidCallback? onPause,
    VoidCallback? onResume,
    VoidCallback? onStop,
  }) =>
      MaterialApp(
        home: Scaffold(
          body: TrackingControls(
            theme: builtinThemes.first,
            isTracking: isTracking,
            paused: paused,
            starting: starting,
            onStart: onStart ?? () {},
            onPause: onPause ?? () {},
            onResume: onResume ?? () {},
            onStop: onStop ?? () {},
          ),
        ),
      );

  testWidgets('idle shows Start; Stop is disabled', (tester) async {
    var started = false;
    var stopped = false;
    await tester.pumpWidget(host(
      isTracking: false,
      paused: false,
      starting: false,
      onStart: () => started = true,
      onStop: () => stopped = true,
    ));

    expect(find.text('Start'), findsOneWidget);
    expect(find.text('Stop'), findsOneWidget);
    expect(find.text('Pause'), findsNothing);

    await tester.tap(find.text('Stop'), warnIfMissed: false);
    expect(stopped, isFalse); // Stop is disabled when idle

    await tester.tap(find.text('Start'));
    expect(started, isTrue);
  });

  testWidgets('starting shows a spinner and disables Start', (tester) async {
    var started = false;
    await tester.pumpWidget(host(
      isTracking: false,
      paused: false,
      starting: true,
      onStart: () => started = true,
    ));

    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    await tester.tap(find.text('Start'), warnIfMissed: false);
    expect(started, isFalse);
  });

  testWidgets('tracking shows Pause and fires onPause', (tester) async {
    var paused = false;
    await tester.pumpWidget(host(
      isTracking: true,
      paused: false,
      starting: false,
      onPause: () => paused = true,
    ));

    expect(find.text('Pause'), findsOneWidget);
    expect(find.text('Start'), findsNothing);

    await tester.tap(find.text('Pause'));
    expect(paused, isTrue);
  });

  testWidgets('paused shows Resume and fires onResume', (tester) async {
    var resumed = false;
    await tester.pumpWidget(host(
      isTracking: true,
      paused: true,
      starting: false,
      onResume: () => resumed = true,
    ));

    expect(find.text('Resume'), findsOneWidget);
    expect(find.text('Pause'), findsNothing);

    await tester.tap(find.text('Resume'));
    expect(resumed, isTrue);
  });

  testWidgets('Stop fires while tracking', (tester) async {
    var stopped = false;
    await tester.pumpWidget(host(
      isTracking: true,
      paused: false,
      starting: false,
      onStop: () => stopped = true,
    ));

    await tester.tap(find.text('Stop'));
    expect(stopped, isTrue);
  });
}
