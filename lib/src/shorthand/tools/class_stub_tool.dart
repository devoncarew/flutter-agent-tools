import 'dart:io';

import 'package:dart_mcp/server.dart';

import '../../common.dart';
import '../context.dart';
import '../stub_emitter.dart';

class ClassStubTool extends PackagesTool {
  ClassStubTool();

  @override
  final Tool definition = Tool(
    name: 'class_stub',
    description:
        'Returns the public API for a single named class, mixin, or extension '
        'as a Dart stub (signatures only, no bodies).',
    inputSchema: Schema.object(
      properties: {
        'project_directory': projectDirectorySchema,
        'package': packageSchema,
        'library_uri': librarySchema,
        'class': Schema.string(
          description:
              'The class, mixin, or extension name to target (e.g. "Client").',
        ),
      },
      required: ['project_directory', 'package', 'library_uri', 'class'],
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
    final String className = request.arguments?['class'] as String;

    final packageDir = context.resolvePackage(projectDirectory, packageName);

    return _handleClassStub(
      context,
      packageDir: packageDir,
      projectDirectory: projectDirectory,
      libraryUri: libraryUri,
      className: className,
    );
  }

  Future<CallToolResult> _handleClassStub(
    ToolContext context, {
    required Directory packageDir,
    required String projectDirectory,
    required String libraryUri,
    required String className,
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
      throw throw ToolException(
        "Could not resolve '$libraryUri'. "
        'Check that the library URI is correct and the package is in '
        'pubspec.lock.',
      );
    }

    final stub = emitElementStub(library, className);
    if (stub == null) {
      throw throw ToolException(
        "'$className' not found in '$libraryUri'. "
        'Use package_summary to list exported names.',
      );
    }

    return CallToolResult(content: [TextContent(text: stub)]);
  }
}
