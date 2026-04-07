import 'dart:io';

import 'package:dart_mcp/server.dart';
import 'package:path/path.dart' as p;
import 'package:pub_semver/pub_semver.dart';
import 'package:yaml/yaml.dart';

import 'resolver.dart';
import 'stub_emitter.dart';

/// Implements the `package_info` MCP tool.
///
/// Resolves a Dart package from the local pub cache and returns its public API
/// surface. Version resolution order: `pubspec.lock` in `project_directory` →
/// latest cached version.
class PackageInfoTool {
  // Single-entry cache: reused when consecutive calls target the same package.
  PackageResolver? _resolver;
  String? _resolverKey;

  Tool get definition => Tool(
    name: 'package_info',
    description:
        'Returns API summaries of Dart or Flutter packages. '
        'Use this to get accurate, version-matched API signatures instead of '
        'relying on training-data summaries, which are often subtly wrong.\n\n'
        'kind values:\n'
        '  package_summary — version, entry-point import, README excerpt, '
        'public library list, and exported name groups for the main library. '
        'Start here to orient on an unfamiliar package.\n'
        '  library_stub — full public API for one library as a Dart stub '
        '(signatures only, no bodies). Requires the `library` parameter.\n'
        '  class_stub — stub for a single named class, mixin, or extension. '
        'Requires both `library` and `class` parameters.',
    inputSchema: Schema.object(
      properties: {
        'project_directory': Schema.string(
          description:
              'Absolute path to the Dart/Flutter project directory '
              '(the folder containing pubspec.yaml). Used to resolve the '
              'package version from pubspec.lock and to locate the '
              'package_config.json for analysis.',
        ),
        'package': Schema.string(
          description: 'The package name (e.g. "http", "provider").',
        ),
        'kind': Schema.string(
          description:
              'What to return. One of: package_summary, library_stub, '
              'class_stub. Defaults to package_summary.',
        ),
        'library': Schema.string(
          description:
              'The library URI to target, e.g. "package:http/http.dart". '
              'Required for library_stub and class_stub.',
        ),
        'class': Schema.string(
          description:
              'The class, mixin, or extension name to target. '
              'Required for class_stub.',
        ),
      },
      required: ['project_directory', 'package'],
    ),
  );

  Future<CallToolResult> handle(CallToolRequest request) async {
    final String? packageName = request.arguments?['package'] as String?;
    if (packageName == null || packageName.isEmpty) {
      return _error('Missing required argument: package');
    }

    final String? explicitKind = request.arguments?['kind'] as String?;
    final kind =
        explicitKind == null || explicitKind.isEmpty
            ? 'package_summary'
            : explicitKind;

    final String? projectDirectory =
        request.arguments?['project_directory'] as String?;
    if (projectDirectory == null || projectDirectory.isEmpty) {
      return _error('Missing required argument: project_directory');
    }

    // Resolve version: pubspec.lock → latest cached.
    final String? version = resolveVersionFromLockfile(
      packageName,
      projectDirectory,
    );
    final Directory? packageDir = findPackageInPubCache(packageName, version);

    if (packageDir == null) {
      final msg =
          version != null
              ? "Package '$packageName' version $version not found in pub "
                  'cache. Run `dart pub get` to download it.'
              : "Package '$packageName' not found in pub cache. Add it to "
                  'pubspec.yaml and run `dart pub get`.';
      return _error(msg);
    }

    final resolvedVersion =
        version ?? readPackageVersion(packageDir) ?? 'unknown';

    return switch (kind) {
      'package_summary' => await _packageSummary(
        packageName: packageName,
        packageDir: packageDir,
        resolvedVersion: resolvedVersion,
        projectDirectory: projectDirectory,
      ),
      'library_stub' => await _libraryStub(
        packageDir: packageDir,
        projectDirectory: projectDirectory,
        libraryUri: request.arguments?['library'] as String? ?? '',
      ),
      'class_stub' => await _classStub(
        packageDir: packageDir,
        projectDirectory: projectDirectory,
        libraryUri: request.arguments?['library'] as String? ?? '',
        className: request.arguments?['class'] as String? ?? '',
      ),
      _ => _error(
        "Unknown kind '$kind'. Use: package_summary, library_stub, "
        'class_stub.',
      ),
    };
  }

  Future<CallToolResult> _packageSummary({
    required String packageName,
    required Directory packageDir,
    required String resolvedVersion,
    required String projectDirectory,
  }) async {
    final buf = StringBuffer();

    // Header.
    buf.writeln('Package: $packageName $resolvedVersion');

    // Entry-point import — only if the conventional lib/name.dart exists.
    final mainLibFile = File(
      p.join(packageDir.path, 'lib', '$packageName.dart'),
    );
    final mainLibUri =
        mainLibFile.existsSync()
            ? 'package:$packageName/$packageName.dart'
            : null;
    if (mainLibUri != null) {
      buf.writeln("import '$mainLibUri';");
    }

    // README excerpt.
    final readme = _readmeExcerpt(packageDir);
    if (readme != null) {
      buf.writeln();
      buf.writeln('## Overview');
      buf.writeln(readme);
    }

    // Public library list: all .dart files under lib/, excluding lib/src/.
    final libDir = Directory(p.join(packageDir.path, 'lib'));
    final libSrcPrefix =
        p.join(packageDir.path, 'lib', 'src') + Platform.pathSeparator;
    final publicLibraries =
        libDir.existsSync()
            ? libDir
                .listSync(recursive: true)
                .whereType<File>()
                .where(
                  (f) =>
                      f.path.endsWith('.dart') &&
                      !f.path.startsWith(libSrcPrefix),
                )
                .map(
                  (f) =>
                      'package:$packageName/'
                      '${p.relative(f.path, from: p.join(packageDir.path, 'lib'))}',
                )
                .toList()
            : <String>[];
    publicLibraries.sort();

    buf.writeln();
    buf.writeln('## Libraries');
    for (final lib in publicLibraries) {
      buf.writeln('  $lib');
    }

    // Exported names from the main library (requires analysis).
    final packageConfigFile = p.join(
      projectDirectory,
      '.dart_tool',
      'package_config.json',
    );
    if (mainLibUri != null && File(packageConfigFile).existsSync()) {
      final resolver = _getResolver(packageDir, packageConfigFile);
      final library = await resolver.resolve(mainLibUri);
      if (library != null) {
        final summary = exportedNamesSummary(library);
        if (summary.isNotEmpty) {
          buf.writeln();
          buf.writeln('## Exports ($mainLibUri)');
          buf.writeln(summary);
        }
      }
    }

    return CallToolResult(content: [TextContent(text: buf.toString())]);
  }

  /// Returns or creates a [PackageResolver] for the given [packageDir] and
  /// [packageConfigFile], reusing the cached instance when the key matches.
  PackageResolver _getResolver(Directory packageDir, String packageConfigFile) {
    final key = '${packageDir.path}|$packageConfigFile';
    if (_resolverKey != key) {
      _resolver?.dispose(); // fire-and-forget
      _resolver = PackageResolver(
        packageDir: packageDir,
        packageConfigFile: packageConfigFile,
      );
      _resolverKey = key;
    }
    return _resolver!;
  }

  /// Reads the first descriptive paragraph from README.md (skipping headings
  /// and badge lines).
  String? _readmeExcerpt(Directory packageDir) {
    for (final name in ['README.md', 'readme.md', 'README']) {
      final file = File(p.join(packageDir.path, name));
      if (file.existsSync()) {
        return _extractFirstParagraph(file.readAsStringSync());
      }
    }
    return null;
  }

  String? _extractFirstParagraph(String content) {
    final lines = content.split('\n');
    final paragraph = <String>[];
    var started = false;

    for (final line in lines) {
      final trimmed = line.trim();
      if (!started) {
        if (trimmed.isEmpty) continue;
        if (trimmed.startsWith('#')) continue;
        if (trimmed.startsWith('[![')) continue; // badge lines
        started = true;
        paragraph.add(trimmed);
      } else {
        if (trimmed.isEmpty) break;
        paragraph.add(trimmed);
      }
    }

    return paragraph.isEmpty ? null : paragraph.join('\n');
  }

  Future<CallToolResult> _libraryStub({
    required Directory packageDir,
    required String projectDirectory,
    required String libraryUri,
  }) async {
    if (libraryUri.isEmpty) {
      return _error(
        'Missing required argument: library '
        '(e.g. "package:http/http.dart").',
      );
    }

    final packageConfigFile = p.join(
      projectDirectory,
      '.dart_tool',
      'package_config.json',
    );
    if (!File(packageConfigFile).existsSync()) {
      return _error(
        'package_config.json not found at $packageConfigFile. '
        'Run `dart pub get` in the project directory first.',
      );
    }

    final resolver = _getResolver(packageDir, packageConfigFile);
    final library = await resolver.resolve(libraryUri);
    if (library == null) {
      return _error(
        "Could not resolve '$libraryUri'. "
        'Check that the library URI is correct and the package is in '
        'pubspec.lock.',
      );
    }

    return CallToolResult(
      content: [TextContent(text: emitLibraryStub(library))],
    );
  }

  Future<CallToolResult> _classStub({
    required Directory packageDir,
    required String projectDirectory,
    required String libraryUri,
    required String className,
  }) async {
    if (libraryUri.isEmpty) {
      return _error(
        'Missing required argument: library '
        '(e.g. "package:http/http.dart").',
      );
    }
    if (className.isEmpty) {
      return _error('Missing required argument: class (e.g. "Client").');
    }

    final packageConfigFile = p.join(
      projectDirectory,
      '.dart_tool',
      'package_config.json',
    );
    if (!File(packageConfigFile).existsSync()) {
      return _error(
        'package_config.json not found at $packageConfigFile. '
        'Run `dart pub get` in the project directory first.',
      );
    }

    final resolver = _getResolver(packageDir, packageConfigFile);
    final library = await resolver.resolve(libraryUri);
    if (library == null) {
      return _error(
        "Could not resolve '$libraryUri'. "
        'Check that the library URI is correct and the package is in '
        'pubspec.lock.',
      );
    }

    final stub = emitElementStub(library, className);
    if (stub == null) {
      return _error(
        "'$className' not found in '$libraryUri'. "
        'Use kind=package_summary to list exported names.',
      );
    }

    return CallToolResult(content: [TextContent(text: stub)]);
  }

  static CallToolResult _error(String message) =>
      CallToolResult(isError: true, content: [TextContent(text: message)]);
}

// ---------------------------------------------------------------------------
// Package resolution helpers (top-level functions for testability)

/// Returns the resolved version for [packageName] from the nearest
/// `pubspec.lock` found by walking up from [projectDirectory].
///
/// Walking up correctly handles pub workspaces where the lock file lives at
/// the workspace root rather than in each member package's directory.
/// Returns null if no lock file is found or the package is not listed.
String? resolveVersionFromLockfile(
  String packageName,
  String projectDirectory,
) {
  var dir = Directory(projectDirectory);
  while (true) {
    final lockFile = File(p.join(dir.path, 'pubspec.lock'));
    if (lockFile.existsSync()) {
      try {
        final yaml = loadYaml(lockFile.readAsStringSync());
        if (yaml is! Map) return null;
        final packages = yaml['packages'];
        if (packages is! Map) return null;
        final entry = packages[packageName];
        if (entry is! Map) return null;
        return entry['version'] as String?;
      } catch (_) {
        return null;
      }
    }
    final parent = dir.parent;
    if (parent.path == dir.path) break; // filesystem root
    dir = parent;
  }
  return null;
}

/// Finds the package directory in the pub cache for [packageName].
///
/// If [version] is provided, looks for an exact match. Otherwise returns
/// the directory with the highest semver version.
/// Returns null if the pub cache cannot be located or the package is absent.
Directory? findPackageInPubCache(String packageName, String? version) {
  final pubCacheDir = pubCacheHostedDir();
  if (pubCacheDir == null) return null;

  if (version != null) {
    final dir = Directory(p.join(pubCacheDir, '$packageName-$version'));
    return dir.existsSync() ? dir : null;
  }

  // No version pinned — find the highest cached version.
  final dirs =
      Directory(pubCacheDir)
          .listSync()
          .whereType<Directory>()
          .where((d) => p.basename(d.path).startsWith('$packageName-'))
          .toList();
  if (dirs.isEmpty) return null;

  Version parseDir(Directory d) {
    final suffix = p.basename(d.path).substring('$packageName-'.length);
    try {
      return Version.parse(suffix);
    } catch (_) {
      return Version.none;
    }
  }

  dirs.sort((a, b) => parseDir(a).compareTo(parseDir(b)));
  return dirs.last;
}

/// Returns the path to `~/.pub-cache/hosted/pub.dev`, or null if not found.
///
/// Respects the `PUB_CACHE` environment variable when set.
String? pubCacheHostedDir() {
  final pubCache =
      Platform.environment['PUB_CACHE'] ??
      p.join(Platform.environment['HOME'] ?? '', '.pub-cache');
  final hosted = p.join(pubCache, 'hosted', 'pub.dev');
  return Directory(hosted).existsSync() ? hosted : null;
}

/// Reads the `version` field from a package's own `pubspec.yaml`.
String? readPackageVersion(Directory packageDir) {
  final pubspec = File(p.join(packageDir.path, 'pubspec.yaml'));
  if (!pubspec.existsSync()) return null;
  try {
    final yaml = loadYaml(pubspec.readAsStringSync());
    if (yaml is! Map) return null;
    return yaml['version'] as String?;
  } catch (_) {
    return null;
  }
}
