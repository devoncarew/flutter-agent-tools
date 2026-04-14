import 'package:dart_mcp/server.dart';
import 'package:vm_service/vm_service.dart' show RPCError;

import '../semantic_node.dart';
import '../semantics_formatter.dart';
import '../tool_context.dart';

/// Implements the `get_semantics` MCP tool.
///
/// Returns a flat list of visible, interactive semantics nodes from the
/// running Flutter app.
class GetSemanticsTool extends InspectorTool {
  @override
  final Tool definition = Tool(
    name: 'get_semantics',
    description:
        'Returns a flat list of visible semantics nodes from the running '
        'Flutter app. Each node shows its role, ID, state flags, supported '
        'actions, label, and size. '
        'Use this to find what is on screen and what can be interacted with. '
        "Node IDs from this output can be passed directly to "
        "'perform_semantic_action'. "
        'Node IDs are stable until the next hot reload or hot restart.',
    inputSchema: Schema.object(properties: {}, required: []),
  );

  // TODO: Implement typed wrappers for the slipstream agent ext. methods in
  // FlutterServiceExtensions.

  @override
  Future<CallToolResult> handle(
    CallToolRequest request,
    ToolContext context,
  ) async {
    final session = context.activeSession;
    if (session == null) return context.noActiveSession();

    try {
      final List<SemanticNode> nodes;

      if (session.hasCompanion) {
        // Use the companion extension — returns screen-space coordinates.
        final extensions = session.serviceExtensions!;

        var response = await extensions.callSlipstreamExtension(
          'ext.slipstream.get_semantics',
        );

        if (response['ok'] != true) {
          final error = response['error'] as String? ?? 'get_semantics failed';
          return CallToolResult(
            content: [TextContent(text: error)],
            isError: true,
          );
        }
        nodes = parseCompanionSemanticsNodes(
          response['nodes'] as List<dynamic>? ?? [],
        );
      } else {
        // Fallback: evaluate-based path; coordinates are in local space.
        nodes = await session.serviceExtensions!.getSemanticsTree();
      }

      return CallToolResult(
        content: [TextContent(text: formatSemanticsTree(nodes))],
      );
    } on RPCError catch (e) {
      return context.rpcError(e);
    }
  }
}
