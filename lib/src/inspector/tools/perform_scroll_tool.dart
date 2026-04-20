import 'package:dart_mcp/server.dart';
import 'package:vm_service/vm_service.dart' show RPCError;

import '../../utils.dart';
import '../tool_context.dart';

/// Implements the `perform_scroll` MCP tool.
///
/// Scrolls a Scrollable widget by a fixed number of pixels. Requires the
/// slipstream_agent companion package.
class PerformScrollTool extends InspectorTool {
  @override
  final Tool definition = Tool(
    name: 'perform_scroll',
    description: '''
Scrolls a Scrollable widget by a fixed number of logical pixels. The finder
locates the Scrollable (e.g. ListView, SingleChildScrollView) directly. Clamped
to the scroll extent bounds.

Finders: byKey (ValueKey string), byType (widget type name, e.g. "ListView"),
byText (Text widget content), byTextContaining (Text content substring),
bySemanticsLabel (Semantics widget label).

To bring a specific widget into view, use perform_scroll_until_visible instead.

Requires the slipstream_agent companion package.''',
    inputSchema: Schema.object(
      properties: {
        'finder': Schema.string(
          description:
              'How to find the Scrollable widget: "byKey", "byType", "byText", '
              '"byTextContaining", or "bySemanticsLabel".',
        ),
        'finder_value': Schema.string(
          description: 'The value to match against the chosen finder.',
        ),
        'direction': Schema.string(
          description: 'Scroll direction: "up", "down", "left", or "right".',
        ),
        'pixels': Schema.num(
          description: 'Number of logical pixels to scroll.',
        ),
      },
      required: ['finder', 'finder_value', 'direction', 'pixels'],
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
      return context.companionNotInstalled('perform_scroll');
    }

    final String finder = request.arguments!['finder'] as String;
    final String finderValue = request.arguments!['finder_value'] as String;
    final String direction = request.arguments!['direction'] as String;
    final double pixels = coerceDouble(request.arguments!['pixels'])!;

    try {
      final result = await session.serviceExtensions!.slipstreamScroll(
        finder: finder,
        finderValue: finderValue,
        direction: direction,
        pixels: pixels,
      );
      if (!result.ok) {
        return CallToolResult(
          isError: true,
          content: [TextContent(text: result.error ?? 'scroll failed')],
        );
      }
      return CallToolResult(
        content: [
          TextContent(
            text: 'Scrolled $finder="$finderValue" $direction by $pixels px',
          ),
        ],
      );
    } on RPCError catch (e) {
      return context.rpcError(e);
    }
  }
}
