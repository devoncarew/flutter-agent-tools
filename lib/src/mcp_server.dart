import 'dart:async';
import 'dart:math';

import 'package:dart_mcp/server.dart';
import 'package:unique_names_generator/unique_names_generator.dart';

import 'flutter_run_session.dart';

// TODO: We'll likely need to listen to the vm service protocol event
// 'Flutter.Error' to get structured framework / layout errors.

/// The MCP server for flutter-agent-tools.
base class FlutterAgentServer extends MCPServer
    with ToolsSupport, LoggingSupport {
  FlutterAgentServer(super.channel)
    : super.fromStreamChannel(
        implementation: Implementation(
          name: 'flutter-agent-tools',
          version: '0.1.0',
        ),
        instructions:
            'Tools for AI agents working on Dart and Flutter projects.',
      ) {
    loggingLevel = LoggingLevel.info;

    registerTool(flutterLaunchAppTool, _flutterLaunchApp);
    registerTool(flutterPerformReloadTool, _flutterPerformReload);
    registerTool(flutterCloseAppTool, _flutterCloseApp);
    registerTool(flutterDebugPaintTool, _flutterDebugPaint);
  }

  final Map<String, FlutterRunSession> _sessions = {};
  final Map<String, StreamSubscription<FlutterEvent>> _subscriptions = {};

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

  final Tool flutterLaunchAppTool = Tool(
    name: 'flutter_launch_app',
    description:
        'Builds and launches the Flutter app, returning a session ID for use '
        'with subsequent flutter_* tools.',
    inputSchema: Schema.object(
      properties: {
        'target': Schema.string(
          description:
              'The main entry point to launch (e.g. lib/main.dart). '
              'Defaults to the project default.',
        ),
        'device': Schema.string(
          description:
              'The target device ID. Defaults to the first available device.',
        ),
        'working_directory': Schema.string(
          description: 'The Flutter project directory to launch.',
        ),
      },
      required: ['working_directory'],
    ),
  );

  Future<CallToolResult> _flutterLaunchApp(CallToolRequest request) async {
    final Map<String, dynamic> args = request.arguments!;
    final String workingDirectory = args['working_directory'] as String;
    final String? device = args['device'] as String?;
    final String? target = args['target'] as String?;

    final String sessionId = _newSessionId();

    final FlutterRunSession session = await FlutterRunSession.start(
      workingDirectory: workingDirectory,
      eventListener: (event) => _handleEvent(sessionId, event),
      deviceId: device,
      target: target,
    );

    _sessions[sessionId] = session;

    return CallToolResult(
      content: [TextContent(text: 'Launched. Session ID: $sessionId')],
    );
  }

  static const String _loggerId = 'flutter_agent_tools';

  void _handleEvent(String sessionId, FlutterEvent event) {
    if (event.event == 'app.stop') {
      _releaseSession(sessionId);

      this.log(
        LoggingLevel.info,
        '[$sessionId] App stopped; session released.',
        logger: _loggerId,
      );

      return;
    }

    // TODO: test log messages we get for sterr
    // TODO: test log messages we get for exceptions

    final (LoggingLevel? level, String? message) = _convertToLog(event);
    if (level != null && message != null) {
      if (event.event == 'app.log') {
        // We special case stdio output a bit.
        const appOutputPrefix = 'flutter: ';

        if (message.startsWith(appOutputPrefix)) {
          final msg = message.substring(appOutputPrefix.length);
          this.log(level, '[app] $msg', logger: _loggerId);
        } else {
          // It's system output.
          this.log(level, '[system] $message', logger: _loggerId);
        }
      } else {
        this.log(level, '[${event.event}] $message', logger: _loggerId);
      }
    }
  }

  void debugLog(String message) {
    this.log(LoggingLevel.info, '[debug] $message', logger: _loggerId);
  }

  void _releaseSession(String sessionId) {
    _sessions.remove(sessionId);
    _subscriptions.remove(sessionId)?.cancel();
  }

  final Tool flutterCloseAppTool = Tool(
    name: 'flutter_close_app',
    description: 'Stops a running Flutter app and releases its session.',
    inputSchema: Schema.object(
      properties: {
        'session_id': Schema.string(
          description: 'The session ID returned by flutter_launch_app.',
        ),
      },
      required: ['session_id'],
    ),
  );

  final Tool flutterPerformReloadTool = Tool(
    name: 'flutter_perform_reload',
    description:
        'Hot reloads or hot restarts a running Flutter app. '
        'Prefer hot reload for iterative changes; use hot restart when state '
        'needs to be fully reset.',
    inputSchema: Schema.object(
      properties: {
        'session_id': Schema.string(
          description: 'The session ID returned by flutter_launch_app.',
        ),
        'full_restart': Schema.bool(
          description:
              'If true, performs a hot restart instead of a hot reload. '
              'Defaults to false.',
        ),
      },
      required: ['session_id'],
    ),
  );

  Future<CallToolResult> _flutterPerformReload(CallToolRequest request) async {
    final String sessionId = request.arguments!['session_id'] as String;
    final FlutterRunSession? session = _sessions[sessionId];

    if (session == null) {
      return CallToolResult(
        isError: true,
        content: [TextContent(text: 'No session found for ID: $sessionId')],
      );
    }

    final bool fullRestart =
        request.arguments!['full_restart'] as bool? ?? false;
    await session.restart(fullRestart: fullRestart);

    final String action = fullRestart ? 'Hot restart' : 'Hot reload';
    return CallToolResult(content: [TextContent(text: '$action complete.')]);
  }

  Future<CallToolResult> _flutterCloseApp(CallToolRequest request) async {
    final String sessionId = request.arguments!['session_id'] as String;
    final FlutterRunSession? session = _sessions.remove(sessionId);

    if (session == null) {
      return CallToolResult(
        isError: true,
        content: [TextContent(text: 'No session found for ID: $sessionId')],
      );
    }

    _releaseSession(sessionId);

    // We don't await this call.
    session.stop();

    return CallToolResult(content: [TextContent(text: 'App stopped.')]);
  }

  final Tool flutterDebugPaintTool = Tool(
    name: 'flutter_debug_paint',
    description:
        'Gets or sets the debug paint overlay for a running Flutter app. '
        'Debug paint draws layout debug lines over the UI. '
        'Omit "enabled" to read the current value.',
    inputSchema: Schema.object(
      properties: {
        'session_id': Schema.string(
          description: 'The session ID returned by flutter_launch_app.',
        ),
        'enabled': Schema.bool(
          description: 'Enable or disable debug paint. Omit to read.',
        ),
      },
      required: ['session_id'],
    ),
  );

  Future<CallToolResult> _flutterDebugPaint(CallToolRequest request) async {
    final String sessionId = request.arguments!['session_id'] as String;
    final FlutterRunSession? session = _sessions[sessionId];

    if (session == null) {
      return CallToolResult(
        isError: true,
        content: [TextContent(text: 'No session found for ID: $sessionId')],
      );
    }

    final bool? enabled = request.arguments!['enabled'] as bool?;
    if (enabled == null) {
      final bool current = await session.getDebugPaint();
      return CallToolResult(
        content: [
          TextContent(
            text: 'Debug paint is ${current ? 'enabled' : 'disabled'}.',
          ),
        ],
      );
    } else {
      await session.setDebugPaint(enabled);
      return CallToolResult(
        content: [
          TextContent(text: 'Debug paint ${enabled ? 'enabled' : 'disabled'}.'),
        ],
      );
    }
  }

  (LoggingLevel?, String?) _convertToLog(FlutterEvent event) {
    final Map<String, dynamic> params = event.params;

    // By default, flatten the map.
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
          // The `progressId` field identifies the app.progress type.
          switch (params['progressId']) {
            case 'devFS.update':
              {
                // Filter all app.progress / devFS.update events.
                return (null, null);
              }
            case 'hot.reload':
              {
                // We get a start and a stop event; filter the first and promote
                // the second.
                if (params['finished'] == true) {
                  return (LoggingLevel.notice, 'Hot reload finished.');
                } else {
                  return (null, null);
                }
              }
            case 'hot.restart':
              {
                // We get a start and a stop event; filter the first and promote
                // the second.
                if (params['finished'] == true) {
                  return (LoggingLevel.notice, 'Hot restart finished.');
                } else {
                  return (null, null);
                }
              }
          }
        }
    }

    return (LoggingLevel.info, message);
  }
}
