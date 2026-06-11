import 'package:err/builtin_themes.dart';
import 'package:err/err_theme.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('every builtin theme gives the three stat headings distinct colors',
      () {
    for (final t in builtinThemes) {
      final headings = {t.statDistance, t.statElevation, t.statTime};
      expect(headings.length, 3,
          reason: '${t.id} reuses a heading color');
      // The point is to stand out from the generic label color too.
      expect(headings.contains(t.statLabel), isFalse,
          reason: '${t.id} heading color equals statLabel');
    }
  });

  test('heading colors survive a JSON round trip', () {
    final t = builtinThemes.first;
    final back = ErrTheme.fromJson(t.toJson());
    expect(back.statDistance, t.statDistance);
    expect(back.statElevation, t.statElevation);
    expect(back.statTime, t.statTime);
  });

  test('custom themes saved before the heading slots fall back to statLabel',
      () {
    final json = builtinThemes.first.toJson()
      ..remove('statDistance')
      ..remove('statElevation')
      ..remove('statTime');
    final t = ErrTheme.fromJson(json);
    expect(t.statDistance, t.statLabel);
    expect(t.statElevation, t.statLabel);
    expect(t.statTime, t.statLabel);
  });
}
