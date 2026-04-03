import 'dart:async';
import 'dart:math';

import 'package:dart_mcp/server.dart';
import 'package:flutter_daemon/flutter_daemon.dart';

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
  }

  final _sessions = <String, FlutterApplication>{};
  final _random = Random();

  String _newSessionId() => List.generate(
    8,
    (_) => _random.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();

  final echoTool = Tool(
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

  final flutterLaunchAppTool = Tool(
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

    final daemon = FlutterDaemon();
    final application = await daemon.run(
      arguments: arguments,
      workingDirectory: workingDirectory,
    );

    final sessionId = _newSessionId();
    _sessions[sessionId] = application;

    return CallToolResult(
      content: [TextContent(text: 'Launched. Session ID: $sessionId')],
    );
  }
}
