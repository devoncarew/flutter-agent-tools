import 'package:dart_mcp/server.dart';

import '../common.dart';
import 'context.dart';
import 'tools/class_stub_tool.dart';
import 'tools/library_stub_tool.dart';
import 'tools/package_summary_tool.dart';

/// The MCP server for the 'packages' package API summarization tool.
///
/// Provides token-efficient access to Dart package public APIs, reading
/// directly from the local pub cache.
base class PackagesMCPServer extends MCPServer
    with ToolsSupport, LoggingSupport {
  PackagesMCPServer(super.channel)
    : super.fromStreamChannel(
        implementation: Implementation(
          name: 'packages',
          version: packageVersion,
        ),
        instructions: '''
Tools for querying Dart and Flutter package APIs directly from the pub cache.

Use these tools when you need accurate, up-to-date API signatures for a package
rather than relying on training-data summaries, which are often subtly wrong.

Typical call sequence:
1. package_summary — orient on the package: version, library list, exported names.
2. library_stub — get full API signatures for one library.
3. class_stub — drill into a specific class when you know exactly what you need.

Source is the local pub cache — already downloaded, always matches the resolved
version in pubspec.lock, no network required.''',
      ) {
    _registerTools();
  }

  final ToolContext context = ToolContext();

  void _registerTools() {
    _register(PackageSummaryTool());
    _register(LibraryStubTool());
    _register(ClassStubTool());
  }

  void _register(PackagesTool tool) {
    registerTool(tool.definition, (req) async {
      try {
        return await tool.handle(req, context);
      } on ToolException catch (e) {
        return CallToolResult(
          content: [TextContent(text: e.message)],
          isError: true,
        );
      }
    }, validateArguments: false);
  }
}
