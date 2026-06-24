import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:err/builtin_themes.dart';
import 'package:err/help_screen.dart';
import 'package:err/main.dart';
import 'package:err/settings_screen.dart';
import 'package:err/theme_scope.dart';

/// Pump the app on a phone-sized surface so the centered stat column fits
/// without a RenderFlex overflow (the default 800x600 test window is too
/// short), and let SharedPreferences.getInstance resolve.
Future<void> _pumpApp(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(1080, 2160));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(const ErrApp());
  await tester.pump();
}

/// Pump a standalone screen on a tall surface so a lazy ListView builds all
/// of its rows (otherwise off-screen rows aren't in the tree to find).
Future<void> _pumpScreen(WidgetTester tester, Widget screen) async {
  await tester.binding.setSurfaceSize(const Size(1080, 2160));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      home: ErrThemeScope(theme: builtinThemes.first, child: screen),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('app bar shows the Err title', (tester) async {
    await _pumpApp(tester);

    expect(find.text('Err'), findsOneWidget);
  });

  testWidgets('shows Start and Stop controls', (tester) async {
    await _pumpApp(tester);

    expect(find.text('Start'), findsOneWidget);
    expect(find.text('Stop'), findsOneWidget);
  });

  testWidgets('shows the core stat tiles', (tester) async {
    await _pumpApp(tester);

    expect(find.text('Distance'), findsOneWidget);
    expect(find.text('Elevation Gained'), findsOneWidget);
    expect(find.text('Time'), findsOneWidget);
  });

  testWidgets('app bar keeps only the Statistics action', (tester) async {
    await _pumpApp(tester);

    expect(find.byTooltip('Statistics'), findsOneWidget);
    // About and Theme moved into the drawer / Settings.
    expect(find.byTooltip('About'), findsNothing);
    expect(find.byTooltip('Theme'), findsNothing);
  });

  testWidgets('main body no longer carries inline settings', (tester) async {
    await _pumpApp(tester);

    // Units toggle and keep-screen-on switch moved into Settings.
    expect(find.text('Metric'), findsNothing);
    expect(find.text('Keep screen on'), findsNothing);
  });

  testWidgets('speed tile is hidden until tracking starts', (tester) async {
    await _pumpApp(tester);

    expect(find.text('Speed'), findsNothing);
  });

  testWidgets('drawer exposes the navigation destinations', (tester) async {
    await _pumpApp(tester);

    await tester.tap(find.byTooltip('Open navigation menu'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Track'), findsOneWidget);
    expect(find.text('Statistics'), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('Help'), findsOneWidget);
    expect(find.text('About'), findsOneWidget);
  });

  testWidgets('Settings screen renders its controls', (tester) async {
    await _pumpScreen(
      tester,
      SettingsScreen(
        useImperial: false,
        keepScreenOn: false,
        showSpeed: true,
        debugMode: false,
        onUseImperialChanged: (_) {},
        onKeepScreenOnChanged: (_) {},
        onShowSpeedChanged: (_) {},
        onDebugModeChanged: (_) {},
        onOpenTheme: () {},
        onOpenAppearance: () {},
        onOpenDebugTools: () {},
      ),
    );

    expect(find.text('Metric'), findsOneWidget);
    expect(find.text('Imperial'), findsOneWidget);
    expect(find.text('Keep screen on'), findsOneWidget);
    expect(find.text('Show speed while tracking'), findsOneWidget);
    expect(find.text('Theme'), findsOneWidget);
    expect(find.text('Debug mode'), findsOneWidget);
  });

  testWidgets('debug tools row appears only when debug mode is on',
      (tester) async {
    SettingsScreen settings(bool debug) => SettingsScreen(
          key: ValueKey('debug_$debug'),
          useImperial: false,
          keepScreenOn: false,
          showSpeed: true,
          debugMode: debug,
          onUseImperialChanged: (_) {},
          onKeepScreenOnChanged: (_) {},
          onShowSpeedChanged: (_) {},
          onDebugModeChanged: (_) {},
          onOpenTheme: () {},
          onOpenAppearance: () {},
          onOpenDebugTools: () {},
        );

    await _pumpScreen(tester, settings(false));
    expect(find.text('Open debug tools'), findsNothing);

    await _pumpScreen(tester, settings(true));
    expect(find.text('Open debug tools'), findsOneWidget);
  });

  testWidgets('Help screen renders its sections', (tester) async {
    await _pumpScreen(tester, const HelpScreen());

    expect(find.text('Getting started'), findsOneWidget);
    expect(find.text('Your data stays yours'), findsOneWidget);
  });
}
