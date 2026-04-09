import 'dart:io';

import 'package:dart_mcp/server.dart';
import 'package:path/path.dart' as path;
import 'package:pub_semver/pub_semver.dart';
import 'package:yaml/yaml.dart';

import '../common.dart';
import 'resolver.dart';

abstract class PackagesTool {
  /// The MCP [Tool] definition (name, description, input schema).
  Tool get definition;

  /// Handles a [CallToolRequest], using [context] to access sessions and
  /// shared utilities.
  Future<CallToolResult> handle(CallToolRequest request, ToolContext context);
}

class ToolContext {
  /// Validate the required params are present.
  ///
  /// Throws a [ToolException] is a param is missing.
  void validateParams(CallToolRequest request, List<String> requiredParams) {
    // todo: throw one error for all missing params

    for (final param in requiredParams) {
      final String? value = request.arguments?[param] as String?;
      if (value == null || value.isEmpty) {
        throw ToolException('Missing required argument: $param');
      }
    }
  }

  /// Resolves the version used by the project and finds the package and version
  /// in the pub cache.
  ///
  /// This will throw a [ToolException] if the package is not found.
  Directory findPackageInPubCache(String projectDirectory, String packageName) {
    // Resolve version: pubspec.lock → latest cached.
    final String? version = resolveVersionFromLockfile(
      projectDirectory,
      packageName,
    );
    final Directory? packageDir = locateInPubCache(packageName, version);

    if (packageDir == null) {
      final message =
          version != null
              ? "Package '$packageName' version $version not found in pub "
                  'cache. Run `dart pub get` to download it.'
              : "Package '$packageName' not found in pub cache. Add it to "
                  'pubspec.yaml and run `dart pub get`.';
      throw ToolException(message);
    }

    return packageDir;
  }

  String? findPackageConfig(String projectDirectory) {
    final config = path.join(
      projectDirectory,
      '.dart_tool',
      'package_config.json',
    );
    return File(config).existsSync() ? config : null;
  }

  // Single-entry cache: reused when consecutive calls target the same package.
  PackageResolver? _resolver;
  String? _resolverKey;

  /// Returns or creates a [PackageResolver] for the given [packageDir] and
  /// [packageConfigFile], reusing the cached instance when the key matches.
  PackageResolver getResolver(Directory packageDir, String packageConfigFile) {
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
}

final StringSchema projectDirectorySchema = Schema.string(
  description:
      'Absolute path to the Dart/Flutter project directory (the folder '
      'containing pubspec.yaml). Used to resolve the package version from '
      'pubspec.lock and to locate the package_config.json for analysis.',
);

final StringSchema packageSchema = Schema.string(
  description: 'The package name (e.g. "http", "provider").',
);

final StringSchema librarySchema = Schema.string(
  description: 'The library URI to target, e.g. "package:http/http.dart".',
);

// ---------------------------------------------------------------------------
// Package resolution helpers (top-level functions for testability)

/// Returns the resolved version for [packageName] from the nearest
/// `pubspec.lock` found by walking up from [projectDirectory].
///
/// Walking up correctly handles pub workspaces where the lock file lives at
/// the workspace root rather than in each member package's directory.
/// Returns null if no lock file is found or the package is not listed.
String? resolveVersionFromLockfile(
  String projectDirectory,
  String packageName,
) {
  var dir = Directory(projectDirectory);
  while (true) {
    final lockFile = File(path.join(dir.path, 'pubspec.lock'));
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
Directory? locateInPubCache(String packageName, String? version) {
  final pubCacheDir = pubCacheHostedDir();
  if (pubCacheDir == null) return null;

  if (version != null) {
    final dir = Directory(path.join(pubCacheDir, '$packageName-$version'));
    return dir.existsSync() ? dir : null;
  }

  // No version pinned — find the highest cached version.
  final dirs =
      Directory(pubCacheDir)
          .listSync()
          .whereType<Directory>()
          .where((d) => path.basename(d.path).startsWith('$packageName-'))
          .toList();
  if (dirs.isEmpty) return null;

  Version parseDir(Directory d) {
    final suffix = path.basename(d.path).substring('$packageName-'.length);
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
      path.join(Platform.environment['HOME'] ?? '', '.pub-cache');
  final hosted = path.join(pubCache, 'hosted', 'pub.dev');
  return Directory(hosted).existsSync() ? hosted : null;
}

/// Reads the `version` field from a package's own `pubspec.yaml`.
String? readPackageVersion(Directory packageDir) {
  final pubspec = File(path.join(packageDir.path, 'pubspec.yaml'));
  if (!pubspec.existsSync()) return null;
  try {
    final yaml = loadYaml(pubspec.readAsStringSync());
    if (yaml is! Map) return null;
    return yaml['version'] as String?;
  } catch (_) {
    return null;
  }
}
