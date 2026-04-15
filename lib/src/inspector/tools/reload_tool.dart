import 'package:dart_mcp/server.dart';

import '../app_session.dart';
import '../tool_context.dart';
import '../../utils.dart';

/// Implements the `reload` MCP tool.
///
/// Hot reloads or hot restarts a running Flutter app.
class ReloadTool extends InspectorTool {
  @override
  final Tool definition = Tool(
    name: 'reload',
    description:
        'Applies source file changes to a running Flutter app. Call this '
        'after editing Dart files, before taking a screenshot or inspecting '
        'layout. Prefer hot reload for iterative changes; use hot restart '
        '(full_restart: true) when state needs to be fully reset.',
    inputSchema: Schema.object(
      properties: {
        'full_restart': Schema.bool(
          description:
              'If true, performs a hot restart instead of a hot reload. '
              'Defaults to false.',
        ),
      },
      required: [],
    ),
  );

  @override
  Future<CallToolResult> handle(
    CallToolRequest request,
    ToolContext context,
  ) async {
    final session = context.activeSession;
    if (session == null) return context.noActiveSession();

    final bool fullRestart =
        coerceBool(request.arguments!['full_restart']) ?? false;
    try {
      await session.restart(fullRestart: fullRestart);
    } on DaemonException catch (e) {
      return CallToolResult(
        isError: true,
        content: [TextContent(text: e.message)],
      );
    }

    final String action = fullRestart ? 'Hot restart' : 'Hot reload';

    if (session.hasCompanion) {
      // TODO: This may be too early to call 'log'. Consider delaying it until
      // we know the companion package is available.
      session.serviceExtensions?.slipstreamLog(
        fullRestart ? 'restart' : 'reload',
      );
    }

    return CallToolResult(
      content: [
        TextContent(
          text:
              '$action complete. '
              'Semantics node IDs reset — call get_semantics before reusing any.',
        ),
      ],
    );
  }
}
