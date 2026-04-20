import 'package:dart_mcp/server.dart';

import '../tool_context.dart';

/// Implements the `get_output` MCP tool.
///
/// Drains the session output buffer and returns the accumulated lines. The
/// buffer is cleared after each call and on hot reload/restart.
class GetOutputTool extends InspectorTool {
  @override
  final Tool definition = Tool(
    name: 'get_output',
    description:
        'Returns buffered app output and runtime events since the last call '
        '(or the last reload/restart).\n\n'
        'Call this after reload, after interaction tools (perform_tap, '
        'perform_set_text, etc.), and after run_app to check for errors or '
        'unexpected output. Calling this clears the buffer.\n\n'
        'Output is prefixed by source:\n'
        '- [app] print() / debugPrint() output from the app\n'
        '- [stdout] other process stdout\n'
        '- [flutter.error] framework errors; widget IDs usable with inspect_layout\n'
        '- [route] navigation events (requires slipstream_agent companion)',
    inputSchema: Schema.object(properties: {}, required: []),
  );

  @override
  Future<CallToolResult> handle(
    CallToolRequest request,
    ToolContext context,
  ) async {
    final session = context.activeSession;
    if (session == null) return context.noActiveSession();

    final lines = session.drainOutput();
    final text = lines.isEmpty ? '(no output)' : lines.join('\n');

    if (session.hasCompanion) {
      final extensions = session.serviceExtensions!;

      // "get output: 7 lines, 1 error"
      var msg = '∅';
      final errors =
          lines.where((line) => line.startsWith('[flutter.error]')).length;
      if (lines.isNotEmpty) {
        msg = lines.length == 1 ? '1 line' : '${lines.length} lines';
        if (errors != 0) {
          final errDesc = errors == 1 ? '1 error' : '$errors errors';
          msg = '$msg, $errDesc';
        }
      }

      extensions.slipstreamLog('get output', kind: 'read', details: msg);

      // Clear the error banner once the agent has seen the errors.
      if (errors > 0) {
        extensions.slipstreamClearErrors();
      }
    }

    return CallToolResult(content: [TextContent(text: text)]);
  }
}
