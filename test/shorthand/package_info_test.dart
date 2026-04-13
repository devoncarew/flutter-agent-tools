import 'dart:io';

import 'package:flutter_slipstream/src/shorthand/context.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

// The project root — where pubspec.yaml and .dart_tool/ live.
// Tests run from the package root, so '.' is correct.
final String projectDir = Directory.current.absolute.path;

void main() {
  group('resolvePackageFromConfig', () {
    test('resolves a hosted dependency', () {
      final dir = resolvePackageFromConfig(projectDir, 'http');
      expect(dir, isNotNull);
      expect(dir!.existsSync(), isTrue);
    });

    test('resolves a transitive dependency', () {
      final dir = resolvePackageFromConfig(projectDir, 'http_parser');
      expect(dir, isNotNull);
      expect(dir!.existsSync(), isTrue);
    });

    test('returns null for an unknown package', () {
      final dir = resolvePackageFromConfig(projectDir, 'no_such_package_xyz');
      expect(dir, isNull);
    });

    test('walks up to find config from a subdirectory', () {
      final dir = resolvePackageFromConfig(p.join(projectDir, 'lib'), 'http');
      expect(dir, isNotNull);
      expect(dir!.existsSync(), isTrue);
    });
  });

  group('readPackageVersion', () {
    test('reads the version of a resolved package', () {
      final dir = resolvePackageFromConfig(projectDir, 'http');
      expect(dir, isNotNull);
      final version = readPackageVersion(dir!);
      expect(version, isNotNull);
      expect(version, matches(RegExp(r'^\d+\.\d+\.\d+')));
    });
  });
}
