import 'package:dart_mcp/server.dart';
import 'package:vm_service/vm_service.dart' show RPCError;

import '../route_formatter.dart';
import '../semantics_formatter.dart';
import '../tool_context.dart';

/// Implements the `flutter_query_ui` MCP tool.
///
/// Returns a high-level description of what is currently on screen in the
/// running Flutter app.
class FlutterQueryUiTool extends FlutterTool {
  @override
  final Tool definition = Tool(
    name: 'flutter_query_ui',
    description:
        'Returns a high-level description of what is currently on screen in '
        'the running Flutter app. Use to orient before navigating to a '
        'specific app state, to confirm a change took effect, or to '
        'understand the current route before drilling into layout details. '
        'Modes: '
        '"route" — current route name and navigator stack (use this for '
        '"what screen/route is the app on?" questions); '
        '"semantics" — flat list of visible, interactive nodes (labels, '
        'roles, bounding boxes); '
        '"widget_tree" — summary widget tree filtered to user-written widgets.',
    inputSchema: Schema.object(
      properties: {
        'session_id': Schema.string(
          description: 'The session ID returned by flutter_launch_app.',
        ),
        'mode': Schema.string(
          description:
              'What to return. One of: "semantics", "widget_tree", "route".',
        ),
      },
      required: ['session_id', 'mode'],
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

    final String? mode = request.arguments!['mode'] as String?;
    if (mode == null ||
        !const {'semantics', 'widget_tree', 'route'}.contains(mode)) {
      return CallToolResult(
        isError: true,
        content: [
          TextContent(
            text:
                'Invalid mode "$mode". '
                'Must be one of: semantics, widget_tree, route.',
          ),
        ],
      );
    }

    try {
      final extensions = session.serviceExtensions!;
      switch (mode) {
        case 'route':
          final root = await extensions.getRootWidgetTree(
            isSummaryTree: true,
            fullDetails: true,
          );

          // Best-effort: resolve the current go_router path via VM evaluate.
          // Finds InheritedGoRouter in the widget tree, converts its inspector
          // handle to a VM object ID, then evaluates widget.goRouter.state.uri.
          String? currentPath;
          try {
            final goRouterNodes = findGoRouterNodes(root);
            if (goRouterNodes.isNotEmpty) {
              final valueId = goRouterNodes.first.valueId;
              if (valueId != null) {
                final vmId = await extensions.inspectorIdToVmObjectId(valueId);
                if (vmId != null) {
                  currentPath = await extensions.evaluateOnObject(
                    vmId,
                    'widget.goRouter.state.uri.toString()',
                  );
                }
              }
            }
          } catch (_) {
            // go_router enrichment is best-effort — proceed without path info.
          }

          return CallToolResult(
            content: [
              TextContent(
                text: formatRouteInfo(root, currentPath: currentPath),
              ),
            ],
          );
        case 'semantics':
          final json = await extensions.getSemanticsTree();
          return CallToolResult(
            content: [TextContent(text: formatSemanticsTree(json))],
          );
        default:
          return CallToolResult(
            isError: true,
            content: [
              TextContent(
                text: 'flutter_query_ui mode "$mode": not yet implemented.',
              ),
            ],
          );
      }
    } on RPCError catch (e) {
      return context.rpcError(e);
    }
  }
}
