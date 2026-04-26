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
        'Dispatches a semantics action on a widget by semantics node ID or '
        'label. Works without slipstream_agent; requires the target to have a '
        'semantics node. Use get_semantics to see available nodes and IDs.\n\n'
        'Actions: tap, setText (requires "value"), longPress, focus, '
        'scrollUp, scrollDown, increase, decrease.\n\n'
        'Prefer node_id over label (faster). With slipstream_agent, prefer '
        'perform_tap/perform_set_text/perform_scroll instead.',
    inputSchema: Schema.object(
      properties: {
        'action': Schema.string(
          description:
              'The semantics action to dispatch (see tool description '
              'for the list).',
        ),
        'node_id': Schema.int(
          description:
              'Semantics node ID from get_semantics output (id=N). '
              'Prefer over label.',
        ),
        'label': Schema.string(
          description:
              'Case-insensitive substring match on node labels. '
              'Ignored if node_id is provided.',
        ),
        'value': Schema.string(
          description: 'Required for setText. Replaces current content.',
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
      final extensions = session.serviceExtensions!;
      final result = await extensions.performSemanticsAction(
        actionType: action,
        nodeId: nodeId,
        label: label,
        arguments: value,
      );
      if (session.hasCompanion) {
        final String target = nodeId != null ? 'id=$nodeId' : '"$label"';
        // We don't have a semantic ID finder type. We may consider adding one?
        // It could also be used for 'perform_tap', ...
        extensions.slipstreamLog(
          'perform semantic',
          details: '$action $target',
          kind: 'interact',
        );
      }
      return CallToolResult(content: [TextContent(text: result)]);
    } on RPCError catch (e) {
      return context.rpcError(e);
    }
  }
}
