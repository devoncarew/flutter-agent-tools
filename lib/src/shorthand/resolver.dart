import 'dart:io';

import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/element/element.dart';
// ignore: implementation_imports (packageConfigFile is not exposed on the
// public AnalysisContextCollection factory; the Impl class is the only path)
import 'package:analyzer/src/dart/analysis/analysis_context_collection.dart'; // ignore: implementation_imports
import 'package:path/path.dart' as p;

/// Resolves libraries from a single package in the pub cache.
///
/// Each instance is bound to one [packageDir] and one [packageConfigFile].
/// Resolution uses the caller project's `.dart_tool/package_config.json` so
/// the agent sees exactly the API their compiler sees — no separate `pub get`
/// is needed. The package must already be in the project's `pubspec.lock`.
///
/// The caller is responsible for caching instances: create one per
/// package/version and discard it when switching packages.
class PackageResolver {
  final Directory packageDir;
  late final AnalysisContextCollectionImpl _context;

  PackageResolver({required this.packageDir, required String packageConfigFile})
    : _context = AnalysisContextCollectionImpl(
        includedPaths: [packageDir.path],
        sdkPath: _sdkPath(),
        packageConfigFile: packageConfigFile,
      );

  /// Returns a resolved [LibraryElement] for [libraryUri].
  ///
  /// [libraryUri] is a `package:` URI such as `package:http/http.dart`.
  /// Returns null if the library file does not exist or cannot be resolved.
  Future<LibraryElement?> resolve(String libraryUri) async {
    final path = _uriToPath(libraryUri);
    if (path == null || !File(path).existsSync()) return null;

    final analysisContext = _context.contextFor(path);
    final result = await analysisContext.currentSession.getResolvedLibrary(
      path,
    );
    if (result is! ResolvedLibraryResult) return null;
    return result.element;
  }

  /// Converts a `package:` URI to an absolute file path within [packageDir].
  String? _uriToPath(String uri) {
    if (!uri.startsWith('package:')) return null;
    // package:foo/bar/baz.dart → bar/baz.dart (relative to lib/)
    final withoutScheme = uri.substring('package:'.length);
    final slash = withoutScheme.indexOf('/');
    if (slash < 0) return null;
    final relativeToLib = withoutScheme.substring(slash + 1);
    return p.join(packageDir.path, 'lib', relativeToLib);
  }

  Future<void> dispose() async => _context.dispose();

  // dart executable is at <sdk>/bin/dart; SDK root is two levels up.
  static String _sdkPath() => p.dirname(p.dirname(Platform.resolvedExecutable));
}

/// Returns the names exported by [library], grouped by kind, as a
/// human-readable summary string. Used as a smoke-test for resolution.
String exportedNamesSummary(LibraryElement library) {
  final classes = <String>[];
  final mixins = <String>[];
  final extensions = <String>[];
  final functions = <String>[];
  final variables = <String>[];
  final typedefs = <String>[];
  final enums = <String>[];

  for (final entry in library.exportNamespace.definedNames2.entries) {
    final name = entry.key;
    final element = entry.value;
    if (name.startsWith('_')) continue;
    switch (element) {
      case EnumElement():
        enums.add(name);
      case ClassElement():
        classes.add(name);
      case MixinElement():
        mixins.add(name);
      case ExtensionElement():
        extensions.add(name);
      case TopLevelFunctionElement():
        functions.add(name);
      // Top-level variables appear in the namespace as GetterElements.
      case GetterElement e when e.isOriginVariable:
        final v = e.variable;
        if (v is TopLevelVariableElement) variables.add(name);
      case TypeAliasElement():
        typedefs.add(name);
    }
  }

  for (final names in [
    classes,
    mixins,
    extensions,
    functions,
    variables,
    typedefs,
    enums,
  ]) {
    names.sort();
  }

  final buf = StringBuffer();
  void section(String label, List<String> names) {
    if (names.isEmpty) return;
    buf.writeln('$label: ${names.join(', ')}');
  }

  section('classes', classes);
  section('mixins', mixins);
  section('extensions', extensions);
  section('enums', enums);
  section('functions', functions);
  section('typedefs', typedefs);
  section('variables', variables);

  return buf.toString().trimRight();
}
