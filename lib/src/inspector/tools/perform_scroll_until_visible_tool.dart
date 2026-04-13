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
    description:
        'Scrolls a Scrollable widget until a target widget is visible in the '
        'viewport. Two finders are required: one to locate the target widget, '
        'and one to locate the Scrollable that contains it.\n\n'
        'Finders for both: byKey (ValueKey string), byType (widget type name), '
        'byText (Text widget content), bySemanticsLabel (Semantics label).\n\n'
        'Example: scroll a ListView (scroll_finder="byType", '
        'scroll_finder_value="ListView") until item_42 is visible '
        '(finder="byKey", finder_value="item_42").\n\n'
        'Requires the slipstream_agent companion package.',
    inputSchema: Schema.object(
      properties: {
        'session_id': Schema.string(
          description: 'The session ID returned by run_app.',
        ),
        'finder': Schema.string(
          description:
              'How to find the target widget: "byKey", "byType", "byText", or '
              '"bySemanticsLabel".',
        ),
        'finder_value': Schema.string(
          description: 'The value to match against the target finder.',
        ),
        'scroll_finder': Schema.string(
          description:
              'How to find the Scrollable: "byKey", "byType", "byText", or '
              '"bySemanticsLabel".',
        ),
        'scroll_finder_value': Schema.string(
          description: 'The value to match against the scroll finder.',
        ),
      },
      required: [
        'session_id',
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

    final String sessionId = request.arguments!['session_id'] as String;
    final session = context.session(sessionId);
    if (session == null) return context.unknownSession(sessionId);
    if (!session.hasCompanion) {
      return context.companionNotInstalled('perform_scroll_until_visible');
    }

    final String finder = request.arguments!['finder'] as String;
    final String finderValue = request.arguments!['finder_value'] as String;
    final String scrollFinder = request.arguments!['scroll_finder'] as String;
    final String scrollFinderValue =
        request.arguments!['scroll_finder_value'] as String;

    try {
      final response = await session.serviceExtensions!.callSlipstreamExtension(
        'ext.slipstream.perform_action',
        args: {
          'action': 'scroll_until_visible',
          'finder': finder,
          'finderValue': finderValue,
          'scrollFinder': scrollFinder,
          'scrollFinderValue': scrollFinderValue,
        },
      );
      final bool ok = response['ok'] as bool? ?? false;
      if (!ok) {
        return CallToolResult(
          isError: true,
          content: [
            TextContent(
              text:
                  response['error'] as String? ?? 'scroll_until_visible failed',
            ),
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
