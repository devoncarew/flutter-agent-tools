import 'dart:convert';
import 'dart:io';

import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/element/element.dart';
// ignore: implementation_imports
import 'package:analyzer/src/dart/analysis/analysis_context_collection.dart';
import 'package:path/path.dart' as p;

/// Parses and resolves [source] as a Dart library and returns its
/// [LibraryElement].
///
/// Writes the source to a temporary directory alongside a minimal
/// `package_config.json`, resolves it with the real SDK, then cleans up.
///
/// Use this in tests to obtain a [LibraryElement] without needing the pub
/// cache or an existing project on disk.
Future<LibraryElement> libraryElementFromSource(String source) async {
  final tmp = await Directory.systemTemp.createTemp('analyzer_test_');
  try {
    final libDir = Directory(p.join(tmp.path, 'lib'))..createSync();
    final srcFile = File(p.join(libDir.path, 'test.dart'))
      ..writeAsStringSync(source);

    final configDir = Directory(p.join(tmp.path, '.dart_tool'))..createSync();
    File(p.join(configDir.path, 'package_config.json')).writeAsStringSync(
      jsonEncode({
        'configVersion': 2,
        'packages': [
          {
            'name': 'test_pkg',
            'rootUri': '../',
            'packageUri': 'lib/',
            'languageVersion': '3.7',
          },
        ],
      }),
    );

    // sdkPath is omitted — AnalysisContextCollectionImpl locates the SDK
    // automatically from the running Dart executable.
    final collection = AnalysisContextCollectionImpl(
      includedPaths: [libDir.path],
      packageConfigFile: p.join(configDir.path, 'package_config.json'),
    );

    final context = collection.contextFor(srcFile.path);
    final result = await context.currentSession.getResolvedLibrary(
      srcFile.path,
    );
    if (result is! ResolvedLibraryResult) {
      throw StateError('Failed to resolve library: $result');
    }
    return result.element;
  } finally {
    await tmp.delete(recursive: true);
  }
}
