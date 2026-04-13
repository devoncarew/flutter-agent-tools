import 'package:dart_mcp/server.dart';
import 'package:vm_service/vm_service.dart' show RPCError;

import '../tool_context.dart';

const _finderDescription =
    'How to find the Scrollable widget: "byKey", "byType", "byText", or '
    '"bySemanticsLabel".';
const _finderValueDescription = 'The value to match against the chosen finder.';

/// Implements the `perform_scroll` MCP tool.
///
/// Scrolls a Scrollable widget by a fixed number of pixels. Requires the
/// slipstream_agent companion package.
class PerformScrollTool extends InspectorTool {
  @override
  final Tool definition = Tool(
    name: 'perform_scroll',
    description:
        'Scrolls a Scrollable widget by a fixed number of logical pixels. '
        'The finder locates the Scrollable (e.g. ListView, SingleChildScrollView) '
        'directly. Clamped to the scroll extent bounds.\n\n'
        'Finders: byKey (ValueKey string), byType (widget type name, e.g. '
        '"ListView"), byText (Text widget content), bySemanticsLabel '
        '(Semantics widget label).\n\n'
        'To bring a specific widget into view, use perform_scroll_until_visible '
        'instead.\n\n'
        'Requires the slipstream_agent companion package.',
    inputSchema: Schema.object(
      properties: {
        'session_id': Schema.string(
          description: 'The session ID returned by run_app.',
        ),
        'finder': Schema.string(description: _finderDescription),
        'finder_value': Schema.string(description: _finderValueDescription),
        'direction': Schema.string(
          description: 'Scroll direction: "up", "down", "left", or "right".',
        ),
        'pixels': Schema.string(
          description: 'Number of logical pixels to scroll.',
        ),
      },
      required: ['session_id', 'finder', 'finder_value', 'direction', 'pixels'],
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
      return context.companionNotInstalled('perform_scroll');
    }

    final String finder = request.arguments!['finder'] as String;
    final String finderValue = request.arguments!['finder_value'] as String;
    final String direction = request.arguments!['direction'] as String;
    final String pixels = request.arguments!['pixels'] as String;

    try {
      final response = await session.serviceExtensions!.callSlipstreamExtension(
        'ext.slipstream.perform_action',
        args: {
          'action': 'scroll',
          'finder': finder,
          'finderValue': finderValue,
          'direction': direction,
          'pixels': pixels,
        },
      );
      final bool ok = response['ok'] as bool? ?? false;
      if (!ok) {
        return CallToolResult(
          isError: true,
          content: [
            TextContent(text: response['error'] as String? ?? 'scroll failed'),
          ],
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
