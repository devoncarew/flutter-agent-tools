import 'dart:convert';
import 'dart:io';

import 'package:dart_mcp/server.dart';
import 'package:path/path.dart' as path;
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
    final args = request.arguments ?? {};

    final missing =
        requiredParams.where((param) => !args.containsKey(param)).toList();
    if (missing.isNotEmpty) {
      final label = missing.length == 1 ? 'argument' : 'arguments';
      throw ToolException('Missing required $label: ${missing.join(', ')}');
    }
  }

  /// Resolves the directory for [packageName] using the project's
  /// `.dart_tool/package_config.json`.
  ///
  /// Throws a [ToolException] if the package is not found.
  Directory resolvePackage(String projectDirectory, String packageName) {
    final packageDir = resolvePackageFromConfig(projectDirectory, packageName);
    if (packageDir != null) return packageDir;

    throw ToolException(
      "Package '$packageName' not found. Make sure it is listed in "
      'pubspec.yaml and run `dart pub get`.',
    );
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
      'containing pubspec.yaml). Used to locate '
      '.dart_tool/package_config.json for package resolution and analysis. '
      'Run `dart pub get` first if the config is missing.',
);

final StringSchema packageSchema = Schema.string(
  description: 'The package name (e.g. "http", "provider").',
);

final StringSchema librarySchema = Schema.string(
  description: 'The library URI to target, e.g. "package:http/http.dart".',
);

// ---------------------------------------------------------------------------
// Package resolution helpers (top-level functions for testability)

/// Resolves the directory for [packageName] from the nearest
/// `.dart_tool/package_config.json` found by walking up from
/// [projectDirectory].
///
/// The `rootUri` in the config may be an absolute `file://` URI (hosted, git,
/// and SDK packages such as `package:flutter`) or a relative URI (path
/// dependencies). Relative URIs are resolved against the `.dart_tool/`
/// directory that contains the config file.
///
/// Walking up correctly handles pub workspaces where the config lives at the
/// workspace root rather than in each member package's directory.
///
/// Returns null if no config file is found, the package is not listed, or the
/// resolved directory does not exist on disk.
Directory? resolvePackageFromConfig(
  String projectDirectory,
  String packageName,
) {
  var dir = Directory(projectDirectory);
  while (true) {
    final configFile = File(
      path.join(dir.path, '.dart_tool', 'package_config.json'),
    );
    if (configFile.existsSync()) {
      try {
        final json =
            jsonDecode(configFile.readAsStringSync()) as Map<String, dynamic>;
        final packages =
            (json['packages'] as List?)
                ?.whereType<Map<String, dynamic>>()
                .toList();
        if (packages == null) return null;
        for (final pkg in packages) {
          if (pkg['name'] != packageName) continue;
          final rootUri = pkg['rootUri'] as String?;
          if (rootUri == null) return null;
          final uri = Uri.parse(rootUri);
          final Directory packageDir;
          if (uri.isAbsolute) {
            packageDir = Directory.fromUri(uri);
          } else {
            // Relative URI — resolve against the .dart_tool directory.
            packageDir = Directory.fromUri(
              configFile.parent.uri.resolveUri(uri),
            );
          }
          return packageDir.existsSync() ? packageDir : null;
        }
        return null; // package not listed in config
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
