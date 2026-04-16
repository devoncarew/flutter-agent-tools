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
        'widget_id': Schema.string(
          description:
              'The widget ID to inspect. Omit to start from the root widget.',
        ),
        'subtree_depth': Schema.int(
          description: 'How many levels of children to include. Defaults to 1.',
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
    if (session == null) {
      return context.noActiveSession();
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
        // Use the summary tree to start from the first user-created widget,
        // skipping internal Flutter framework wrappers (View, RawView, etc.)
        // which are 10+ levels above app code and make inspect_layout useless
        // at default subtree depths.
        final summaryRoot = await extensions.getRootWidgetTree(
          isSummaryTree: true,
        );
        final appRoot =
            summaryRoot.children.isNotEmpty ? summaryRoot.children.first : null;
        if (appRoot?.valueId != null) {
          resolvedId = appRoot!.valueId!;
        } else {
          // Fall back to the raw root widget.
          final root = await extensions.getRootWidget();
          if (root.valueId == null) {
            return CallToolResult(
              isError: true,
              content: [TextContent(text: 'Root widget has no valueId.')],
            );
          }
          resolvedId = root.valueId!;
        }
      }
      final node = await extensions.getDetailsSubtree(
        resolvedId,
        subtreeDepth: subtreeDepth,
      );
      final layoutSummary = formatLayoutDetails(node, maxDepth: subtreeDepth);
      if (session.hasCompanion) {
        // We don't have a way to pass Flutter Inspector IDs as a widget finder.
        // That's not really an issue; for the moment it means that the widget
        // under inspection won't flash. In the future we may have an
        // 'ext.slipstream.inspect_layout', which would be finder based.
        extensions.slipstreamLog(
          'inspect layout',
          details: widgetId,
          kind: 'read',
          viz: 'layout',
        );
      }
      return CallToolResult(content: [TextContent(text: layoutSummary)]);
    } on RPCError catch (e) {
      return context.rpcError(e);
    }
  }
}
