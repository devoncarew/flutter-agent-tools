import 'package:dart_mcp/server.dart';
import 'package:vm_service/vm_service.dart' show RPCError;

import '../tool_context.dart';

/// Implements the `set_text` MCP tool.
///
/// Sets the text content of a text field identified by semantics node ID or
/// label, using `SemanticsAction.setText`.
class SetTextTool extends InspectorTool {
  @override
  final Tool definition = Tool(
    name: 'set_text',
    description:
        'Sets the text content of a text field by its semantics node ID or '
        'label. Dispatches SemanticsAction.setText — replaces the field\'s '
        'current content entirely. No keyboard simulation needed. '
        'One of "node_id" or "label" must be provided. '
        'Prefer "node_id" when available (faster — skips tree fetch). '
        'Semantics node IDs and labels appear in get_semantics output. '
        "Tip: tap the field first ('tap') if the app requires focus "
        'before accepting text input.',
    inputSchema: Schema.object(
      properties: {
        'session_id': Schema.string(
          description: 'The session ID returned by run_app.',
        ),
        'text': Schema.string(
          description:
              'The text to set. Replaces the field\'s current content.',
        ),
        'node_id': Schema.int(
          description:
              'The semantics node ID of the text field. Shown as "id=N" in '
              'get_semantics output. Prefer this over "label" when '
              'you already know the ID.',
        ),
        'label': Schema.string(
          description:
              'Set text in the first visible node whose label contains this '
              'text (case-insensitive substring match). Use when you do not '
              'have a node ID. Ignored if "node_id" is provided.',
        ),
      },
      required: ['session_id', 'text'],
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

    final String text = request.arguments!['text'] as String;
    final int? nodeId = request.arguments!['node_id'] as int?;
    final String? label = request.arguments!['label'] as String?;

    if (nodeId == null && label == null) {
      return CallToolResult(
        isError: true,
        content: [
          TextContent(
            text: 'set_text: one of "node_id" or "label" must be provided.',
          ),
        ],
      );
    }

    try {
      final result = await session.serviceExtensions!.performSemanticsAction(
        actionType: 'setText',
        nodeId: nodeId,
        label: label,
        arguments: text,
      );
      return CallToolResult(content: [TextContent(text: result)]);
    } on RPCError catch (e) {
      return context.rpcError(e);
    }
  }
}
