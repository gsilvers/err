import 'package:err/builtin_themes.dart';
import 'package:err/theme_scope.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('ErrThemeScope.of exposes the theme and rebuilds dependents', (
    tester,
  ) async {
    final themeA = builtinThemes[0];
    final themeB = builtinThemes[1];
    late StateSetter setOuter;
    var theme = themeA;

    await tester.pumpWidget(
      StatefulBuilder(
        builder: (context, setState) {
          setOuter = setState;
          return Directionality(
            textDirection: TextDirection.ltr,
            child: ErrThemeScope(
              theme: theme,
              child: Builder(
                builder: (context) => Text(ErrThemeScope.of(context).id),
              ),
            ),
          );
        },
      ),
    );

    expect(find.text(themeA.id), findsOneWidget);

    // Swapping the scope's theme re-themes the dependent — the behaviour that
    // was broken when screens captured the theme at construction.
    setOuter(() => theme = themeB);
    await tester.pump();

    expect(find.text(themeB.id), findsOneWidget);
    expect(find.text(themeA.id), findsNothing);
  });
}
