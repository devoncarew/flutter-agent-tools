import 'package:dart_mcp/server.dart';

import '../version.dart';
import 'api_tool.dart';

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

Call the 'api' tool with a package name to get its version, public library list,
and the content of its main entry-point library.

Source is the local pub cache — already downloaded, always matches the resolved
version in pubspec.lock, no network required.''',
      ) {
    _registerTools();
  }

  void _registerTools() {
    final tool = ApiTool();
    registerTool(tool.definition, tool.handle);
  }
}
