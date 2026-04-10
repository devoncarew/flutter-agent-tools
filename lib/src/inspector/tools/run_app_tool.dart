import 'package:dart_mcp/server.dart';

import '../app_session.dart';
import '../tool_context.dart';

/// Implements the `run_app` MCP tool.
///
/// Builds and launches a Flutter app, returning a session ID for use with
/// all other inspector tools.
class RunAppTool extends InspectorTool {
  RunAppTool({
    required this.sessionIdGenerator,
    required this.registerSession,
    required this.eventListener,
  });

  /// Called to generate a unique session ID for the new session.
  final String Function() sessionIdGenerator;

  /// Called to register a new [AppSession] under [sessionId].
  final void Function(String sessionId, AppSession session) registerSession;

  /// Called to forward daemon events from the session to the server.
  final void Function(String sessionId, DaemonEvent event) eventListener;

  @override
  final Tool definition = Tool(
    name: 'run_app',
    description:
        'Builds and launches the Flutter app. Returns a session ID required '
        'by all other tools. Call this first before inspecting, '
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
    context.validateParams(request, definition.inputSchema.required!);

    final Map<String, dynamic> args = request.arguments!;
    final String workingDirectory = args['working_directory'] as String;
    final String? device = args['device'] as String?;
    final String? target = args['target'] as String?;

    final String sessionId = sessionIdGenerator();

    final AppSession session;
    try {
      session = await AppSession.start(
        workingDirectory: workingDirectory,
        eventListener: (event) => eventListener(sessionId, event),
        deviceId: device,
        target: target,
        debugLog: (message) => context.log(LoggingLevel.info, message),
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
