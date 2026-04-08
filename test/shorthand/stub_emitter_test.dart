import 'dart:io';

import 'package:flutter_slipstream/src/shorthand/context.dart';
import 'package:flutter_slipstream/src/shorthand/resolver.dart';
import 'package:flutter_slipstream/src/shorthand/stub_emitter.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

final String projectDir = Directory.current.absolute.path;

PackageResolver resolverFor(String packageName) {
  final version = resolveVersionFromLockfile(packageName, projectDir);
  final packageDir = locateInPubCache(packageName, version);
  if (packageDir == null) throw StateError('$packageName not in pub cache');
  return PackageResolver(
    packageDir: packageDir,
    packageConfigFile: p.join(projectDir, '.dart_tool', 'package_config.json'),
  );
}

void main() {
  group('emitLibraryStub — yaml', () {
    late PackageResolver resolver;
    late String stub;

    setUpAll(() async {
      resolver = resolverFor('yaml');
      final library = await resolver.resolve('package:yaml/yaml.dart');
      stub = emitLibraryStub(library!);
    });

    tearDownAll(() => resolver.dispose());

    test('contains loadYaml function', () {
      expect(stub, contains('loadYaml'));
    });

    test('contains loadYamlStream function', () {
      expect(stub, contains('loadYamlStream'));
    });

    test('does not contain method bodies (no return/throw statements)', () {
      expect(stub, isNot(contains('\n    return ')));
      expect(stub, isNot(contains('\n    throw ')));
    });

    test('member declarations end with semicolon, not braces', () {
      // Every non-blank, non-comment line that starts with exactly two spaces
      // (i.e. a class member, not a class/enum header or closing brace) should
      // end with a semicolon.
      final memberLines =
          stub.split('\n').where((l) {
            if (!l.startsWith('  ') || l.startsWith('   ')) return false;
            final t = l.trim();
            return t.isNotEmpty && !t.startsWith('//') && !t.startsWith('///');
          }).toList();
      for (final line in memberLines) {
        expect(
          line.trimRight().endsWith(';'),
          isTrue,
          reason: 'Expected semicolon on member: $line',
        );
      }
    });
  });

  group('emitLibraryStub — http', () {
    late PackageResolver resolver;
    late String stub;

    setUpAll(() async {
      resolver = resolverFor('http');
      final library = await resolver.resolve('package:http/http.dart');
      stub = emitLibraryStub(library!);
    });

    tearDownAll(() => resolver.dispose());

    test('contains Client class', () {
      expect(stub, contains('class Client'));
    });

    test('contains Response class', () {
      expect(stub, contains('class Response'));
    });

    test('contains top-level get function', () {
      expect(stub, contains('get('));
    });

    test('contains top-level post function', () {
      expect(stub, contains('post('));
    });

    test('does not expose private members', () {
      expect(stub, isNot(contains('_withClient')));
    });
  });
}
