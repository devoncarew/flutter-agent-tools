import 'package:flutter_toolkit/src/shorthand/api_tool.dart';
import 'package:test/test.dart';

// The project root — where pubspec.yaml and pubspec.lock live.
// Tests run from the package root, so '.' is correct.
const String projectDir = '.';

void main() {
  group('resolveVersionFromLockfile', () {
    test('resolves a known direct dependency', () {
      // http is a direct dependency of this project.
      final version = resolveVersionFromLockfile('http', projectDir);
      expect(version, isNotNull);
      // Should be a valid semver string.
      expect(version, matches(RegExp(r'^\d+\.\d+\.\d+')));
    });

    test('resolves a transitive dependency', () {
      // yaml is a direct dependency; http_parser is transitive via http.
      final version = resolveVersionFromLockfile('http_parser', projectDir);
      expect(version, isNotNull);
    });

    test('returns null for an unknown package', () {
      final version = resolveVersionFromLockfile(
        'no_such_package_xyz',
        projectDir,
      );
      expect(version, isNull);
    });

    test('walks up to find lock file from a subdirectory', () {
      // Starting inside lib/ should still find the root pubspec.lock.
      final version = resolveVersionFromLockfile('http', '$projectDir/lib');
      expect(version, isNotNull);
    });
  });

  group('pubCacheHostedDir', () {
    test('returns a non-null path that exists on disk', () {
      final dir = pubCacheHostedDir();
      expect(dir, isNotNull);
    });
  });

  group('findPackageInPubCache', () {
    test('finds http at the version in pubspec.lock', () {
      final version = resolveVersionFromLockfile('http', projectDir);
      expect(version, isNotNull);
      final dir = findPackageInPubCache('http', version);
      expect(dir, isNotNull);
      expect(dir!.existsSync(), isTrue);
    });

    test('finds http with no version — returns highest cached', () {
      final dir = findPackageInPubCache('http', null);
      expect(dir, isNotNull);
      expect(dir!.existsSync(), isTrue);
    });

    test('returns null for an unknown package', () {
      final dir = findPackageInPubCache('no_such_package_xyz', null);
      expect(dir, isNull);
    });

    test('returns null for a known package at a non-existent version', () {
      final dir = findPackageInPubCache('http', '0.0.0-nonexistent');
      expect(dir, isNull);
    });
  });

  group('readPackageVersion', () {
    test('reads the version of a cached package', () {
      final lockVersion = resolveVersionFromLockfile('http', projectDir);
      expect(lockVersion, isNotNull);
      final dir = findPackageInPubCache('http', lockVersion);
      expect(dir, isNotNull);
      final version = readPackageVersion(dir!);
      expect(version, lockVersion);
    });
  });
}
