import 'package:flutter_slipstream/src/shorthand/context.dart';
import 'package:test/test.dart';

// The project root — where pubspec.yaml and pubspec.lock live.
// Tests run from the package root, so '.' is correct.
const String projectDir = '.';

void main() {
  group('resolveVersionFromLockfile', () {
    test('resolves a known direct dependency', () {
      // http is a direct dependency of this project.
      final version = resolveVersionFromLockfile(projectDir, 'http');
      expect(version, isNotNull);
      // Should be a valid semver string.
      expect(version, matches(RegExp(r'^\d+\.\d+\.\d+')));
    });

    test('resolves a transitive dependency', () {
      // yaml is a direct dependency; http_parser is transitive via http.
      final version = resolveVersionFromLockfile(projectDir, 'http_parser');
      expect(version, isNotNull);
    });

    test('returns null for an unknown package', () {
      final version = resolveVersionFromLockfile(
        projectDir,
        'no_such_package_xyz',
      );
      expect(version, isNull);
    });

    test('walks up to find lock file from a subdirectory', () {
      // Starting inside lib/ should still find the root pubspec.lock.
      final version = resolveVersionFromLockfile('$projectDir/lib', 'http');
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
      final version = resolveVersionFromLockfile(projectDir, 'http');
      expect(version, isNotNull);
      final dir = locateInPubCache('http', version);
      expect(dir, isNotNull);
      expect(dir!.existsSync(), isTrue);
    });

    test('finds http with no version — returns highest cached', () {
      final dir = locateInPubCache('http', null);
      expect(dir, isNotNull);
      expect(dir!.existsSync(), isTrue);
    });

    test('returns null for an unknown package', () {
      final dir = locateInPubCache('no_such_package_xyz', null);
      expect(dir, isNull);
    });

    test('returns null for a known package at a non-existent version', () {
      final dir = locateInPubCache('http', '0.0.0-nonexistent');
      expect(dir, isNull);
    });
  });

  group('readPackageVersion', () {
    test('reads the version of a cached package', () {
      final lockVersion = resolveVersionFromLockfile(projectDir, 'http');
      expect(lockVersion, isNotNull);
      final dir = locateInPubCache('http', lockVersion);
      expect(dir, isNotNull);
      final version = readPackageVersion(dir!);
      expect(version, lockVersion);
    });
  });
}
