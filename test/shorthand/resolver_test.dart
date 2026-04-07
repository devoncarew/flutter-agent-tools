import 'dart:io';

import 'package:flutter_agent_tools/src/shorthand/package_info_tool.dart';
import 'package:flutter_agent_tools/src/shorthand/resolver.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

// Tests run from the package root; resolve to an absolute path as required
// by AnalysisContextCollectionImpl.
final String projectDir = Directory.current.absolute.path;

PackageResolver resolverFor(String packageName) {
  final version = resolveVersionFromLockfile(packageName, projectDir);
  final packageDir = findPackageInPubCache(packageName, version);
  if (packageDir == null) throw StateError('$packageName not in pub cache');
  final packageConfigFile = p.join(
    projectDir,
    '.dart_tool',
    'package_config.json',
  );
  return PackageResolver(
    packageDir: packageDir,
    packageConfigFile: packageConfigFile,
  );
}

void main() {
  group('PackageResolver.resolve', () {
    late PackageResolver resolver;
    setUp(() => resolver = resolverFor('yaml'));
    tearDown(() => resolver.dispose());

    test('resolves the main library', () async {
      final library = await resolver.resolve('package:yaml/yaml.dart');
      expect(library, isNotNull);
      expect(library!.uri.toString(), contains('yaml'));
    });

    test('returns null for a non-existent library URI', () async {
      final library = await resolver.resolve(
        'package:yaml/does_not_exist.dart',
      );
      expect(library, isNull);
    });
  });

  group('PackageResolver.resolve — http', () {
    late PackageResolver resolver;
    setUp(() => resolver = resolverFor('http'));
    tearDown(() => resolver.dispose());

    test('resolves the main library', () async {
      final library = await resolver.resolve('package:http/http.dart');
      expect(library, isNotNull);
    });
  });

  group('exportedNamesSummary', () {
    late PackageResolver yamlResolver;
    late PackageResolver httpResolver;
    setUp(() {
      yamlResolver = resolverFor('yaml');
      httpResolver = resolverFor('http');
    });
    tearDown(() async {
      await yamlResolver.dispose();
      await httpResolver.dispose();
    });

    test('lists exported names for yaml', () async {
      final library = await yamlResolver.resolve('package:yaml/yaml.dart');
      expect(library, isNotNull);
      final summary = exportedNamesSummary(library!);
      expect(summary, contains('loadYaml'));
      expect(summary, contains('functions:'));
    });

    test('lists exported names for http', () async {
      final library = await httpResolver.resolve('package:http/http.dart');
      expect(library, isNotNull);
      final summary = exportedNamesSummary(library!);
      expect(summary, contains('classes:'));
      expect(summary, contains('Client'));
    });
  });
}
