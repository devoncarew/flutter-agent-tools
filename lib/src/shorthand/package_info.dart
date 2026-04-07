import 'dart:io';

import 'package:dart_mcp/server.dart';
import 'package:path/path.dart' as p;
import 'package:pub_semver/pub_semver.dart';
import 'package:yaml/yaml.dart';

/// Implements the `package_info` MCP tool.
///
/// Resolves a Dart package from the local pub cache and returns its public API
/// surface. Version resolution order: explicit `version` argument →
/// `pubspec.lock` in `project_directory` → latest cached version.
class PackageInfoTool {
  Tool get definition => Tool(
    name: 'package_info',
    description:
        'Returns public API information for a Dart or Flutter package '
        'directly from the local pub cache. '
        'Use this to get accurate, version-matched API signatures instead of '
        'relying on training-data summaries, which are often subtly wrong. '
        'Returns the package version, the list of public library files, and '
        'the content of the main library entry point.',
    inputSchema: Schema.object(
      properties: {
        'package': Schema.string(
          description: 'The package name (e.g. "http", "provider").',
        ),
        'project_directory': Schema.string(
          description:
              'Absolute path to the Dart/Flutter project directory '
              '(the folder containing pubspec.yaml). Used to resolve the '
              'package version from pubspec.lock.',
        ),
        'version': Schema.string(
          description:
              'Specific version to look up (e.g. "1.6.0"). Optional — '
              'defaults to the version resolved in pubspec.lock, or the '
              'latest cached version if the package is not yet in the '
              'lockfile.',
        ),
      },
      required: ['package', 'project_directory'],
    ),
  );

  Future<CallToolResult> handle(CallToolRequest request) async {
    final String? packageName = request.arguments?['package'] as String?;
    if (packageName == null || packageName.isEmpty) {
      return CallToolResult(
        isError: true,
        content: [TextContent(text: 'Missing required argument: package')],
      );
    }

    final String? projectDirectory =
        request.arguments?['project_directory'] as String?;
    if (projectDirectory == null || projectDirectory.isEmpty) {
      return CallToolResult(
        isError: true,
        content: [
          TextContent(text: 'Missing required argument: project_directory'),
        ],
      );
    }

    // Resolve the version: explicit arg → pubspec.lock → latest cached.
    final String? explicitVersion = request.arguments?['version'] as String?;
    final String? version =
        (explicitVersion != null && explicitVersion.isNotEmpty)
            ? explicitVersion
            : resolveVersionFromLockfile(packageName, projectDirectory);
    final Directory? packageDir = findPackageInPubCache(packageName, version);

    if (packageDir == null) {
      final msg =
          version != null
              ? "Package '$packageName' version $version not found in pub "
                  'cache. Run `dart pub get` to download it.'
              : "Package '$packageName' not found in pub cache. Add it to "
                  'pubspec.yaml and run `dart pub get`.';
      return CallToolResult(isError: true, content: [TextContent(text: msg)]);
    }

    final resolvedVersion =
        version ?? readPackageVersion(packageDir) ?? 'unknown';

    // List public library files (lib/*.dart, not lib/src/).
    final libDir = Directory(p.join(packageDir.path, 'lib'));
    final List<String> publicLibraries =
        libDir.existsSync()
            ? libDir
                .listSync()
                .whereType<File>()
                .where((f) => f.path.endsWith('.dart'))
                .map((f) => 'package:$packageName/${p.basename(f.path)}')
                .toList()
            : [];
    publicLibraries.sort();

    // Read the main entry point: lib/{package}.dart.
    final mainLibPath = p.join(packageDir.path, 'lib', '$packageName.dart');
    final mainLibFile = File(mainLibPath);
    final String mainLibContent =
        mainLibFile.existsSync()
            ? mainLibFile.readAsStringSync()
            : '// No lib/$packageName.dart found.';

    final buffer = StringBuffer();
    buffer.writeln('Package: $packageName $resolvedVersion');
    buffer.writeln('Pub cache: ${packageDir.path}');
    buffer.writeln();

    buffer.writeln('Public libraries:');
    for (final lib in publicLibraries) {
      buffer.writeln('  $lib');
    }
    buffer.writeln();

    buffer.writeln('// lib/$packageName.dart');
    buffer.writeln(mainLibContent);

    return CallToolResult(content: [TextContent(text: buffer.toString())]);
  }
}

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
