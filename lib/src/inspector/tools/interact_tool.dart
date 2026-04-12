import 'package:dart_mcp/server.dart';
import 'package:vm_service/vm_service.dart' show RPCError;

import '../tool_context.dart';

/// Implements the `interact` MCP tool.
///
/// Performs UI actions (tap, set_text, scroll, scroll_until_visible) on a
/// widget located by an advanced finder (byKey, byType, byText,
/// bySemanticsLabel). Requires the slipstream_agent companion package.
///
/// When the companion is not installed, returns an actionable error explaining
/// how to add it. Use `perform_semantic_action` for semantics-based interaction
/// without the companion.
class InteractTool extends InspectorTool {
  @override
  final Tool definition = Tool(
    name: 'interact',
    description:
        'Performs a UI action on a widget located by an advanced finder. '
        'Requires the slipstream_agent companion package '
        '(`dev_dependency: slipstream_agent`).\n\n'
        'Actions:\n'
        '  - tap — tap a widget at its center\n'
        '  - set_text — replace a text field\'s content (provide "text")\n'
        '  - scroll — scroll a scrollable widget (provide "direction" and '
        '"pixels")\n'
        '  - scroll_until_visible — scroll until a widget is visible (provide '
        '"scroll_finder" and "scroll_finder_value")\n\n'
        'Finders:\n'
        '  - byKey — match a ValueKey string (e.g. "login_button")\n'
        '  - byType — match the widget\'s type name '
        '(e.g. "ElevatedButton")\n'
        '  - byText — match a Text widget\'s content exactly\n'
        '  - bySemanticsLabel — match a Semantics widget\'s label\n\n'
        'If the companion is not installed, use `perform_semantic_action` '
        'instead (semantics-based, works without the companion).',
    inputSchema: Schema.object(
      properties: {
        'session_id': Schema.string(
          description: 'The session ID returned by run_app.',
        ),
        'action': Schema.string(
          description: 'The action to perform: "tap" or "set_text".',
        ),
        'finder': Schema.string(
          description:
              'How to find the widget: "byKey", "byType", "byText", or '
              '"bySemanticsLabel".',
        ),
        'finder_value': Schema.string(
          description: 'The value to match against the chosen finder.',
        ),
        'text': Schema.string(
          description:
              'Required for the set_text action. The text to set — replaces '
              'the field\'s current content entirely.',
        ),
        'direction': Schema.string(
          description:
              'Required for scroll. One of: "up", "down", "left", "right".',
        ),
        'pixels': Schema.string(
          description:
              'Required for scroll. Number of logical pixels to scroll.',
        ),
        'scroll_finder': Schema.string(
          description:
              'Required for scroll_until_visible. Finder type for the '
              'Scrollable widget.',
        ),
        'scroll_finder_value': Schema.string(
          description:
              'Required for scroll_until_visible. Finder value for the '
              'Scrollable widget.',
        ),
      },
      required: ['session_id', 'action', 'finder', 'finder_value'],
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
    if (session == null) {
      return context.unknownSession(sessionId);
    }

    if (!session.hasCompanion) {
      return CallToolResult(
        isError: true,
        content: [
          TextContent(
            text:
                'interact: the slipstream_agent companion package is not '
                'installed in this app.\n\n'
                'Add it as a dev dependency:\n\n'
                '  dev_dependencies:\n'
                '    slipstream_agent: ^0.1.0\n\n'
                'Then call SlipstreamAgent.init() in your main() inside '
                'kDebugMode.\n\n'
                'Alternatively, use perform_semantic_action for '
                'semantics-based interaction without the companion package.',
          ),
        ],
      );
    }

    final String action = request.arguments!['action'] as String;
    final String finder = request.arguments!['finder'] as String;
    final String finderValue = request.arguments!['finder_value'] as String;
    final String? text = request.arguments!['text'] as String?;
    final String? direction = request.arguments!['direction'] as String?;
    final String? pixels = request.arguments!['pixels'] as String?;
    final String? scrollFinder = request.arguments!['scroll_finder'] as String?;
    final String? scrollFinderValue =
        request.arguments!['scroll_finder_value'] as String?;

    // Build the args map for ext.slipstream.interact.
    // MCP uses snake_case; the service extension uses camelCase.
    final Map<String, dynamic> args = {
      'action': action,
      'finder': finder,
      'finderValue': finderValue,
      if (text != null) 'text': text,
      if (direction != null) 'direction': direction,
      if (pixels != null) 'pixels': pixels,
      if (scrollFinder != null) 'scrollFinder': scrollFinder,
      if (scrollFinderValue != null) 'scrollFinderValue': scrollFinderValue,
    };

    try {
      final response = await session.serviceExtensions!.callSlipstreamExtension(
        'ext.slipstream.interact',
        args: args,
      );
      final bool ok = response['ok'] as bool? ?? false;
      if (!ok) {
        final String error = response['error'] as String? ?? 'interact failed';
        return CallToolResult(
          isError: true,
          content: [TextContent(text: error)],
        );
      }
      return CallToolResult(
        content: [
          TextContent(text: 'Performed $action on $finder="$finderValue"'),
        ],
      );
    } on RPCError catch (e) {
      return context.rpcError(e);
    }
  }
}
