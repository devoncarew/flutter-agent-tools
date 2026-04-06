import 'dart:async';
import 'dart:math';

import 'package:dart_mcp/server.dart';
import 'package:unique_names_generator/unique_names_generator.dart';

import 'flutter_run_session.dart';
import 'tool_context.dart';
import 'tools/flutter_close_app.dart';
import 'tools/flutter_evaluate.dart';
import 'tools/flutter_inspect_layout.dart';
import 'tools/flutter_launch_app.dart';
import 'tools/flutter_query_ui.dart';
import 'tools/flutter_reload.dart';
import 'tools/flutter_take_screenshot.dart';

/// The MCP server for flutter-agent-tools.
///
/// Owns the session map and event-to-log translation. Tool implementations
/// live in lib/src/tools/ and are decoupled from this class via [ToolContext].
base class FlutterAgentServer extends MCPServer
    with ToolsSupport, LoggingSupport {
  FlutterAgentServer(super.channel)
    : super.fromStreamChannel(
        implementation: Implementation(
          name: 'flutter-agent-tools',
          version: '0.1.0',
        ),
        instructions: '''
Tools for AI agents working on Dart and Flutter projects.

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
- flutter_query_ui mode=route shows the current navigator stack with screen widget names and source locations. Use this to confirm which screen is active before inspecting or editing.

Flutter.Error events are forwarded automatically as MCP log warnings — no polling needed. They include widget IDs for use with flutter_inspect_layout.''',
      ) {
    loggingLevel = LoggingLevel.info;

    _registerTools();
  }

  final Map<String, FlutterRunSession> _sessions = {};
  final Map<String, StreamSubscription<DaemonEvent>> _subscriptions = {};

  late final ToolContext _context = ToolContext(
    sessions: _sessions,
    log: (level, message) => this.log(level, message, logger: _loggerId),
  );

  void _registerTools() {
    void register(FlutterTool tool) {
      registerTool(tool.definition, (req) => tool.handle(req, _context));
    }

    register(FlutterLaunchAppTool(
      newSessionId: _newSessionId,
      registerSession: (id, session) => _sessions[id] = session,
      eventListener: _handleEvent,
      debugLog: debugLog,
    ));
    register(FlutterReloadTool());
    register(FlutterTakeScreenshotTool());
    register(FlutterInspectLayoutTool());
    register(FlutterEvaluateTool());
    register(FlutterQueryUiTool());
    register(FlutterCloseAppTool(
      cancelSubscription: (id) => _subscriptions.remove(id)?.cancel(),
    ));
  }

  @override
  Future<void> shutdown() async {
    await Future.wait(_subscriptions.values.map((s) => s.cancel()));
    _subscriptions.clear();
    await Future.wait(_sessions.values.map((session) => session.stop()));
    _sessions.clear();
    await super.shutdown();
  }

  final Random _random = Random();
  final UniqueNamesGenerator _nameGenerator = UniqueNamesGenerator(
    config: Config(
      length: 2,
      dictionaries: [adjectives, animals],
      separator: '_',
    ),
  );

  String _newSessionId() {
    final String suffix =
        List.generate(
          2,
          (_) => _random.nextInt(256).toRadixString(16).padLeft(2, '0'),
        ).join();
    return [_nameGenerator.generate(), suffix].join('_');
  }

  static const String _loggerId = 'flutter_agent_tools';

  void _handleEvent(String sessionId, DaemonEvent event) {
    if (event.event == 'app.stop') {
      _sessions.remove(sessionId);
      _subscriptions.remove(sessionId)?.cancel();

      this.log(
        LoggingLevel.info,
        '[$sessionId] App stopped; session released.',
        logger: _loggerId,
      );
      return;
    } else if (event.event == 'flutter.error') {
      final String summary =
          event.params['summary'] as String? ?? 'Unknown Flutter error';
      this.log(
        LoggingLevel.warning,
        '[flutter.error] $summary',
        logger: _loggerId,
      );
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
      this.log(
        LoggingLevel.info,
        '[flutter.navigation] $routeDesc (use flutter_query_ui mode=route to see current stack)',
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
          this.log(item.$1, '[app] $msg', logger: _loggerId);
        } else {
          this.log(item.$1, '[stdout] ${item.$2}', logger: _loggerId);
        }
      } else {
        this.log(item.$1, '[${event.event}] ${item.$2}', logger: _loggerId);
      }
    }
  }

  void debugLog(String message) {
    this.log(LoggingLevel.info, '[debug] $message', logger: _loggerId);
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
