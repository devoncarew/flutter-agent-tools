import 'package:dart_mcp/server.dart';

import '../tool_context.dart';

/// Implements the `close_app` MCP tool.
///
/// Stops a running Flutter app and releases its session.
class CloseAppTool extends FlutterTool {
  CloseAppTool();

  @override
  final Tool definition = Tool(
    name: 'close_app',
    description: 'Stops a running Flutter app and releases its session.',
    inputSchema: Schema.object(
      properties: {
        'session_id': Schema.string(
          description: 'The session ID returned by run_app.',
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
