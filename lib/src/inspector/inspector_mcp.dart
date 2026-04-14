import 'dart:async';

import 'package:dart_mcp/server.dart';

import '../common.dart';
import 'app_session.dart';
import 'tool_context.dart';
import 'tools/close_app_tool.dart';
import 'tools/evaluate_tool.dart';
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
  static const String _loggerId = 'flutter_agent_tools';

  late final ToolContext _context = ToolContext(
    log: (level, message) => log(level, message, logger: _loggerId),
  );

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
- Widget IDs appear in flutter.error log events — use them to jump directly to the failing widget.
- Increase subtree_depth to see deeper into the tree.

Orientation:
- get_route shows the current navigator stack with screen widget names and source locations. Use this to confirm which screen is active before inspecting or editing.
- get_semantics lists visible, interactive nodes with their IDs. Pass node IDs directly to 'perform_semantic_action'.
- If the app has slipstream_agent installed, use 'perform_tap', 'perform_set_text', 'perform_scroll', or 'perform_scroll_until_visible' instead of 'perform_semantic_action' — these support byKey/byType/byText finders and do not require semantics annotations.

Flutter.Error events are forwarded automatically as MCP log warnings — no polling needed. They include widget IDs for use with inspect_layout.''',
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

    register(
      RunAppTool(
        registerSession: _registerSession,
        eventListener: _handleEvent,
      ),
    );
    register(ReloadTool());
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

  /// Registers [session] as the active session, stopping any existing one.
  Future<void> _registerSession(AppSession session) async {
    final existing = _context.removeSession();
    if (existing != null) {
      await existing.stop().timeout(
        Duration(milliseconds: 250),
        onTimeout: () => null,
      );
    }
    _context.setSession(session);
  }

  @override
  Future<void> shutdown() async {
    final session = _context.removeSession();
    if (session != null) await session.stop();

    await super.shutdown();
  }

  void _handleEvent(AppEvent event) {
    if (event.event == 'app.stop') {
      _context.removeSession();

      log(
        LoggingLevel.info,
        'App stopped; session released.',
        logger: _loggerId,
      );
      return;
    } else if (event.event == 'slipstream.windowResized') {
      final p = event.params;
      final double w = (p['logicalWidth'] as num?)?.toDouble() ?? 0;
      final double h = (p['logicalHeight'] as num?)?.toDouble() ?? 0;
      final double dpr = (p['devicePixelRatio'] as num?)?.toDouble() ?? 1;
      log(
        LoggingLevel.info,
        '[window] ${w.toStringAsFixed(0)}×${h.toStringAsFixed(0)} logical px '
        '(dpr=${dpr.toStringAsFixed(1)})',
        logger: _loggerId,
      );
      return;
    } else if (event.event == 'flutter.error') {
      final String summary =
          event.params['summary'] as String? ?? 'Unknown Flutter error';
      log(LoggingLevel.warning, '[flutter.error] $summary', logger: _loggerId);
      return;
    } else if (event.event == 'flutter.navigation') {
      // The Flutter.Navigation event is only emitted by the imperative
      // Navigator API (push/pop/replace). go_router's context.go() works
      // declaratively (rebuilds the stack), so navigation events fire on
      // back-navigation (pop) but not on forward navigation (go()).
      //
      // Sample go_router pop event description (path template, not path):
      //   _PageBasedMaterialPageRoute<void>(/podcast/:id)
      final routeDesc = event.params['route'];
      log(
        LoggingLevel.info,
        '[flutter.navigation] $routeDesc (use get_route to see current stack)',
        logger: _loggerId,
      );
      return;
    }

    final item = _convertToLog(event);
    if (item != null) {
      if (event.event == 'app.log') {
        const appOutputPrefix = 'flutter: ';
        if (item.$2.startsWith(appOutputPrefix)) {
          final msg = item.$2.substring(appOutputPrefix.length);
          log(item.$1, '[app] $msg', logger: _loggerId);
        } else {
          log(item.$1, '[stdout] ${item.$2}', logger: _loggerId);
        }
      } else {
        log(item.$1, '[${event.event}] ${item.$2}', logger: _loggerId);
      }
    }
  }

  (LoggingLevel, String)? _convertToLog(AppEvent event) {
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
          final bool isError = params['error'] as bool? ?? false;
          return (isError ? LoggingLevel.warning : LoggingLevel.info, message);
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

    return (LoggingLevel.info, message);
  }
}
