import 'package:dart_mcp/server.dart';
import 'package:vm_service/vm_service.dart' show RPCError;

import '../../utils.dart';
import '../tool_context.dart';

/// Implements the `perform_semantic_action` MCP tool.
///
/// Dispatches a semantics action on a widget identified by node ID or label.
/// This is the baseline interaction tool — it works without the slipstream_agent
/// companion package but requires the target widget to have a semantics node.
///
/// For richer targeting (byKey, byType, byText) without semantics annotations,
/// install the slipstream_agent companion package and use the perform_* tools.
class PerformSemanticActionTool extends InspectorTool {
  @override
  final Tool definition = Tool(
    name: 'perform_semantic_action',
    description:
        'Dispatches a semantics action on a widget by its semantics node ID '
        'or label. Works without the slipstream_agent companion package, but '
        'requires the target widget to have a semantics node.\n\n'
        'Common actions:\n'
        '  - tap — tap a button, list item, or any tappable widget\n'
        '  - setText — set text field content; provide "value" with the text\n'
        '  - longPress — long-press a widget\n'
        '  - focus — move keyboard focus to an input field\n'
        '  - scrollUp / scrollDown — scroll a scrollable widget\n'
        '  - increase / decrease — adjust a slider or stepper\n\n'
        'One of "node_id" or "label" must be provided. Prefer "node_id" when '
        'available (faster — skips tree fetch). Use get_semantics first to see '
        'available nodes and their IDs.\n\n'
        'For apps with the slipstream_agent companion installed, prefer '
        'perform_tap, perform_set_text, perform_scroll, or '
        'perform_scroll_until_visible — they support byKey/byType/byText '
        'finders and do not require semantics annotations.',
    inputSchema: Schema.object(
      properties: {
        'action': Schema.string(
          description:
              'The SemanticsAction to dispatch. Common values: tap, setText, '
              'longPress, focus, scrollUp, scrollDown, increase, decrease.',
        ),
        'node_id': Schema.int(
          description:
              'The semantics node ID. Shown as "id=N" in get_semantics output. '
              'Prefer this over "label" when you already know the ID.',
        ),
        'label': Schema.string(
          description:
              'Dispatch to the first visible node whose label contains this '
              'text (case-insensitive substring match). Ignored if "node_id" '
              'is provided.',
        ),
        'value': Schema.string(
          description:
              'Required for the setText action. Replaces the field\'s current '
              'content entirely. Ignored for other actions.',
        ),
      },
      required: ['action'],
    ),
  );

  @override
  Future<CallToolResult> handle(
    CallToolRequest request,
    ToolContext context,
  ) async {
    context.validateParams(request, definition.inputSchema.required!);

    final session = context.activeSession;
    if (session == null) return context.noActiveSession();

    final String action = request.arguments!['action'] as String;
    final int? nodeId = coerceInt(request.arguments!['node_id']);
    final String? label = request.arguments!['label'] as String?;
    final String? value = request.arguments!['value'] as String?;

    if (nodeId == null && label == null) {
      return CallToolResult(
        isError: true,
        content: [
          TextContent(
            text:
                'perform_semantic_action: one of "node_id" or "label" must be '
                'provided.',
          ),
        ],
      );
    }

    try {
      final result = await session.serviceExtensions!.performSemanticsAction(
        actionType: action,
        nodeId: nodeId,
        label: label,
        arguments: value,
      );
      return CallToolResult(content: [TextContent(text: result)]);
    } on RPCError catch (e) {
      return context.rpcError(e);
    }
  }
}
