import 'package:dart_mcp/server.dart';
import 'package:vm_service/vm_service.dart' show RPCError;

import '../route_formatter.dart' show formatRouteInfo;
import '../tool_context.dart';

/// Implements the `get_route` MCP tool.
///
/// Returns the current navigator stack with screen widget names and source
/// locations. If the slipstream_agent companion is installed and a router
/// adapter is registered, enriches the output with the current route path.
class GetRouteTool extends InspectorTool {
  @override
  final Tool definition = Tool(
    name: 'get_route',
    description:
        'Returns the current navigator route stack with screen widget names '
        'and source locations. Use this to confirm which screen is active '
        'before inspecting or editing, or to answer "what screen is the app '
        'on?" questions. Enriches the stack with the current router path when '
        'the slipstream_agent companion is installed with a router adapter.',
    inputSchema: Schema.object(properties: {}, required: []),
  );

  @override
  Future<CallToolResult> handle(
    CallToolRequest request,
    ToolContext context,
  ) async {
    final session = context.activeSession;
    if (session == null) return context.noActiveSession();

    try {
      final extensions = session.serviceExtensions!;
      final root = await extensions.getRootWidgetTree(
        isSummaryTree: true,
        fullDetails: true,
      );

      // If the companion is installed, ask it for the current route path.
      String? currentPath;
      if (session.hasCompanion) {
        try {
          final response = await extensions.callSlipstreamExtension(
            'ext.slipstream.get_route',
          );
          if (response['ok'] == true) {
            currentPath = response['path'] as String?;
          }
        } catch (_) {
          // Path enrichment is best-effort — proceed without it.
        }
      }

      return CallToolResult(
        content: [
          TextContent(text: formatRouteInfo(root, currentPath: currentPath)),
        ],
      );
    } on RPCError catch (e) {
      return context.rpcError(e);
    }
  }
}
