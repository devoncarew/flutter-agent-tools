import 'package:dart_mcp/server.dart';

import '../tool_context.dart';

/// Implements the `get_output` MCP tool.
///
/// Returns buffered app output and runtime events since the last call (or
/// since the last reload/restart, whichever is more recent), then clears the
/// buffer. Agents should call this after `reload`, after interaction tools
/// (`perform_tap`, `perform_set_text`, etc.), and after `run_app` to see
/// what the app has printed and whether any errors occurred.
///
/// ## Buffer contents
///
/// The buffer accumulates the following in order of occurrence:
///
/// - **App stdout** — anything the app prints via `print()` or `debugPrint()`,
///   prefixed `[app]`. Non-`flutter:` stdout (e.g. from native code) is
///   prefixed `[stdout]`.
/// - **Flutter errors** — uncaught framework errors with a one-line summary
///   and widget ID, prefixed `[flutter.error]`. Widget IDs can be passed
///   directly to `inspect_layout`.
/// - **Route changes** — navigation events from the slipstream_agent companion,
///   prefixed `[route]`. Only present when the companion is installed with a
///   router adapter.
/// - **Window resize** — logical size changes, prefixed `[window]`. Only
///   present when the companion is installed.
///
/// ## Reset behaviour
///
/// The buffer is cleared:
/// - After each `get_output` call (this call).
/// - On hot reload and hot restart.
/// - On `run_app` (new session).
///
/// ## Example output
///
/// ```
/// [app] Loading podcast feed…
/// [app] Loaded 42 episodes.
/// [flutter.error] RenderFlex overflowed by 32px (widget id: inspector-12)
/// [route] /podcast/abc123
/// ```
///
/// An empty result means no output has been produced since the last reset.
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
      if (lines.isNotEmpty) {
        msg = lines.length == 1 ? '1 line' : '${lines.length} lines';
        final errors =
            lines.where((line) => line.startsWith('[flutter.error]')).length;
        if (errors != 0) {
          final errDesc = errors == 1 ? '1 error' : '$errors errors';
          msg = '$msg, $errDesc';
        }
      }

      extensions.slipstreamLog('get output', kind: 'read', details: msg);
    }

    return CallToolResult(content: [TextContent(text: text)]);
  }
}
