import 'diagnostics.dart';
import 'mini_lisp.dart';

/// Installs Err's read-only state-inspection builtins into [interp].
///
/// Every builtin is a getter over [TrackingDiagnostics] — the REPL cannot
/// mutate app state. Results are assoc lists so they compose with the core
/// list functions (`assoc`, `map`, `filter`, ...).
void installReplEnv(Interpreter interp, TrackingDiagnostics diag) {
  Object? checkedArity(List<Object?> args, int min, int max, String name) {
    if (args.length < min || args.length > max) {
      throw LispError('$name takes $min'
          '${max == min ? '' : '–$max'} arg${max == 1 ? '' : 's'}');
    }
    return null;
  }

  int count(List<Object?> args, int fallback) {
    if (args.isEmpty) return fallback;
    final n = args[0];
    if (n is! double) throw LispError('expected a number');
    return n.toInt();
  }

  interp.def('stats', (args) {
    final stats = diag.statsProvider?.call();
    return stats == null ? null : mapToAlist(stats);
  });

  interp.def('gps', (args) {
    final fix = diag.fixWithAge();
    return fix == null ? null : mapToAlist(fix);
  });

  interp.def('gps-history', (args) {
    checkedArity(args, 0, 1, 'gps-history');
    final n = count(args, 20);
    final fixes = diag.fixHistory.toList().reversed.take(n); // newest first
    return listToLisp(fixes.map(mapToAlist));
  });

  interp.def('fix-age', (args) {
    final t = diag.lastFixTime;
    if (t == null) return null;
    return DateTime.now().difference(t).inMilliseconds / 1000.0;
  });

  interp.def('baro', (args) {
    final baro = diag.lastBaro;
    return baro == null ? null : mapToAlist(baro);
  });

  interp.def('elev', (args) {
    final snapshot = diag.trackerSnapshot?.call();
    return snapshot == null ? null : mapToAlist(snapshot);
  });

  interp.def('counters', (args) => mapToAlist(diag.counters()));

  interp.def('log', (args) {
    checkedArity(args, 0, 2, 'log');
    final n = count(args, 20);
    final category = args.length > 1 ? args[1] : null;
    final filter = switch (category) {
      null => null,
      final Sym s => s.name,
      final String s => s,
      _ => throw LispError("log filter must be a symbol, e.g. (log 20 'gps)"),
    };
    final lines = diag.events
        .toList()
        .reversed // newest first
        .where((e) => filter == null || e.category == filter)
        .take(n)
        .map((e) =>
            '${e.time.toIso8601String().substring(11, 19)} ${e.category} '
            '${e.message}');
    return listToLisp(lines);
  });

  interp.def('help', (args) {
    return listToLisp([
      for (final line in const [
        '(stats)            distance, gain, elapsed, points, segments',
        '(gps)              latest RAW fix, pre-filter, with age',
        '(gps-history [n])  last n raw fixes, newest first',
        '(fix-age)          seconds since last raw fix',
        '(baro)             latest barometer sample',
        '(elev)             ElevationTracker internals',
        '(counters)         filter verdict counts',
        "(log [n] ['cat])   last n log lines, e.g. (log 20 'gps)",
        'core: + - * / = < > car cdr cons list length nth assoc',
        '      map filter lambda define let if quote and or not',
      ])
        line,
    ]);
  });
}
