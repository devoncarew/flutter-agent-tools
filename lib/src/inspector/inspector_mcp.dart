import 'dart:async';

import 'package:dart_mcp/server.dart';

import '../common.dart';
import 'app_session.dart';
import 'tool_context.dart';
import 'tools/close_app_tool.dart';
import 'tools/evaluate_tool.dart';
import 'tools/get_output_tool.dart';
import 'tools/get_route_tool.dart';
import 'tools/get_semantics_tool.dart';
import 'tools/inspect_layout_tool.dart';
import 'tools/navigate_tool.dart';
import 'tools/perform_scroll_tool.dart';
import 'tools/perform_scroll_until_visible_tool.dart';
import 'tools/perform_semantic_action_tool.dart';
import 'tools/perform_set_text_tool.dart';
import 'tools/perform_tap_tool.dart';
import 'tools/reload_tool.dart';
import 'tools/run_app_tool.dart';
import 'tools/take_screenshot_tool.dart';

/// The MCP server for the runtime inspector feature.
///
/// Owns the session and event-to-log translation. Tool implementations
/// live in lib/src/tools/ and are decoupled from this class via [ToolContext].
base class InspectorMCPServer extends MCPServer
    with ToolsSupport, LoggingSupport {
  late final ToolContext _context = ToolContext(log: _serverLog);

  /// Diagnostic log — sent as an MCP notification (not buffered for agents).
  /// Use for internal server events; not expected to reach the model context.
  void _serverLog(String message) {
    log(LoggingLevel.info, message, logger: 'slipstream');
  }

  InspectorMCPServer(super.channel)
    : super.fromStreamChannel(
        implementation: Implementation(
          name: 'inspector',
          version: packageVersion,
        ),
        instructions: '''
Tools for launching, inspecting, and interacting with a running Flutter app.

Session lifecycle: call run_app first to launch the app; call close_app when done. Only one app session can be active at a time — calling run_app while an app is already running will stop the previous app first.

Recommended workflow for UI changes:
1. Edit Dart source files.
2. reload — applies changes without losing app state. Use full_restart: true only when state must reset (e.g. initState changes).
3. screenshot — visually confirm the change. Do this proactively; don't assume the edit was correct.
4. If the screenshot reveals a problem, use inspect_layout (for sizing/overflow issues) or evaluate (for runtime state).

Debugging layout issues:
- inspect_layout with no widget_id starts from the root.
- Widget IDs appear in flutter.error log output — use them to jump directly to the failing widget.
- Increase subtree_depth to see deeper into the tree.

Orientation:
- get_route shows the current navigator stack with screen widget names and source locations. Use this to confirm which screen is active before inspecting or editing.
- get_semantics lists visible, interactive nodes with their IDs. Pass node IDs directly to 'perform_semantic_action'.
- If the app has slipstream_agent installed, use 'perform_tap', 'perform_set_text', 'perform_scroll', or 'perform_scroll_until_visible' instead of 'perform_semantic_action' — these support byKey/byType/byText finders and do not require semantics annotations.

After reload or any interaction tool, call get_output to see app stdout, Flutter errors, and route changes since the last call.''',
      ) {
    loggingLevel = LoggingLevel.info;

    _registerTools();
  }

  void _registerTools() {
    void register(InspectorTool tool) {
      // Disable dart_mcp's auto-validation so our handlers can apply lenient
      // coercions (e.g. accept "5" for an int param) and return more
      // informative error messages than the generic schema error.
      registerTool(tool.definition, (req) async {
        try {
          return await tool.handle(req, _context);
        } on ToolException catch (e) {
          return CallToolResult(
            content: [TextContent(text: e.message)],
            isError: true,
          );
        }
      }, validateArguments: false);
    }

    register(RunAppTool(eventListener: _handleAppEvent));
    register(ReloadTool());
    register(GetOutputTool());
    register(TakeScreenshotTool());
    register(InspectLayoutTool());
    register(EvaluateTool());
    register(GetRouteTool());
    register(NavigateTool());
    register(PerformTapTool());
    register(PerformSetTextTool());
    register(PerformScrollTool());
    register(PerformScrollUntilVisibleTool());
    register(GetSemanticsTool());
    register(PerformSemanticActionTool());
    register(CloseAppTool());
  }

  @override
  Future<void> shutdown() async {
    final session = _context.removeSession();
    if (session != null) await session.stop();

    await super.shutdown();
  }

  void _handleAppEvent(AppEvent event) {
    if (event.event == 'app.stop') {
      // This is informational; our session end signal is process exit.
      _serverLog('App stopped.');
      return;
    }

    final session = _context.activeSession;

    if (event.event == 'slipstream.windowResized') {
      final p = event.params;
      final double w = (p['logicalWidth'] as num?)?.toDouble() ?? 0;
      final double h = (p['logicalHeight'] as num?)?.toDouble() ?? 0;
      final double dpr = (p['devicePixelRatio'] as num?)?.toDouble() ?? 1;
      _serverLog(
        '[window] ${w.toStringAsFixed(0)}×${h.toStringAsFixed(0)} logical px '
        '(dpr=${dpr.toStringAsFixed(1)})',
      );
      return;
    } else if (event.event == 'slipstream.routeChanged') {
      final String path = event.params['path'] as String? ?? '?';
      session?.addOutput('route', path);
      _serverLog('[route] $path');
      return;
    } else if (event.event == 'flutter.error') {
      final String summary =
          event.params['summary'] as String? ?? 'Unknown Flutter error';
      session?.addOutput('flutter.error', summary);
      _serverLog('[flutter.error] $summary');
      return;
    }

    final item = _convertToLog(event);
    if (item != null) {
      if (event.event == 'app.log') {
        const appOutputPrefix = 'flutter: ';
        final String line;
        if (item.startsWith(appOutputPrefix)) {
          line = item.substring(appOutputPrefix.length);
          session?.addOutput('app', line);
          _serverLog('[app] $line');
        } else {
          line = item;
          session?.addOutput('stdout', line);
          _serverLog('[stdout] $line');
        }
      } else {
        _serverLog('[${event.event}] $item');
      }
    }
  }

  String? _convertToLog(AppEvent event) {
    final Map<String, dynamic> params = event.params;

    String message = params.keys
        .map((String k) {
          final Object? v = params[k];
          return '$k: ${v is String ? "'$v'" : v}';
        })
        .join(', ');

    switch (event.event) {
      case 'app.log':
        {
          message = params['log'] as String? ?? message;
          return message;
        }
      case 'app.progress':
        {
          switch (params['progressId']) {
            case 'devFS.update':
              return null;
            case 'hot.reload':
              // Filter both start and stop — the agent already sees a stdout
              // message: "[stdout] Reloaded 0 libraries in ..."
              return null;
            case 'hot.restart':
              return null;
          }
        }
    }

    return message;
  }
}
