import 'package:dart_mcp/server.dart';

import '../app_session.dart';
import '../tool_context.dart';

/// Implements the `flutter_reload` MCP tool.
///
/// Hot reloads or hot restarts a running Flutter app.
class FlutterReloadTool extends FlutterTool {
  @override
  final Tool definition = Tool(
    name: 'flutter_reload',
    description:
        'Applies source file changes to a running Flutter app. Call this '
        'after editing Dart files, before taking a screenshot or inspecting '
        'layout. Prefer hot reload for iterative changes; use hot restart '
        '(full_restart: true) when state needs to be fully reset.',
    inputSchema: Schema.object(
      properties: {
        'session_id': Schema.string(
          description: 'The session ID returned by flutter_launch_app.',
        ),
        'full_restart': Schema.bool(
          description:
              'If true, performs a hot restart instead of a hot reload. '
              'Defaults to false.',
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
    final session = context.session(sessionId);
    if (sessionId == null || session == null) {
      return context.unknownSession(sessionId);
    }

    final bool fullRestart =
        request.arguments!['full_restart'] as bool? ?? false;
    try {
      await session.restart(fullRestart: fullRestart);
    } on DaemonException catch (e) {
      return CallToolResult(
        isError: true,
        content: [TextContent(text: e.message)],
      );
    }

    final String action = fullRestart ? 'Hot restart' : 'Hot reload';
    return CallToolResult(content: [TextContent(text: '$action complete.')]);
  }
}
