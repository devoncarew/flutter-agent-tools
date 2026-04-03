import 'dart:async';
import 'dart:math';

import 'package:dart_mcp/server.dart';
import 'package:flutter_daemon/flutter_daemon.dart';
import 'package:unique_names_generator/unique_names_generator.dart';

// TODO: We want to switch from using the persistent daemon process to using
// `flutter run --machine`. This supports a subset of the daemon protocol -
// also json over stdio - and was designed for this run-one-app use case.
// This means we'll stop using package:flutter_daemon (and will likely roll our
// own, miniimal library). The protocol is documented at:
// https://github.com/flutter/flutter/blob/master/packages/flutter_tools/doc/daemon.md

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
  }

  FlutterDaemon? _daemon;
  FlutterDaemon get _daemonInstance => _daemon ??= FlutterDaemon();

  final Map<String, FlutterApplication> _sessions = {};
  final Map<String, StreamSubscription<FlutterDaemonEvent>> _subscriptions = {};

  @override
  Future<void> shutdown() async {
    await Future.wait(_subscriptions.values.map((s) => s.cancel()));
    _subscriptions.clear();
    await Future.wait(_sessions.values.map((app) => app.stop()));
    _sessions.clear();
    await _daemon?.dispose();
    await super.shutdown();
  }

  final Random _random = Random();
  final UniqueNamesGenerator _nameGenerator = UniqueNamesGenerator(
    config: Config(
      length: 2,
      dictionaries: [adjectives, animals],
      separator: '-',
    ),
  );

  String _newSessionId() {
    final suffix =
        List.generate(
          2,
          (_) => _random.nextInt(256).toRadixString(16).padLeft(2, '0'),
        ).join();

    return [_nameGenerator.generate(), suffix].join('-');
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
    final args = request.arguments!;
    final workingDirectory = args['working_directory'] as String;
    final device = args['device'] as String?;
    final target = args['target'] as String?;

    final arguments = [
      if (device != null) ...['--device-id', device],
      if (target != null) ...['--target', target],
    ];

    final application = await _daemonInstance.run(
      arguments: arguments,
      workingDirectory: workingDirectory,
    );

    final sessionId = _newSessionId();

    _sessions[sessionId] = application;
    _watchSession(sessionId, application);

    return CallToolResult(
      content: [TextContent(text: 'Launched. Session ID: $sessionId')],
    );
  }

  void _watchSession(String sessionId, FlutterApplication application) {
    const loggerId = 'flutter_agent_tools';

    _subscriptions[sessionId] = application.events.listen((event) {
      if (event.event == 'app.stop') {
        _releaseSession(sessionId);

        this.log(
          LoggingLevel.info,
          '[$sessionId] App stopped; session released.',
          logger: loggerId,
        );
      } else {
        final (level, message) = _convertToLog(event);
        if (level != null) {
          this.log(
            level,
            '[$sessionId] ${event.event}: $message',
            logger: loggerId,
          );
        }
      }
    });
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
    final sessionId = request.arguments!['session_id'] as String;
    final application = _sessions[sessionId];

    if (application == null) {
      return CallToolResult(
        isError: true,
        content: [TextContent(text: 'No session found for ID: $sessionId')],
      );
    }

    final fullRestart = request.arguments!['full_restart'] as bool? ?? false;
    await application.restart(fullRestart: fullRestart);

    final action = fullRestart ? 'Hot restart' : 'Hot reload';
    return CallToolResult(content: [TextContent(text: '$action complete.')]);
  }

  Future<CallToolResult> _flutterCloseApp(CallToolRequest request) async {
    final sessionId = request.arguments!['session_id'] as String;
    final application = _sessions.remove(sessionId);

    if (application == null) {
      return CallToolResult(
        isError: true,
        content: [TextContent(text: 'No session found for ID: $sessionId')],
      );
    }

    _releaseSession(sessionId);

    // We don't await this call.
    application.stop();

    return CallToolResult(content: [TextContent(text: 'App stopped.')]);
  }

  (LoggingLevel?, String?) _convertToLog(FlutterDaemonEvent event) {
    final params = event.params;

    // By default, flatten the map.
    var message = params.keys
        .map((k) {
          final v = params[k];
          return '$k: ${v is String ? "'$v'" : v}';
        })
        .join(', ');

    switch (event.event) {
      case 'app.progress':
        {
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
          }
        }
    }

    return (LoggingLevel.info, message);
  }
}
