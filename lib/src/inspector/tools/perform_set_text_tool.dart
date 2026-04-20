import 'package:dart_mcp/server.dart';
import 'package:vm_service/vm_service.dart' show RPCError;

import '../tool_context.dart';

/// Implements the `perform_set_text` MCP tool.
///
/// Sets the text content of a text field located by a finder. Requires the
/// slipstream_agent companion package. For semantics-based set_text without
/// the companion, use `perform_semantic_action` with action "setText".
class PerformSetTextTool extends InspectorTool {
  @override
  final Tool definition = Tool(
    name: 'perform_set_text',
    description: '''
Sets the text content of a text field located by a finder. Replaces the field's
current content and fires the field's onChanged callback. Note:
TextInputFormatters are not applied since text is set directly without going
through the input pipeline.

Finders: byKey (ValueKey string), byType (widget type name, e.g. "TextField"),
byText (exact Text content), byTextContaining (Text content substring),
bySemanticsLabel (Semantics widget label).

Tip: call perform_tap on the field first if the app requires focus before
accepting text input.

Requires the slipstream_agent companion package. Without it, use
perform_semantic_action with action "setText" instead.''',
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
      final result = await session.serviceExtensions!.slipstreamSetText(
        finder: finder,
        finderValue: finderValue,
        text: text,
      );
      if (!result.ok) {
        return CallToolResult(
          isError: true,
          content: [TextContent(text: result.error ?? 'set_text failed')],
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
