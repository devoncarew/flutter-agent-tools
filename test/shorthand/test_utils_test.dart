import 'package:flutter_slipstream/src/shorthand/stub_emitter.dart';
import 'package:test/test.dart';

import 'test_utils.dart';

void main() {
  group('libraryElementFromSource', () {
    test('resolves a simple class', () async {
      final library = await libraryElementFromSource('''
class Foo {
  final int x;
  Foo(this.x);
  String greet() => 'hello';
}
''');
      expect(library.exportNamespace.definedNames2.keys, contains('Foo'));
    });

    test('resolves a top-level function', () async {
      final library = await libraryElementFromSource('''
int add(int a, int b) => a + b;
''');
      expect(library.exportNamespace.definedNames2.keys, contains('add'));
    });

    test('emitLibraryStub works on in-memory source', () async {
      final library = await libraryElementFromSource('''
/// A simple adder.
class Adder {
  /// Adds two numbers.
  int add(int a, int b) => a + b;
}

/// Returns true if [n] is even.
bool isEven(int n) => n % 2 == 0;
''');
      final stub = emitLibraryStub(library);
      expect(stub, contains('class Adder {'));
      expect(stub, contains('int add(int a, int b);'));
      expect(stub, contains('bool isEven(int n);'));
      // No method bodies.
      expect(stub, isNot(contains('=> a + b')));
    });
  });
}
