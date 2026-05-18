import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:err/main.dart';

void main() {
  testWidgets('shows prompt text before location is fetched', (tester) async {
    await tester.pumpWidget(const ErrApp());

    expect(find.text('Tap the button to get your location.'), findsOneWidget);
  });

  testWidgets('shows Get My Location button on initial load', (tester) async {
    await tester.pumpWidget(const ErrApp());

    expect(find.text('Get My Location'), findsOneWidget);
  });

  testWidgets('app bar shows Err title', (tester) async {
    await tester.pumpWidget(const ErrApp());

    expect(find.text('Err'), findsOneWidget);
  });

  testWidgets('button has location icon', (tester) async {
    await tester.pumpWidget(const ErrApp());

    expect(find.byIcon(Icons.my_location), findsOneWidget);
  });
}
