import 'package:dart_mcp/server.dart';

import '../tool_context.dart';

/// Implements the `close_app` MCP tool.
///
/// Stops the running Flutter app and releases its session.
class CloseAppTool extends InspectorTool {
  CloseAppTool();

  @override
  final Tool definition = Tool(
    name: 'close_app',
    description: 'Stops the running Flutter app and releases its session.',
    inputSchema: Schema.object(properties: {}, required: []),
  );

  @override
  Future<CallToolResult> handle(
    CallToolRequest request,
    ToolContext context,
  ) async {
    final session = context.removeSession();
    if (session == null) {
      return CallToolResult(
        content: [TextContent(text: 'No app was running.')],
      );
    }

    await session.stop().timeout(
      Duration(milliseconds: 250),
      onTimeout: () => null,
    );

    return CallToolResult(content: [TextContent(text: 'Closed app.')]);
  }
}
