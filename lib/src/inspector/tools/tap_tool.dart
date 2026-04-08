import 'package:dart_mcp/server.dart';
import 'package:vm_service/vm_service.dart' show RPCError;

import '../tool_context.dart';

/// Implements the `tap` MCP tool.
///
/// Taps a widget identified by semantics node ID or label, using
/// `SemanticsBinding.performSemanticsAction`. No screen coordinates needed.
class TapTool extends InspectorTool {
  @override
  final Tool definition = Tool(
    name: 'tap',
    description:
        'Taps a widget by its semantics node ID or label. '
        'Dispatches a tap action via SemanticsBinding.performSemanticsAction — '
        'no screen coordinates needed. '
        'One of "node_id" or "label" must be provided. '
        'Prefer "node_id" when available (faster — skips tree fetch). '
        'Use get_semantics first to see available nodes and their IDs.',
    inputSchema: Schema.object(
      properties: {
        'session_id': Schema.string(
          description: 'The session ID returned by run_app.',
        ),
        'node_id': Schema.int(
          description:
              'The semantics node ID to tap. Shown as "id=N" in '
              'get_semantics output. Prefer this over '
              '"label" when you already know the ID.',
        ),
        'label': Schema.string(
          description:
              'Tap the first visible node whose label contains this text '
              '(case-insensitive substring match). Use when you do not have '
              'a node ID. Ignored if "node_id" is provided.',
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

    final int? nodeId = request.arguments!['node_id'] as int?;
    final String? label = request.arguments!['label'] as String?;

    if (nodeId == null && label == null) {
      return CallToolResult(
        isError: true,
        content: [
          TextContent(
            text: 'tap: one of "node_id" or "label" must be provided.',
          ),
        ],
      );
    }

    try {
      final result = await session.serviceExtensions!.performSemanticsAction(
        actionType: 'tap',
        nodeId: nodeId,
        label: label,
      );
      return CallToolResult(content: [TextContent(text: result)]);
    } on RPCError catch (e) {
      return context.rpcError(e);
    }
  }
}
