import 'package:dart_mcp/server.dart';

/// The MCP server for the dart-api (shorthand) package API summarization tool.
///
/// Provides token-efficient access to Dart package public APIs, reading
/// directly from the local pub cache. Implementation lives in lib/src/shorthand/.
base class ShorthandServer extends MCPServer with ToolsSupport, LoggingSupport {
  ShorthandServer(super.channel)
    : super.fromStreamChannel(
        implementation: Implementation(
          name: 'dart-api',
          version: '0.1.0',
        ),
        instructions: '''
Tools for querying Dart and Flutter package APIs directly from the pub cache.

Use these tools when you need accurate, up-to-date API signatures for a package
rather than relying on training-data summaries, which are often subtly wrong.

Typical workflow for an unfamiliar package:
1. package_info kind=package_summary — orient: version, entry-point import,
   exported names. Decide what to look at next.
2. package_info kind=library_stub — full public API for one library as Dart
   stubs (signatures, no bodies). The format you will write matches the format
   you read: no translation step, no transcription errors.
3. package_info kind=class_stub or kind=example — drill into a specific class
   or usage sample if signatures alone are not enough.

Source is the local pub cache — already downloaded, always matches the resolved
version in pubspec.lock, no network required.''',
      ) {
    _registerTools();
  }

  void _registerTools() {
    // TODO: register package_info tool.
  }
}
