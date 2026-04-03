import 'dart:async';
import 'dart:math';

import 'package:dart_mcp/server.dart';
import 'package:flutter_daemon/flutter_daemon.dart';
import 'package:unique_names_generator/unique_names_generator.dart';

/// The MCP server for flutter-agent-tools.
base class FlutterAgentServer extends MCPServer with ToolsSupport {
  FlutterAgentServer(super.channel)
    : super.fromStreamChannel(
        implementation: Implementation(
          name: 'flutter-agent-tools',
          version: '0.1.0',
        ),
        instructions:
            'Tools for AI agents working on Dart and Flutter projects.',
      ) {
    registerTool(echoTool, _echo);
    registerTool(flutterLaunchAppTool, _flutterLaunchApp);
    registerTool(flutterCloseAppTool, _flutterCloseApp);
  }

  FlutterDaemon? _daemon;
  FlutterDaemon get _daemonInstance => _daemon ??= FlutterDaemon();

  final Map<String, FlutterApplication> _sessions = {};

  @override
  Future<void> shutdown() async {
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
          (_) => _random
              .nextInt(256)
              .toRadixString(16)
              .toUpperCase()
              .padLeft(2, '0'),
        ).join();

    return [_nameGenerator.generate(), suffix].join('-');
  }

  final Tool echoTool = Tool(
    name: 'echo',
    description: 'Returns the provided text unchanged.',
    inputSchema: Schema.object(
      properties: {
        'text': Schema.string(description: 'The text to echo back.'),
      },
      required: ['text'],
    ),
  );

  FutureOr<CallToolResult> _echo(CallToolRequest request) {
    final text = request.arguments!['text'] as String;
    return CallToolResult(content: [TextContent(text: text)]);
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

    return CallToolResult(
      content: [TextContent(text: 'Launched. Session ID: $sessionId')],
    );
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

  Future<CallToolResult> _flutterCloseApp(CallToolRequest request) async {
    final sessionId = request.arguments!['session_id'] as String;
    final application = _sessions.remove(sessionId);

    if (application == null) {
      return CallToolResult(
        isError: true,
        content: [TextContent(text: 'No session found for ID: $sessionId')],
      );
    }

    await application.stop();
    return CallToolResult(content: [TextContent(text: 'App stopped.')]);
  }
}
