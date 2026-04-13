import 'package:dart_mcp/server.dart';
import 'package:vm_service/vm_service.dart' show RPCError;

import '../tool_context.dart';

const _finderDescription =
    'How to find the widget: "byKey", "byType", "byText", or '
    '"bySemanticsLabel".';
const _finderValueDescription = 'The value to match against the chosen finder.';

/// Implements the `perform_set_text` MCP tool.
///
/// Sets the text content of a text field located by a finder. Requires the
/// slipstream_agent companion package. For semantics-based set_text without
/// the companion, use `perform_semantic_action` with action "setText".
class PerformSetTextTool extends InspectorTool {
  @override
  final Tool definition = Tool(
    name: 'perform_set_text',
    description:
        'Sets the text content of a text field located by a finder. Replaces '
        'the field\'s current content and fires the field\'s onChanged '
        'callback. Note: TextInputFormatters are not applied since text is set '
        'directly without going through the input pipeline.\n\n'
        'Finders: byKey (ValueKey string), byType (widget type name, e.g. '
        '"TextField"), byText (Text widget content), bySemanticsLabel '
        '(Semantics widget label).\n\n'
        'Tip: call perform_tap on the field first if the app requires focus '
        'before accepting text input.\n\n'
        'Requires the slipstream_agent companion package. Without it, use '
        'perform_semantic_action with action "setText" instead.',
    inputSchema: Schema.object(
      properties: {
        'finder': Schema.string(description: _finderDescription),
        'finder_value': Schema.string(description: _finderValueDescription),
        'text': Schema.string(
          description:
              'The text to set. Replaces the field\'s current content.',
        ),
      },
      required: ['finder', 'finder_value', 'text'],
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
      return context.companionNotInstalled('perform_set_text');
    }

    final String finder = request.arguments!['finder'] as String;
    final String finderValue = request.arguments!['finder_value'] as String;
    final String text = request.arguments!['text'] as String;

    try {
      final response = await session.serviceExtensions!.callSlipstreamExtension(
        'ext.slipstream.perform_action',
        args: {
          'action': 'set_text',
          'finder': finder,
          'finderValue': finderValue,
          'text': text,
        },
      );
      final bool ok = response['ok'] as bool? ?? false;
      if (!ok) {
        return CallToolResult(
          isError: true,
          content: [
            TextContent(
              text: response['error'] as String? ?? 'set_text failed',
            ),
          ],
        );
      }
      return CallToolResult(
        content: [TextContent(text: 'Set text on $finder="$finderValue"')],
      );
    } on RPCError catch (e) {
      return context.rpcError(e);
    }
  }
}
