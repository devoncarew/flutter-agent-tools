import 'package:dart_mcp/server.dart';

import '../flutter_run_session.dart';
import '../tool_context.dart';

/// Implements the `flutter_launch_app` MCP tool.
///
/// Builds and launches a Flutter app, returning a session ID for use with
/// all other flutter_* tools.
class FlutterLaunchAppTool extends FlutterTool {
  FlutterLaunchAppTool({
    required this.newSessionId,
    required this.registerSession,
    required this.eventListener,
    required this.debugLog,
  });

  /// Called to generate a unique session ID for the new session.
  final String Function() newSessionId;

  /// Called to register a new [FlutterRunSession] under [sessionId].
  final void Function(String sessionId, FlutterRunSession session)
  registerSession;

  /// Called to forward daemon events from the session to the server.
  final void Function(String sessionId, DaemonEvent event) eventListener;

  /// Called to emit debug log messages.
  final void Function(String message) debugLog;

  @override
  final Tool definition = Tool(
    name: 'flutter_launch_app',
    description:
        'Builds and launches the Flutter app. Returns a session ID required '
        'by all other flutter_* tools. Call this first before inspecting, '
        'screenshotting, or evaluating. Flutter.Error events from the running '
        'app are automatically forwarded as MCP log warnings — no polling needed.',
    inputSchema: Schema.object(
      properties: {
        'working_directory': Schema.string(
          description: 'The Flutter project directory to launch.',
        ),
        'target': Schema.string(
          description:
              'The main entry point to launch (e.g. lib/main.dart). '
              'Defaults to the project default.',
        ),
        'device': Schema.string(
          description:
              'Optional device ID override. When omitted, auto-selects the '
              'best available device (prefers desktop for fast builds). Only '
              'pass this if the user requests a specific device.',
        ),
      },
      required: ['working_directory'],
    ),
  );

  @override
  Future<CallToolResult> handle(
    CallToolRequest request,
    ToolContext context,
  ) async {
    final Map<String, dynamic> args = request.arguments!;
    final String workingDirectory = args['working_directory'] as String;
    final String? device = args['device'] as String?;
    final String? target = args['target'] as String?;

    final String sessionId = newSessionId();

    final FlutterRunSession session;
    try {
      session = await FlutterRunSession.start(
        workingDirectory: workingDirectory,
        eventListener: (event) => eventListener(sessionId, event),
        deviceId: device,
        target: target,
        debugLogger: debugLog,
      );
    } on DaemonException catch (e) {
      return CallToolResult(
        isError: true,
        content: [TextContent(text: e.message)],
      );
    }

    registerSession(sessionId, session);

    final String deviceInfo =
        session.deviceId != null ? 'Device ID: ${session.deviceId}, ' : '';
    return CallToolResult(
      content: [
        TextContent(text: 'Launched. ${deviceInfo}Session ID: $sessionId'),
      ],
    );
  }
}
