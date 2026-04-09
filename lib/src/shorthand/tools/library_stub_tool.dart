import 'dart:io';

import 'package:dart_mcp/server.dart';

import '../../common.dart';
import '../context.dart';
import '../stub_emitter.dart';

class LibraryStubTool extends PackagesTool {
  LibraryStubTool();

  @override
  final Tool definition = Tool(
    name: 'library_stub',
    description:
        'Returns the full public API for one library as a Dart stub '
        '(signatures only, no bodies).',
    inputSchema: Schema.object(
      properties: {
        'project_directory': projectDirectorySchema,
        'package': packageSchema,
        'library_uri': librarySchema,
      },
      required: ['project_directory', 'package', 'library_uri'],
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
    final String libraryUri = request.arguments?['library_uri'] as String;

    final packageDir = context.findPackageInPubCache(
      projectDirectory,
      packageName,
    );

    return _handleLibraryStub(
      context,
      packageDir: packageDir,
      projectDirectory: projectDirectory,
      libraryUri: libraryUri,
    );
  }

  Future<CallToolResult> _handleLibraryStub(
    ToolContext context, {
    required Directory packageDir,
    required String projectDirectory,
    required String libraryUri,
  }) async {
    final packageConfig = context.findPackageConfig(projectDirectory);
    if (packageConfig == null) {
      throw ToolException(
        'package_config.json not found; '
        'Run `dart pub get` in the project directory first.',
      );
    }

    final resolver = context.getResolver(packageDir, packageConfig);
    final library = await resolver.resolve(libraryUri);
    if (library == null) {
      throw ToolException(
        "Could not resolve '$libraryUri'. "
        'Check that the library URI is correct and the package is in '
        'pubspec.lock.',
      );
    }

    return CallToolResult(
      content: [TextContent(text: emitLibraryStub(library))],
    );
  }
}
