import 'package:dart_mcp/server.dart';
import 'package:vm_service/vm_service.dart' show RPCError;

import '../tool_context.dart';

/// Implements the `perform_tap` MCP tool.
///
/// Taps a widget located by a finder. Requires the slipstream_agent companion
/// package. For semantics-based tap without the companion, use
/// `perform_semantic_action` with action "tap".
class PerformTapTool extends InspectorTool {
  @override
  final Tool definition = Tool(
    name: 'perform_tap',
    description: '''
Taps a widget located by a finder. Synthesizes a pointer down/up event at the
widget's center — triggers GestureDetector.onTap, InkWell.onTap, and any other
gesture recognizers.

Finders: byKey (ValueKey string), byType (widget type name, e.g.
"ElevatedButton"), byText (exact Text content), byTextContaining (Text content
substring), bySemanticsLabel (Semantics widget label).

Requires the slipstream_agent companion package. Without it, use
perform_semantic_action with action "tap" instead.''',
    inputSchema: Schema.object(
      properties: {
        'finder': Schema.string(
          description:
              'How to find the widget: "byKey", "byType", "byText", "byTextContaining", '
              'or "bySemanticsLabel".',
        ),
        'finder_value': Schema.string(
          description: 'The value to match against the chosen finder.',
        ),
      },
      required: ['finder', 'finder_value'],
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

    if (!session.hasCompanion) {
      return context.companionNotInstalled('perform_tap');
    }

    final String finder = request.arguments!['finder'] as String;
    final String finderValue = request.arguments!['finder_value'] as String;

    try {
      final result = await session.serviceExtensions!.slipstreamTap(
        finder: finder,
        finderValue: finderValue,
      );
      if (!result.ok) {
        return CallToolResult(
          isError: true,
          content: [TextContent(text: result.error ?? 'tap failed')],
        );
      }
      return CallToolResult(
        content: [TextContent(text: 'Tapped $finder="$finderValue"')],
      );
    } on RPCError catch (e) {
      return context.rpcError(e);
    }
  }
}
