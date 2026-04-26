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
    description: 'Sets the text content of a text field located by a finder. '
        'Replaces current content and fires onChanged. TextInputFormatters are '
        'not applied. Call perform_tap on the field first if focus is required. '
        'Requires slipstream_agent; without it use perform_semantic_action '
        'with action "setText".',
    inputSchema: Schema.object(
      properties: {
        'finder': Schema.string(
          description: 'Finder type: "byKey", "byType", "byText", '
              '"byTextContaining", or "bySemanticsLabel".',
        ),
        'finder_value': Schema.string(
          description: 'Value to match against the finder.',
        ),
        'text': Schema.string(
          description: 'Text to set. Replaces the current content.',
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
