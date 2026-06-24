import 'package:flutter/widgets.dart';

import 'err_theme.dart';

/// Makes the active [ErrTheme] available to the whole widget tree, so screens
/// read it from context instead of receiving it through constructors.
///
/// Crucially this includes *pushed* routes: because the scope sits above the
/// app's [Navigator], a route that reads [ErrThemeScope.of] re-themes the
/// instant the theme changes — fixing the old behaviour where a pushed screen
/// captured the theme at push time and only updated once you backed out.
///
/// Small leaf widgets (the control bar, drawer, stat tiles) still take an
/// explicit theme/colour — they're always built under the current theme and
/// stay easy to test in isolation.
class ErrThemeScope extends InheritedWidget {
  const ErrThemeScope({super.key, required this.theme, required super.child});

  final ErrTheme theme;

  static ErrTheme of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<ErrThemeScope>();
    assert(scope != null, 'No ErrThemeScope found in context');
    return scope!.theme;
  }

  @override
  bool updateShouldNotify(ErrThemeScope oldWidget) => oldWidget.theme != theme;
}
