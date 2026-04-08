import 'dart:async';

import 'package:dart_mcp/server.dart';
import '../version.dart';
import 'utils.dart';

import 'app_session.dart';
import 'tool_context.dart';
import 'tools/close_app_tool.dart';
import 'tools/evaluate_tool.dart';
import 'tools/get_route_tool.dart';
import 'tools/get_semantics_tool.dart';
import 'tools/inject_text_tool.dart';
import 'tools/inspect_layout_tool.dart';
import 'tools/navigate_tool.dart';
import 'tools/launch_app_tool.dart';
import 'tools/reload_tool.dart';
import 'tools/take_screenshot_tool.dart';
import 'tools/tap_tool.dart';

/// The MCP server for the runtime inspector feature.
///
/// Owns the session map and event-to-log translation. Tool implementations
/// live in lib/src/tools/ and are decoupled from this class via [ToolContext].
base class InspectorServer extends MCPServer with ToolsSupport, LoggingSupport {
  static const String _loggerId = 'flutter_agent_tools';

  final Map<String, AppSession> _sessions = {};

  final IdGenerator _idGenerator = IdGenerator();

  late final ToolContext _context = ToolContext(
    sessions: _sessions,
    log: (level, message) => log(level, message, logger: _loggerId),
  );

  InspectorServer(super.channel)
    : super.fromStreamChannel(
        implementation: Implementation(
          name: 'flutter-inspect',
          version: packageVersion,
        ),
        instructions: '''
Tools for for launching, inspecting, and interacting with a running Flutter app.

Session lifecycle: call flutter_launch_app first to get a session_id; pass it to all other tools. Call flutter_close_app when done.

Recommended workflow for UI changes:
1. Edit Dart source files.
2. flutter_reload — applies changes without losing app state. Use full_restart: true only when state must reset (e.g. initState changes).
3. flutter_take_screenshot — visually confirm the change. Do this proactively; don't assume the edit was correct.
4. If the screenshot reveals a problem, use flutter_inspect_layout (for sizing/overflow issues) or flutter_evaluate (for runtime state).

Debugging layout issues:
- flutter_inspect_layout with no widget_id starts from the root.
- Widget IDs appear in flutter.error log events — use them to jump directly to the failing widget.
- Increase subtree_depth to see deeper into the tree.

Orientation:
- flutter_get_route shows the current navigator stack with screen widget names and source locations. Use this to confirm which screen is active before inspecting or editing.
- flutter_get_semantics lists visible, interactive nodes with their IDs. Pass node IDs directly to flutter_tap, flutter_inject_text, and flutter_scroll_to.

Flutter.Error events are forwarded automatically as MCP log warnings — no polling needed. They include widget IDs for use with flutter_inspect_layout.''',
      ) {
    loggingLevel = LoggingLevel.info;

    _registerTools();
  }

  void _registerTools() {
    void register(FlutterTool tool) {
      registerTool(tool.definition, (req) => tool.handle(req, _context));
    }

    register(
      FlutterLaunchAppTool(
        sessionIdGenerator: _idGenerator.createNextId,
        registerSession: (id, session) => _sessions[id] = session,
        eventListener: _handleEvent,
        debugLog: debugLog,
      ),
    );
    register(FlutterReloadTool());
    register(FlutterTakeScreenshotTool());
    register(FlutterInspectLayoutTool());
    register(FlutterEvaluateTool());
    register(FlutterGetRouteTool());
    register(FlutterNavigateTool());
    register(FlutterGetSemanticsTool());
    register(FlutterTapTool());
    register(FlutterInjectTextTool());
    register(FlutterCloseAppTool());
  }

  @override
  Future<void> shutdown() async {
    await Future.wait(_sessions.values.map((session) => session.stop()));
    _sessions.clear();

    await super.shutdown();
  }

  void _handleEvent(String sessionId, DaemonEvent event) {
    if (event.event == 'app.stop') {
      _sessions.remove(sessionId);

      log(
        LoggingLevel.info,
        '[$sessionId] App stopped; session released.',
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
        '[flutter.navigation] $routeDesc (use flutter_get_route to see current stack)',
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

  void debugLog(String message) {
    log(LoggingLevel.info, '[debug] $message', logger: _loggerId);
  }

  (LoggingLevel, String)? _convertToLog(DaemonEvent event) {
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
