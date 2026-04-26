import 'package:dart_mcp/server.dart';
import 'package:vm_service/vm_service.dart' show RPCError;

import '../tool_context.dart';

/// Implements the `perform_scroll_until_visible` MCP tool.
///
/// Scrolls a Scrollable widget until a target widget is visible in the
/// viewport. Requires the slipstream_agent companion package.
class PerformScrollUntilVisibleTool extends InspectorTool {
  @override
  final Tool definition = Tool(
    name: 'perform_scroll_until_visible',
    description: 'Scrolls a Scrollable until a target widget is visible in '
        'the viewport. Two finders required: one for the target widget, one '
        'for the Scrollable. Requires slipstream_agent.',
    inputSchema: Schema.object(
      properties: {
        'finder': Schema.string(
          description: 'Finder type for the target widget: "byKey", "byType", '
              '"byText", "byTextContaining", or "bySemanticsLabel".',
        ),
        'finder_value': Schema.string(
          description: 'Value to match against the target finder.',
        ),
        'scroll_finder': Schema.string(
          description: 'Finder type for the Scrollable (same types as finder).',
        ),
        'scroll_finder_value': Schema.string(
          description: 'Value to match against the scroll finder.',
        ),
      },
      required: [
        'finder',
        'finder_value',
        'scroll_finder',
        'scroll_finder_value',
      ],
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
      return context.companionNotInstalled('perform_scroll_until_visible');
    }

    final String finder = request.arguments!['finder'] as String;
    final String finderValue = request.arguments!['finder_value'] as String;
    final String scrollFinder = request.arguments!['scroll_finder'] as String;
    final String scrollFinderValue =
        request.arguments!['scroll_finder_value'] as String;

    try {
      final result = await session.serviceExtensions!
          .slipstreamScrollUntilVisible(
            finder: finder,
            finderValue: finderValue,
            scrollFinder: scrollFinder,
            scrollFinderValue: scrollFinderValue,
          );
      if (!result.ok) {
        return CallToolResult(
          isError: true,
          content: [
            TextContent(text: result.error ?? 'scroll_until_visible failed'),
          ],
        );
      }
      return CallToolResult(
        content: [
          TextContent(text: 'Scrolled until $finder="$finderValue" is visible'),
        ],
      );
    } on RPCError catch (e) {
      return context.rpcError(e);
    }
  }
}
