import 'package:dart_mcp/server.dart';

import '../tool_context.dart';

/// Implements the `close_app` MCP tool.
///
/// Stops a running Flutter app and releases its session.
class CloseAppTool extends InspectorTool {
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
    context.validateParams(request, definition.inputSchema.required!);

    final String sessionId = request.arguments!['session_id'] as String;
    final session = context.removeSession(sessionId);
    if (session == null) {
      return context.unknownSession(sessionId);
    }

    // Don't wait more than 250ms for the call to complete.
    await session.stop().timeout(
      Duration(milliseconds: 250),
      onTimeout: () => null,
    );

    return CallToolResult(content: [TextContent(text: 'App stopped.')]);
  }
}
