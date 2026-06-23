import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:err/main.dart';

/// Pump the app on a phone-sized surface so the centered stat column fits
/// without a RenderFlex overflow (the default 800x600 test window is too
/// short), and let SharedPreferences.getInstance resolve.
Future<void> _pumpApp(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(1080, 2160));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(const ErrApp());
  await tester.pump();
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

  testWidgets('exposes a Statistics action', (tester) async {
    await _pumpApp(tester);

    expect(find.byTooltip('Statistics'), findsOneWidget);
    expect(find.byIcon(Icons.bar_chart), findsOneWidget);
  });

  testWidgets('speed tile is hidden until tracking starts', (tester) async {
    await _pumpApp(tester);

    expect(find.text('Speed'), findsNothing);
  });
}
