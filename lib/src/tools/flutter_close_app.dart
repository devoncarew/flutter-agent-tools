import 'package:dart_mcp/server.dart';

import '../tool_context.dart';

/// Implements the `flutter_close_app` MCP tool.
///
/// Stops a running Flutter app and releases its session.
class FlutterCloseAppTool extends FlutterTool {
  FlutterCloseAppTool();

  @override
  final Tool definition = Tool(
    name: 'flutter_close_app',
    description: 'Stops a running Flutter app and releases its session.',
    inputSchema: Schema.object(
      properties: {
        'session_id': Schema.string(
          description: 'The session ID returned by flutter_launch_app.',
        ),
      },
      required: ['session_id'],
    ),
  );

  @override
  Future<CallToolResult> handle(
    CallToolRequest request,
    ToolContext context,
  ) async {
    final String? sessionId = request.arguments!['session_id'] as String?;
    final session = context.removeSession(sessionId);
    if (sessionId == null || session == null) {
      return context.unknownSession(sessionId);
    }

    // We don't await this call.
    session.stop();

    return CallToolResult(content: [TextContent(text: 'App stopped.')]);
  }
}
