import 'dart:io';

import 'package:dart_mcp/server.dart';
import 'package:path/path.dart' as p;

import '../context.dart';
import '../resolver.dart';

/// Implements the `package_summary` MCP tool.
///
/// Resolves a Dart package from the local pub cache and returns its public API
/// surface. Version resolution order: `pubspec.lock` in `project_directory` →
/// latest cached version.
class PackageSummaryTool extends PackagesTool {
  @override
  final Tool definition = Tool(
    name: 'package_summary',
    description:
        'Returns API summaries for Dart or Flutter packages; start here to '
        'orient on an unfamiliar package. Use this to get accurate, '
        'version-matched API signatures instead of relying on training-data '
        'summaries, which are often subtly wrong.\n\n'
        'The returned package summary contains version, entry-point import, '
        'README excerpt, public library list, and exported name groups for the '
        'main library.',
    inputSchema: Schema.object(
      properties: {
        'project_directory': projectDirectorySchema,
        'package': packageSchema,
      },
      required: ['project_directory', 'package'],
    ),
  );

  @override
  Future<CallToolResult> handle(
    CallToolRequest request,
    ToolContext context,
  ) async {
    context.validateParams(request, definition.inputSchema.required!);

    final String projectDirectory =
        request.arguments?['project_directory'] as String;
    final String packageName = request.arguments?['package'] as String;

    final packageDir = context.resolvePackage(projectDirectory, packageName);

    final version = readPackageVersion(packageDir) ?? 'unknown';

    return _handlePackageSummary(
      context,
      packageName: packageName,
      packageDir: packageDir,
      resolvedVersion: version,
      projectDirectory: projectDirectory,
    );
  }

  Future<CallToolResult> _handlePackageSummary(
    ToolContext context, {
    required String packageName,
    required Directory packageDir,
    required String resolvedVersion,
    required String projectDirectory,
  }) async {
    final buf = StringBuffer();

    // Header.
    buf.writeln('Package: $packageName $resolvedVersion');
    buf.writeln('Source: ${packageDir.path}');

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
    if (publicLibraries.isEmpty) {
      buf.writeln('  (none)');
    } else {
      buf.writeln(
        'Use library_stub with library_uri=... on a URI below to get full API '
        'signatures for all exported names in one call.',
      );
      for (final lib in publicLibraries) {
        buf.writeln('  $lib');
      }
    }

    // Exported names from the main library (requires analysis).
    final packageConfig = context.findPackageConfig(projectDirectory);
    if (mainLibUri != null && packageConfig != null) {
      final resolver = context.getResolver(packageDir, packageConfig);
      final library = await resolver.resolve(mainLibUri);
      if (library != null) {
        final summary = exportedNamesSummary(library);
        if (summary.isNotEmpty) {
          buf.writeln();
          buf.writeln('## Exports ($mainLibUri)');
          buf.writeln(
            'Use class_stub with library_uri=... and class=... to get '
            'signatures for a single type.',
          );
          buf.writeln(summary);
        }
      }
    }

    // Example files.
    final exampleDir = Directory(p.join(packageDir.path, 'example'));
    if (exampleDir.existsSync()) {
      final examples =
          exampleDir
              .listSync(recursive: true)
              .whereType<File>()
              .where((f) => f.path.endsWith('.dart'))
              .map((f) => p.relative(f.path, from: packageDir.path))
              .toList()
            ..sort();
      if (examples.isNotEmpty) {
        buf.writeln();
        buf.writeln('## Examples');
        for (final ex in examples) {
          buf.writeln('  $ex');
        }
      }
    }

    return CallToolResult(content: [TextContent(text: buf.toString())]);
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
}
