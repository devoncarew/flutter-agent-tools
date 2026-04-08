import 'package:dart_mcp/server.dart';
import 'package:vm_service/vm_service.dart' show RPCError;

import '../route_formatter.dart' show formatRouteInfo;
import '../tool_context.dart';

/// Implements the `get_route` MCP tool.
///
/// Returns the current navigator stack with screen widget names and source
/// locations.
class GetRouteTool extends InspectorTool {
  @override
  final Tool definition = Tool(
    name: 'get_route',
    description:
        'Returns the current navigator route stack with screen widget names '
        'and source locations. Use this to confirm which screen is active '
        'before inspecting or editing, or to answer "what screen is the app '
        'on?" questions. Enriches the stack with the current go_router path '
        'when the app uses go_router.',
    inputSchema: Schema.object(
      properties: {
        'session_id': Schema.string(
          description: 'The session ID returned by run_app.',
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

    try {
      final extensions = session.serviceExtensions!;
      final root = await extensions.getRootWidgetTree(
        isSummaryTree: true,
        fullDetails: true,
      );

      // Best-effort: resolve the current go_router path via VM evaluate.
      String? currentPath;
      try {
        final vmId = await extensions.resolveGoRouterVmId();
        if (vmId != null) {
          currentPath = await extensions.evaluateOnObject(
            vmId,
            'widget.goRouter.state.uri.toString()',
          );
        }
      } catch (_) {
        // go_router enrichment is best-effort — proceed without path info.
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
