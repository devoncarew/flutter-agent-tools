import 'package:flutter_toolkit/src/deps/deps_check.dart';
import 'package:test/test.dart';

/// Tests for [newlyAddedPackages] — the pure diff function extracted from
/// [handlePubspecGuard].
///
/// The failure modes we care about:
///  1. Write hook — brand new file or full rewrite: all deps are "new".
///  2. Edit hook — adding a dep to an existing section.
///  3. Edit hook — adding a new section (e.g. dev_dependencies didn't exist).
///  4. Edit hook — changing only a version constraint: not reported as new.
///  5. Edit hook — removing a dep: not reported as new.
///  6. Edge cases: malformed YAML, empty files, null-valued deps (sdk: flutter).
void main() {
  // ---------------------------------------------------------------------------
  // Core diff behaviour

  group('newlyAddedPackages', () {
    test('empty old → all new deps are reported', () {
      const old = '';
      const next = '''
dependencies:
  http: ^1.0.0
  path: ^1.9.0
''';
      expect(
        newlyAddedPackages(old, next),
        unorderedEquals([('http', '^1.0.0'), ('path', '^1.9.0')]),
      );
    });

    test('adding one dep to an existing section', () {
      const old = '''
dependencies:
  path: ^1.9.0
''';
      const next = '''
dependencies:
  path: ^1.9.0
  http: ^1.0.0
''';
      expect(newlyAddedPackages(old, next), [('http', '^1.0.0')]);
    });

    test('adding a dev_dependency', () {
      const old = '''
dependencies:
  path: ^1.9.0
''';
      const next = '''
dependencies:
  path: ^1.9.0
dev_dependencies:
  test: ^1.25.0
''';
      expect(newlyAddedPackages(old, next), [('test', '^1.25.0')]);
    });

    test('adding a new dev_dependencies section that did not exist', () {
      const old = '''
dependencies:
  http: ^1.0.0
''';
      const next = '''
dependencies:
  http: ^1.0.0
dev_dependencies:
  lints: ^6.0.0
  test: ^1.25.0
''';
      expect(
        newlyAddedPackages(old, next),
        unorderedEquals([('lints', '^6.0.0'), ('test', '^1.25.0')]),
      );
    });

    test('changing only a version constraint is not reported', () {
      const old = '''
dependencies:
  http: ^0.13.0
''';
      const next = '''
dependencies:
  http: ^1.0.0
''';
      expect(newlyAddedPackages(old, next), isEmpty);
    });

    test('removing a dep is not reported', () {
      const old = '''
dependencies:
  http: ^1.0.0
  path: ^1.9.0
''';
      const next = '''
dependencies:
  http: ^1.0.0
''';
      expect(newlyAddedPackages(old, next), isEmpty);
    });

    test('no changes → empty result', () {
      const yaml = '''
dependencies:
  http: ^1.0.0
''';
      expect(newlyAddedPackages(yaml, yaml), isEmpty);
    });

    // -------------------------------------------------------------------------
    // Edge cases

    test('null-valued dep (sdk: flutter) is included with empty constraint', () {
      const old = '';
      const next = '''
dependencies:
  flutter:
    sdk: flutter
''';
      // The value is a Map, not a String — parsePubspecDeps coerces to toString.
      // We just want to confirm it doesn't crash and flutter is present.
      final added = newlyAddedPackages(old, next);
      expect(added.map((r) => r.$1), contains('flutter'));
    });

    test('malformed old YAML is treated as empty (fail open)', () {
      const old = 'this: is: not: valid: yaml: :::';
      const next = '''
dependencies:
  http: ^1.0.0
''';
      expect(newlyAddedPackages(old, next), [('http', '^1.0.0')]);
    });

    test('malformed new YAML returns no packages (fail open)', () {
      const old = '''
dependencies:
  http: ^1.0.0
''';
      const next = 'this: is: not: valid: yaml: :::';
      expect(newlyAddedPackages(old, next), isEmpty);
    });

    test('both empty → empty result', () {
      expect(newlyAddedPackages('', ''), isEmpty);
    });

    test('package with no version constraint (bare name)', () {
      const old = '';
      const next = '''
dependencies:
  some_package:
''';
      final added = newlyAddedPackages(old, next);
      expect(added, hasLength(1));
      expect(added.first.$1, 'some_package');
      // Empty constraint → null in the result.
      expect(added.first.$2, isNull);
    });
  });

  // ---------------------------------------------------------------------------
  // parsePubspecDeps (unit tests for the underlying parser)

  group('parsePubspecDeps', () {
    test('returns empty map for empty string', () {
      expect(parsePubspecDeps(''), isEmpty);
    });

    test('parses dependencies section', () {
      const yaml = '''
dependencies:
  http: ^1.0.0
  path: ^1.9.0
''';
      expect(parsePubspecDeps(yaml), {'http': '^1.0.0', 'path': '^1.9.0'});
    });

    test('parses dev_dependencies section', () {
      const yaml = '''
dev_dependencies:
  test: ^1.25.0
''';
      expect(parsePubspecDeps(yaml), {'test': '^1.25.0'});
    });

    test('merges both sections', () {
      const yaml = '''
dependencies:
  http: ^1.0.0
dev_dependencies:
  test: ^1.25.0
''';
      expect(parsePubspecDeps(yaml), {'http': '^1.0.0', 'test': '^1.25.0'});
    });

    test('returns empty map for malformed YAML', () {
      expect(parsePubspecDeps('not: valid: yaml:::'), isEmpty);
    });
  });
}
