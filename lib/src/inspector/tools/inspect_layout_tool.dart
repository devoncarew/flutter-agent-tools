import 'package:dart_mcp/server.dart';
import 'package:vm_service/vm_service.dart' show RPCError;

import '../layout_formatter.dart';
import '../tool_context.dart';
import '../../utils.dart';

/// Implements the `inspect_layout` MCP tool.
///
/// Returns layout details (constraints, size, flex parameters, children) for
/// a widget in the running app.
class InspectLayoutTool extends InspectorTool {
  @override
  final Tool definition = Tool(
    name: 'inspect_layout',
    description:
        'Use when debugging layout issues, overflow errors, or unexpected '
        'widget sizing. Returns constraints, size, flex parameters, and '
        'children for a widget. Omit widget_id to start from the root. '
        'Widget IDs are included in flutter.error log events and in the '
        'output of prior inspect calls — use them to drill into a specific '
        'node. Increase subtree_depth to see deeper child layout.',
    inputSchema: Schema.object(
      properties: {
        'session_id': Schema.string(
          description: 'The session ID returned by run_app.',
        ),
        'widget_id': Schema.string(
          description:
              'The widget ID to inspect. Omit to start from the root widget.',
        ),
        'subtree_depth': Schema.int(
          description: 'How many levels of children to include. Defaults to 1.',
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

    final String? widgetId = request.arguments!['widget_id'] as String?;
    final int subtreeDepth =
        coerceInt(request.arguments!['subtree_depth']) ?? 1;

    try {
      final extensions = session.serviceExtensions!;
      final String resolvedId;
      if (widgetId != null) {
        resolvedId = widgetId;
      } else {
        final root = await extensions.getRootWidget();
        if (root.valueId == null) {
          return CallToolResult(
            isError: true,
            content: [TextContent(text: 'Root widget has no valueId.')],
          );
        }
        resolvedId = root.valueId!;
      }
      final node = await extensions.getDetailsSubtree(
        resolvedId,
        subtreeDepth: subtreeDepth,
      );
      final layoutSummary = formatLayoutDetails(node, maxDepth: subtreeDepth);
      return CallToolResult(content: [TextContent(text: layoutSummary)]);
    } on RPCError catch (e) {
      return context.rpcError(e);
    }
  }
}
