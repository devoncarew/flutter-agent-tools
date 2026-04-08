import 'package:flutter_toolkit/src/shorthand/stub_emitter.dart';
import 'package:test/test.dart';

import 'test_utils.dart';

/// Golden-style tests for [emitLibraryStub].
///
/// Each test supplies a Dart source string and asserts that the emitted stub
/// matches the expected output exactly (modulo leading/trailing whitespace on
/// the whole string). This makes regressions easy to spot: a diff between
/// expected and actual is a diff in the stub format.
///
/// Coverage plan:
///   - typedef (function type alias)
///   - enum (values, no bodies)
///   - class: plain, abstract, final, interface, abstract+interface, sealed
///   - class: supertype / with / implements
///   - class: type parameters with bounds
///   - class: constructors (unnamed, named, const, factory; implicit omitted)
///   - class: fields (direct, static, const, final)
///   - class: fields induced by getters omitted
///   - class: methods (instance, static, abstract)
///   - class: explicit getters / setters
///   - class: mixin contribution inlined with attribution
///   - mixin: on constraint, implements
///   - extension: named and unnamed, methods and getters
///   - top-level functions and variables
///   - doc comments preserved
///   - private members omitted (class and top-level)
void main() {
  // -------------------------------------------------------------------------
  // typedef

  group('typedef', () {
    test('function type alias', () async {
      final lib = await libraryElementFromSource('''
typedef StringMapper = String Function(String);
''');
      expect(
        emitLibraryStub(lib).trim(),
        equals('''
typedef StringMapper = String Function(String);'''),
      );
    });

    test('generic typedef', () async {
      final lib = await libraryElementFromSource('''
typedef Predicate<T> = bool Function(T);
''');
      expect(
        emitLibraryStub(lib).trim(),
        equals('''
typedef Predicate<T> = bool Function(T);'''),
      );
    });
  });

  // -------------------------------------------------------------------------
  // enum

  group('enum', () {
    test('simple enum', () async {
      final lib = await libraryElementFromSource('''
enum Color { red, green, blue }
''');
      expect(
        emitLibraryStub(lib).trim(),
        equals('''
enum Color {
  red, green, blue,
}'''),
      );
    });
  });

  // -------------------------------------------------------------------------
  // plain class

  group('class — structure', () {
    test('abstract class', () async {
      final lib = await libraryElementFromSource('''
abstract class Shape {
  double area();
}
''');
      final stub = emitLibraryStub(lib).trim();
      expect(stub, contains('abstract class Shape {'));
      expect(stub, contains('double area();'));
    });

    test('final class', () async {
      final lib = await libraryElementFromSource('''
final class Point {}
''');
      expect(
        emitLibraryStub(lib).trim(),
        equals('''
final class Point {
}'''),
      );
    });

    test('interface class', () async {
      final lib = await libraryElementFromSource('''
interface class Printable {}
''');
      expect(
        emitLibraryStub(lib).trim(),
        contains('interface class Printable'),
      );
    });

    test('abstract interface class', () async {
      final lib = await libraryElementFromSource('''
abstract interface class Serializable {}
''');
      expect(
        emitLibraryStub(lib).trim(),
        contains('abstract interface class Serializable'),
      );
    });

    test('sealed class', () async {
      final lib = await libraryElementFromSource('''
sealed class Result {}
''');
      expect(emitLibraryStub(lib).trim(), contains('sealed class Result'));
    });
  });

  // -------------------------------------------------------------------------
  // class hierarchy

  group('class — hierarchy', () {
    test('extends', () async {
      final lib = await libraryElementFromSource('''
class Animal {}
class Dog extends Animal {}
''');
      final stub = emitLibraryStub(lib).trim();
      expect(stub, contains('class Dog extends Animal {'));
    });

    test('with mixin', () async {
      final lib = await libraryElementFromSource('''
mixin Flyable {}
class Bird with Flyable {}
''');
      final stub = emitLibraryStub(lib).trim();
      expect(stub, contains('class Bird with Flyable {'));
    });

    test('implements', () async {
      final lib = await libraryElementFromSource('''
abstract class Runnable { void run(); }
class Robot implements Runnable {
  void run() {}
}
''');
      final stub = emitLibraryStub(lib).trim();
      expect(stub, contains('class Robot implements Runnable {'));
    });

    test('type parameters with bound', () async {
      final lib = await libraryElementFromSource('''
class Box<T extends Comparable<T>> {
  final T value;
  Box(this.value);
}
''');
      final stub = emitLibraryStub(lib).trim();
      expect(stub, contains('class Box<T extends Comparable<T>> {'));
    });
  });

  // -------------------------------------------------------------------------
  // constructors

  group('class — constructors', () {
    test('unnamed constructor (explicit)', () async {
      final lib = await libraryElementFromSource('''
class Foo {
  Foo(int x);
}
''');
      expect(
        emitLibraryStub(lib).trim(),
        equals('''
class Foo {
  Foo(int x);
}'''),
      );
    });

    test('implicit default constructor is omitted', () async {
      final lib = await libraryElementFromSource('''
class Empty {}
''');
      final stub = emitLibraryStub(lib).trim();
      // Only the class header and closing brace — no constructor line.
      expect(stub, equals('class Empty {\n}'));
    });

    test('named constructor', () async {
      final lib = await libraryElementFromSource('''
class Point {
  Point.origin();
}
''');
      expect(
        emitLibraryStub(lib).trim(),
        equals('''
class Point {
  Point.origin();
}'''),
      );
    });

    test('const constructor', () async {
      final lib = await libraryElementFromSource('''
class Imm {
  const Imm(int x);
}
''');
      expect(
        emitLibraryStub(lib).trim(),
        equals('''
class Imm {
  const Imm(int x);
}'''),
      );
    });

    test('factory constructor', () async {
      final lib = await libraryElementFromSource('''
class Singleton {
  factory Singleton.instance() => Singleton._();
  Singleton._();
}
''');
      final stub = emitLibraryStub(lib).trim();
      expect(stub, contains('factory Singleton.instance();'));
      // Private constructor omitted.
      expect(stub, isNot(contains('Singleton._()')));
    });
  });

  // -------------------------------------------------------------------------
  // fields

  group('class — fields', () {
    test('instance final field', () async {
      final lib = await libraryElementFromSource('''
class Foo {
  final int x;
  Foo(this.x);
}
''');
      expect(
        emitLibraryStub(lib).trim(),
        equals('''
class Foo {
  Foo(int x);
  final int x;
}'''),
      );
    });

    test('static const field', () async {
      final lib = await libraryElementFromSource('''
class Config {
  static const int maxRetries = 3;
}
''');
      expect(
        emitLibraryStub(lib).trim(),
        equals('''
class Config {
  static const int maxRetries;
}'''),
      );
    });

    test('field-induced getter is omitted', () async {
      // `final int x` induces a synthetic getter — it should NOT appear as an
      // explicit getter in the stub.
      final lib = await libraryElementFromSource('''
class Foo {
  final int x;
  Foo(this.x);
}
''');
      final stub = emitLibraryStub(lib).trim();
      // Should appear as a field, not as `int get x;`.
      expect(stub, isNot(contains('int get x;')));
      expect(stub, contains('final int x;'));
    });
  });

  // -------------------------------------------------------------------------
  // methods

  group('class — methods', () {
    test('instance method', () async {
      final lib = await libraryElementFromSource('''
class Foo {
  String greet(String name) => 'hi';
}
''');
      expect(
        emitLibraryStub(lib).trim(),
        equals('''
class Foo {
  String greet(String name);
}'''),
      );
    });

    test('static method', () async {
      final lib = await libraryElementFromSource('''
class MathUtils {
  static int square(int n) => n * n;
}
''');
      expect(
        emitLibraryStub(lib).trim(),
        equals('''
class MathUtils {
  static int square(int n);
}'''),
      );
    });

    test('generic method', () async {
      final lib = await libraryElementFromSource('''
class Converter {
  T convert<T>(Object o) => o as T;
}
''');
      expect(
        emitLibraryStub(lib).trim(),
        equals('''
class Converter {
  T convert<T>(Object o);
}'''),
      );
    });

    test('named parameters', () async {
      final lib = await libraryElementFromSource('''
class Foo {
  void configure({required String host, int port = 80}) {}
}
''');
      expect(
        emitLibraryStub(lib).trim(),
        equals('''
class Foo {
  void configure({required String host, int port});
}'''),
      );
    });

    test('optional positional parameters', () async {
      final lib = await libraryElementFromSource('''
class Foo {
  void log(String msg, [String? tag]) {}
}
''');
      expect(
        emitLibraryStub(lib).trim(),
        equals('''
class Foo {
  void log(String msg, [String? tag]);
}'''),
      );
    });

    test('private method omitted', () async {
      final lib = await libraryElementFromSource('''
class Foo {
  void pub() {}
  void _priv() {}
}
''');
      final stub = emitLibraryStub(lib).trim();
      expect(stub, contains('void pub();'));
      expect(stub, isNot(contains('_priv')));
    });
  });

  // -------------------------------------------------------------------------
  // explicit getters / setters

  group('class — explicit getters and setters', () {
    test('getter', () async {
      final lib = await libraryElementFromSource('''
class Circle {
  final double radius;
  Circle(this.radius);
  double get area => 3.14 * radius * radius;
}
''');
      expect(
        emitLibraryStub(lib).trim(),
        equals('''
class Circle {
  Circle(double radius);
  final double radius;
  double get area;
}'''),
      );
    });

    test('setter', () async {
      final lib = await libraryElementFromSource('''
class Counter {
  int _count = 0;
  set count(int value) { _count = value; }
}
''');
      expect(
        emitLibraryStub(lib).trim(),
        equals('''
class Counter {
  set count(int value);
}'''),
      );
    });
  });

  // -------------------------------------------------------------------------
  // mixin contribution

  group('mixin contribution', () {
    test('mixin method inlined with attribution', () async {
      final lib = await libraryElementFromSource('''
mixin Logger {
  void log(String msg) {}
}
class Service with Logger {}
''');
      final stub = emitLibraryStub(lib).trim();
      // Service inherits log from Logger — should appear attributed.
      expect(stub, contains('// from Logger'));
      expect(stub, contains('void log(String msg);'));
    });

    test('overridden mixin method not duplicated', () async {
      final lib = await libraryElementFromSource('''
mixin Logger {
  void log(String msg) {}
}
class Service with Logger {
  @override
  void log(String msg) {}
}
''');
      final stub = emitLibraryStub(lib).trim();
      // The stub emits Logger before Service (alphabetical order).
      // log should appear once in each — but the Service block must NOT
      // have the // from Logger attribution (it's a direct override).
      final serviceStart = stub.indexOf('class Service');
      // Find the closing brace of the Service block only.
      final serviceEnd = stub.indexOf('\n}', serviceStart) + 2;
      final serviceBlock = stub.substring(serviceStart, serviceEnd);
      expect('// from Logger'.allMatches(serviceBlock).length, 0);
      expect('void log(String msg);'.allMatches(serviceBlock).length, 1);
    });
  });

  // -------------------------------------------------------------------------
  // mixin declaration

  group('mixin declaration', () {
    test('mixin with on constraint', () async {
      final lib = await libraryElementFromSource('''
abstract class Animal { void breathe(); }
mixin Walker on Animal {
  void walk() {}
}
''');
      expect(
        emitLibraryStub(lib).trim(),
        equals('''
abstract class Animal {
  abstract void breathe();
}

mixin Walker on Animal {
  void walk();
}'''),
      );
    });
  });

  // -------------------------------------------------------------------------
  // extension

  group('extension', () {
    test('named extension with method', () async {
      final lib = await libraryElementFromSource('''
extension StringX on String {
  String shout() => toUpperCase();
}
''');
      expect(
        emitLibraryStub(lib).trim(),
        equals('''
extension StringX on String {
  String shout();
}'''),
      );
    });

    test('extension getter', () async {
      final lib = await libraryElementFromSource('''
extension IntX on int {
  bool get isEven => this % 2 == 0;
}
''');
      expect(
        emitLibraryStub(lib).trim(),
        equals('''
extension IntX on int {
  bool get isEven;
}'''),
      );
    });
  });

  // -------------------------------------------------------------------------
  // top-level functions and variables

  group('top-level', () {
    test('function with positional params', () async {
      final lib = await libraryElementFromSource('''
int add(int a, int b) => a + b;
''');
      expect(emitLibraryStub(lib).trim(), equals('int add(int a, int b);'));
    });

    test('const variable', () async {
      final lib = await libraryElementFromSource('''
const int maxItems = 100;
''');
      expect(emitLibraryStub(lib).trim(), equals('const int maxItems;'));
    });

    test('final variable', () async {
      final lib = await libraryElementFromSource('''
final String appName = 'test';
''');
      expect(emitLibraryStub(lib).trim(), equals('final String appName;'));
    });

    test('private top-level omitted', () async {
      final lib = await libraryElementFromSource('''
int pub() => 1;
int _priv() => 2;
''');
      final stub = emitLibraryStub(lib).trim();
      expect(stub, contains('int pub();'));
      expect(stub, isNot(contains('_priv')));
    });
  });

  // -------------------------------------------------------------------------
  // doc comments

  group('doc comments', () {
    test('class doc comment preserved', () async {
      final lib = await libraryElementFromSource('''
/// A very useful class.
class Useful {}
''');
      final stub = emitLibraryStub(lib).trim();
      expect(stub, contains('/// A very useful class.'));
    });

    test('method doc comment preserved', () async {
      final lib = await libraryElementFromSource('''
class Foo {
  /// Does the thing.
  void doThing() {}
}
''');
      final stub = emitLibraryStub(lib).trim();
      expect(stub, contains('/// Does the thing.'));
      expect(stub, contains('void doThing();'));
    });
  });

  // -------------------------------------------------------------------------
  // emitElementStub

  group('emitElementStub', () {
    test('class', () async {
      final lib = await libraryElementFromSource('''
class Counter {
  int count = 0;
  void increment() {}
}
''');
      expect(
        emitElementStub(lib, 'Counter')?.trim(),
        equals('''
class Counter {
  int count;
  void increment();
}'''),
      );
    });

    test('abstract class', () async {
      final lib = await libraryElementFromSource('''
abstract class Shape {
  double area();
}
''');
      expect(
        emitElementStub(lib, 'Shape')?.trim(),
        equals('''
abstract class Shape {
  abstract double area();
}'''),
      );
    });

    test('mixin', () async {
      final lib = await libraryElementFromSource('''
mixin Logger {
  void log(String msg) {}
}
''');
      expect(
        emitElementStub(lib, 'Logger')?.trim(),
        equals('''
mixin Logger {
  void log(String msg);
}'''),
      );
    });

    test('extension', () async {
      final lib = await libraryElementFromSource('''
extension StringX on String {
  String shout() => toUpperCase();
}
''');
      expect(
        emitElementStub(lib, 'StringX')?.trim(),
        equals('''
extension StringX on String {
  String shout();
}'''),
      );
    });

    test('enum', () async {
      final lib = await libraryElementFromSource('''
enum Direction { north, south, east, west }
''');
      expect(
        emitElementStub(lib, 'Direction')?.trim(),
        equals('''
enum Direction {
  north, south, east, west,
}'''),
      );
    });

    test('not found returns null', () async {
      final lib = await libraryElementFromSource('class Foo {}');
      expect(emitElementStub(lib, 'Bar'), isNull);
    });

    test('top-level function returns null', () async {
      final lib = await libraryElementFromSource('int add(int a, int b) => 0;');
      expect(emitElementStub(lib, 'add'), isNull);
    });
  });
}
