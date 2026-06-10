/// A minimal lisp interpreter for the read-only debug REPL.
///
/// Pure Dart, no dependencies. Small on purpose: numbers (doubles),
/// strings, interned symbols, cons cells (so assoc lists and dotted pairs
/// print naturally), and the special forms `quote` `if` `define` `lambda`
/// `let` `and` `or` `progn`. Everything else is a builtin function.
///
/// `nil` is the empty list, is `null` in Dart, and is false; `t` is true.
library;

/// An interned symbol — two symbols with the same name are identical.
class Sym {
  Sym._(this.name);

  final String name;

  static final Map<String, Sym> _interned = {};

  factory Sym(String name) => _interned.putIfAbsent(name, () => Sym._(name));

  @override
  String toString() => name;
}

/// A cons cell. Proper lists are chains of [Cons] ending in `null` (nil);
/// assoc-list entries are dotted pairs like `(acc . 8.2)`.
class Cons {
  Cons(this.car, this.cdr);

  final Object? car;
  final Object? cdr;
}

class LispError implements Exception {
  LispError(this.message);

  final String message;

  @override
  String toString() => message;
}

typedef Builtin = Object? Function(List<Object?> args);

class Lambda {
  Lambda(this.params, this.body, this.env);

  final List<Sym> params;
  final List<Object?> body;
  final Env env;
}

class Env {
  Env([this.parent]);

  final Env? parent;
  final Map<Sym, Object?> vars = {};

  Object? lookup(Sym s) {
    for (Env? e = this; e != null; e = e.parent) {
      if (e.vars.containsKey(s)) return e.vars[s];
    }
    throw LispError('undefined symbol: ${s.name}');
  }

  void define(Sym s, Object? v) => vars[s] = v;
}

// ─── Reader ──────────────────────────────────────────────────────────────────

class _Tok {
  static const lparen = _Tok._('(');
  static const rparen = _Tok._(')');
  static const quote = _Tok._("'");

  const _Tok._(this.repr);
  final String repr;
}

List<Object?> _tokenize(String src) {
  final tokens = <Object?>[];
  var i = 0;
  while (i < src.length) {
    final c = src[i];
    if (c == ';') {
      while (i < src.length && src[i] != '\n') {
        i++;
      }
    } else if (c == ' ' || c == '\t' || c == '\n' || c == '\r') {
      i++;
    } else if (c == '(') {
      tokens.add(_Tok.lparen);
      i++;
    } else if (c == ')') {
      tokens.add(_Tok.rparen);
      i++;
    } else if (c == "'") {
      tokens.add(_Tok.quote);
      i++;
    } else if (c == '"') {
      final buf = StringBuffer();
      i++;
      while (i < src.length && src[i] != '"') {
        if (src[i] == r'\' && i + 1 < src.length) i++;
        buf.write(src[i]);
        i++;
      }
      if (i >= src.length) throw LispError('unterminated string');
      i++; // closing quote
      tokens.add(buf.toString());
    } else {
      final start = i;
      while (i < src.length && !' \t\n\r()\';"'.contains(src[i])) {
        i++;
      }
      tokens.add(_atom(src.substring(start, i)));
    }
  }
  return tokens;
}

Object? _atom(String text) {
  final n = double.tryParse(text);
  if (n != null) return n;
  if (text == 't') return true;
  if (text == 'nil') return null;
  return Sym(text);
}

class _Reader {
  _Reader(this._tokens);

  final List<Object?> _tokens;
  int _pos = 0;

  bool get done => _pos >= _tokens.length;

  Object? read() {
    if (done) throw LispError('unexpected end of input');
    final tok = _tokens[_pos++];
    if (tok == _Tok.lparen) return _readList();
    if (tok == _Tok.rparen) throw LispError('unexpected )');
    if (tok == _Tok.quote) {
      return Cons(Sym('quote'), Cons(read(), null));
    }
    return tok;
  }

  Object? _readList() {
    final items = <Object?>[];
    Object? tail;
    while (true) {
      if (done) throw LispError('missing )');
      if (_tokens[_pos] == _Tok.rparen) {
        _pos++;
        break;
      }
      if (_tokens[_pos] == Sym('.') && items.isNotEmpty) {
        _pos++;
        tail = read();
        if (done || _tokens[_pos] != _Tok.rparen) {
          throw LispError('malformed dotted pair');
        }
        _pos++;
        break;
      }
      items.add(read());
    }
    Object? list = tail;
    for (final item in items.reversed) {
      list = Cons(item, list);
    }
    return list;
  }
}

/// Parses all top-level forms in [src].
List<Object?> parse(String src) {
  final reader = _Reader(_tokenize(src));
  final forms = <Object?>[];
  while (!reader.done) {
    forms.add(reader.read());
  }
  return forms;
}

// ─── Printer ─────────────────────────────────────────────────────────────────

String printValue(Object? v) {
  if (v == null || v == false) return 'nil';
  if (v == true) return 't';
  if (v is double) {
    if (v == v.roundToDouble() && v.abs() < 1e15) return v.toInt().toString();
    return v.toStringAsFixed(3);
  }
  if (v is String) return '"$v"';
  if (v is Sym) return v.name;
  if (v is Cons) {
    final buf = StringBuffer('(');
    Object? cur = v;
    var first = true;
    while (cur is Cons) {
      if (!first) buf.write(' ');
      buf.write(printValue(cur.car));
      first = false;
      cur = cur.cdr;
    }
    if (cur != null) buf.write(' . ${printValue(cur)}');
    buf.write(')');
    return buf.toString();
  }
  return '#<fn>';
}

// ─── Conversions ─────────────────────────────────────────────────────────────

/// Dart list → proper lisp list.
Object? listToLisp(Iterable<Object?> items) {
  Object? list;
  for (final item in items.toList().reversed) {
    list = Cons(item, list);
  }
  return list;
}

/// Proper lisp list → Dart list. Throws on improper lists.
List<Object?> lispToList(Object? v) {
  final out = <Object?>[];
  while (v != null) {
    if (v is! Cons) throw LispError('expected a proper list');
    out.add(v.car);
    v = v.cdr;
  }
  return out;
}

/// Dart map → assoc list of dotted pairs with symbol keys.
/// Ints become lisp numbers (doubles); nested maps/lists recurse.
Object? mapToAlist(Map<String, Object?> m) =>
    listToLisp(m.entries.map((e) => Cons(Sym(e.key), _toLisp(e.value))));

Object? _toLisp(Object? v) {
  if (v is int) return v.toDouble();
  if (v is Map<String, Object?>) return mapToAlist(v);
  if (v is Iterable<Object?>) return listToLisp(v.map(_toLisp));
  return v; // double, String, bool, null pass through
}

// ─── Interpreter ─────────────────────────────────────────────────────────────

class Interpreter {
  Interpreter() {
    _installCore();
  }

  final Env globals = Env();
  int _steps = 0;
  int _depth = 0;

  /// Guards the UI thread against `(define (loop) (loop))`: the step limit
  /// catches expensive loops, the depth limit catches deep recursion before
  /// it overflows the Dart call stack.
  static const _maxSteps = 200000;
  static const _maxDepth = 500;

  /// Evaluates every form in [src], returning the last result.
  Object? run(String src) {
    final forms = parse(src);
    if (forms.isEmpty) return null;
    _steps = 0;
    _depth = 0;
    Object? result;
    for (final f in forms) {
      result = eval(f, globals);
    }
    return result;
  }

  Object? eval(Object? x, Env env) {
    if (++_steps > _maxSteps) {
      throw LispError('step limit exceeded — expression too expensive');
    }
    if (x is Sym) return env.lookup(x);
    if (x is! Cons) return x; // numbers, strings, booleans, nil
    final args = lispToList(x.cdr);
    final op = x.car;
    if (op is Sym) {
      switch (op.name) {
        case 'quote':
          return args[0];
        case 'if':
          if (args.length < 2 || args.length > 3) {
            throw LispError('if takes 2 or 3 forms');
          }
          if (_truthy(eval(args[0], env))) return eval(args[1], env);
          return args.length == 3 ? eval(args[2], env) : null;
        case 'define':
          return _define(args, env);
        case 'lambda':
          return Lambda(_paramList(args.isEmpty ? null : args[0]),
              args.skip(1).toList(), env);
        case 'let':
          final local = Env(env);
          for (final binding in lispToList(args.isEmpty ? null : args[0])) {
            final pair = lispToList(binding);
            if (pair.length != 2 || pair[0] is! Sym) {
              throw LispError('let bindings are ((name value) ...)');
            }
            local.define(pair[0] as Sym, eval(pair[1], env));
          }
          return _evalBody(args.skip(1).toList(), local);
        case 'and':
          Object? v = true;
          for (final a in args) {
            v = eval(a, env);
            if (!_truthy(v)) return v;
          }
          return v;
        case 'or':
          for (final a in args) {
            final v = eval(a, env);
            if (_truthy(v)) return v;
          }
          return null;
        case 'progn':
          return _evalBody(args, env);
      }
    }
    final fn = eval(op, env);
    return apply(fn, [for (final a in args) eval(a, env)]);
  }

  Object? apply(Object? fn, List<Object?> args) {
    if (fn is Builtin) return fn(args);
    if (fn is Lambda) {
      if (args.length != fn.params.length) {
        throw LispError(
            'expected ${fn.params.length} args, got ${args.length}');
      }
      if (++_depth > _maxDepth) {
        _depth--;
        throw LispError('recursion too deep (max $_maxDepth frames)');
      }
      try {
        final local = Env(fn.env);
        for (var i = 0; i < args.length; i++) {
          local.define(fn.params[i], args[i]);
        }
        return _evalBody(fn.body, local);
      } finally {
        _depth--;
      }
    }
    throw LispError('not a function: ${printValue(fn)}');
  }

  Object? _evalBody(List<Object?> body, Env env) {
    Object? result;
    for (final form in body) {
      result = eval(form, env);
    }
    return result;
  }

  Object? _define(List<Object?> args, Env env) {
    if (args.isEmpty) throw LispError('define needs a name');
    final target = args[0];
    if (target is Sym) {
      final value = args.length > 1 ? eval(args[1], env) : null;
      env.define(target, value);
      return target;
    }
    if (target is Cons && target.car is Sym) {
      // (define (f a b) body...)
      final name = target.car as Sym;
      env.define(
          name, Lambda(_paramList(target.cdr), args.skip(1).toList(), env));
      return name;
    }
    throw LispError('malformed define');
  }

  List<Sym> _paramList(Object? params) => [
        for (final p in lispToList(params))
          p is Sym ? p : (throw LispError('parameters must be symbols')),
      ];

  static bool _truthy(Object? v) => v != null && v != false;

  // ── Core builtins ─────────────────────────────────────────────────────

  void def(String name, Builtin fn) => globals.define(Sym(name), fn);

  static double _num(Object? v) {
    if (v is double) return v;
    throw LispError('expected a number, got ${printValue(v)}');
  }

  void _installCore() {
    def('+', (a) => a.map(_num).fold<double>(0.0, (x, y) => x + y));
    def('*', (a) => a.map(_num).fold<double>(1.0, (x, y) => x * y));
    def('-', (a) {
      if (a.isEmpty) throw LispError('- needs at least 1 arg');
      if (a.length == 1) return -_num(a[0]);
      return a.skip(1).map(_num).fold<double>(_num(a[0]), (x, y) => x - y);
    });
    def('/', (a) {
      if (a.length < 2) throw LispError('/ needs at least 2 args');
      return a.skip(1).map(_num).fold<double>(_num(a[0]), (x, y) => x / y);
    });
    def('mod', (a) => _num(a[0]) % _num(a[1]));
    def('abs', (a) => _num(a[0]).abs());
    def('min', (a) => a.map(_num).reduce((x, y) => x < y ? x : y));
    def('max', (a) => a.map(_num).reduce((x, y) => x > y ? x : y));
    def('round', (a) => _num(a[0]).roundToDouble());

    bool chain(List<Object?> a, bool Function(double, double) cmp) {
      for (var i = 0; i + 1 < a.length; i++) {
        if (!cmp(_num(a[i]), _num(a[i + 1]))) return false;
      }
      return true;
    }

    def('=', (a) => chain(a, (x, y) => x == y));
    def('<', (a) => chain(a, (x, y) => x < y));
    def('>', (a) => chain(a, (x, y) => x > y));
    def('<=', (a) => chain(a, (x, y) => x <= y));
    def('>=', (a) => chain(a, (x, y) => x >= y));
    def('not', (a) => !_truthy(a[0]));
    def('equal?', (a) => _equal(a[0], a[1]));

    def('cons', (a) => Cons(a[0], a[1]));
    def('car', (a) => a[0] is Cons
        ? (a[0] as Cons).car
        : (throw LispError('car: not a pair: ${printValue(a[0])}')));
    def('cdr', (a) => a[0] is Cons
        ? (a[0] as Cons).cdr
        : (throw LispError('cdr: not a pair: ${printValue(a[0])}')));
    def('list', listToLisp);
    def('length', (a) => lispToList(a[0]).length.toDouble());
    def('nth', (a) {
      final items = lispToList(a[1]);
      final i = _num(a[0]).toInt();
      if (i < 0 || i >= items.length) return null;
      return items[i];
    });
    def('reverse', (a) => listToLisp(lispToList(a[0]).reversed));
    def('append', (a) =>
        listToLisp([for (final list in a) ...lispToList(list)]));
    def('null?', (a) => a[0] == null);
    def('pair?', (a) => a[0] is Cons);
    def('number?', (a) => a[0] is double);
    def('string?', (a) => a[0] is String);
    def('symbol?', (a) => a[0] is Sym);

    def('assoc', (a) {
      for (final entry in lispToList(a[1])) {
        if (entry is Cons && _equal(entry.car, a[0])) return entry;
      }
      return null;
    });
    def('map', (a) =>
        listToLisp([for (final v in lispToList(a[1])) apply(a[0], [v])]));
    def('filter', (a) => listToLisp([
          for (final v in lispToList(a[1]))
            if (_truthy(apply(a[0], [v]))) v,
        ]));
  }

  static bool _equal(Object? a, Object? b) {
    if (a is Cons && b is Cons) {
      return _equal(a.car, b.car) && _equal(a.cdr, b.cdr);
    }
    return a == b;
  }
}
