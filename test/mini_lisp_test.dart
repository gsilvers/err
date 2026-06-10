import 'package:err/debug/mini_lisp.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  String run(String src) => printValue(Interpreter().run(src));

  group('reader and printer', () {
    test('atoms', () {
      expect(run('42'), '42');
      expect(run('-3.5'), '-3.500');
      expect(run('"hi"'), '"hi"');
      expect(run('t'), 't');
      expect(run('nil'), 'nil');
    });

    test('quote and lists', () {
      expect(run("'(1 2 3)"), '(1 2 3)');
      expect(run("'(a (b c))"), '(a (b c))');
      expect(run("'()"), 'nil');
    });

    test('dotted pairs read and print', () {
      expect(run("'(acc . 8.2)"), '(acc . 8.200)');
      expect(run("(cons 'a 'b)"), '(a . b)');
    });

    test('comments are skipped', () {
      expect(run('(+ 1 2) ; adds\n'), '3');
    });

    test('reader errors', () {
      expect(() => run('(+ 1 2'), throwsA(isA<LispError>()));
      expect(() => run(')'), throwsA(isA<LispError>()));
      expect(() => run('"open'), throwsA(isA<LispError>()));
    });
  });

  group('evaluation', () {
    test('arithmetic and comparison', () {
      expect(run('(+ 1 2 3)'), '6');
      expect(run('(- 10 4 1)'), '5');
      expect(run('(- 5)'), '-5');
      expect(run('(* 2 3 4)'), '24');
      expect(run('(/ 10 4)'), '2.500');
      expect(run('(< 1 2 3)'), 't');
      expect(run('(> 1 2)'), 'nil');
      expect(run('(= 2 2.0)'), 't');
      expect(run('(max 1 5 3)'), '5');
    });

    test('if, and, or, not', () {
      expect(run('(if (> 2 1) "yes" "no")'), '"yes"');
      expect(run('(if nil 1)'), 'nil');
      expect(run('(and 1 2 3)'), '3');
      expect(run('(and 1 nil 3)'), 'nil');
      expect(run('(or nil 2)'), '2');
      expect(run('(not nil)'), 't');
    });

    test('define and lambda', () {
      expect(run('(define x 5) (+ x 1)'), '6');
      expect(run('(define f (lambda (a b) (+ a b))) (f 2 3)'), '5');
      expect(run('(define (g n) (* n n)) (g 4)'), '16');
    });

    test('let and closures', () {
      expect(run('(let ((a 1) (b 2)) (+ a b))'), '3');
      expect(
        run('(define (adder n) (lambda (x) (+ x n))) ((adder 10) 5)'),
        '15',
      );
    });

    test('recursion', () {
      expect(
        run('(define (fact n) (if (< n 2) 1 (* n (fact (- n 1))))) (fact 10)'),
        '3628800',
      );
    });

    test('list operations', () {
      expect(run("(car '(1 2 3))"), '1');
      expect(run("(cdr '(1 2 3))"), '(2 3)');
      expect(run("(length '(a b c))"), '3');
      expect(run("(nth 1 '(a b c))"), 'b');
      expect(run("(nth 9 '(a b c))"), 'nil');
      expect(run("(reverse '(1 2 3))"), '(3 2 1)');
      expect(run("(append '(1 2) '(3))"), '(1 2 3)');
      expect(run("(map (lambda (x) (* x 2)) '(1 2 3))"), '(2 4 6)');
      expect(run("(filter (lambda (x) (> x 1)) '(1 2 3))"), '(2 3)');
    });

    test('assoc over an alist of dotted pairs', () {
      const alist = "'((lat . 40.6) (acc . 8.2) (alt . 98.4))";
      expect(run('(assoc \'acc $alist)'), '(acc . 8.200)');
      expect(run('(cdr (assoc \'acc $alist))'), '8.200');
      expect(run('(assoc \'missing $alist)'), 'nil');
    });

    test('runtime errors are LispError, not crashes', () {
      expect(() => run('(undefined-fn 1)'), throwsA(isA<LispError>()));
      expect(() => run('(car 5)'), throwsA(isA<LispError>()));
      expect(() => run('((lambda (a) a) 1 2)'), throwsA(isA<LispError>()));
    });

    test('infinite recursion hits the depth limit instead of crashing', () {
      expect(
        () => run('(define (loop) (loop)) (loop)'),
        throwsA(predicate(
            (e) => e is LispError && e.message.contains('recursion'))),
      );
    });
  });

  group('dart interop helpers', () {
    test('mapToAlist converts nested maps, ints, and lists', () {
      final v = mapToAlist({
        'acc': 8.2,
        'n': 3,
        'ok': true,
        'missing': null,
        'nested': {'a': 1},
        'items': [1.0, 2.0],
      });
      expect(
        printValue(v),
        '((acc . 8.200) (n . 3) (ok . t) (missing) (nested (a . 1)) '
        '(items 1 2))',
      );
    });
  });
}
