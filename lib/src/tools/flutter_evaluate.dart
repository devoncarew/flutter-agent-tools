import 'package:dart_mcp/server.dart';
import 'package:vm_service/vm_service.dart' show RPCError;

import '../tool_context.dart';

/// Implements the `flutter_evaluate` MCP tool.
///
/// Evaluates a Dart expression on the running app's main isolate and returns
/// the result as a string.
class FlutterEvaluateTool extends FlutterTool {
  @override
  final Tool definition = Tool(
    name: 'flutter_evaluate',
    description:
        'Evaluates a Dart expression on the running app\'s main isolate and '
        'returns the result as a string. Use for binding-layer and '
        'platform-layer state not visible in the widget tree: FlutterView '
        'properties (physicalSize, devicePixelRatio), MediaQueryData, '
        'or any runtime value. Runs in the root library scope, so top-level '
        'declarations and globals are in scope. Example: '
        '"WidgetsBinding.instance.platformDispatcher.views.first.devicePixelRatio.toString()"',
    inputSchema: Schema.object(
      properties: {
        'session_id': Schema.string(
          description: 'The session ID returned by flutter_launch_app.',
        ),
        'expression': Schema.string(
          description:
              'The Dart expression to evaluate. Must produce a value with a '
              'useful toString(). Example: '
              '"WidgetsBinding.instance.platformDispatcher'
              '.views.first.devicePixelRatio.toString()"',
        ),
      },
      required: ['session_id', 'expression'],
    ),
  );

  @override
  Future<CallToolResult> handle(
    CallToolRequest request,
    ToolContext context,
  ) async {
    final String? sessionId = request.arguments!['session_id'] as String?;
    final session = context.session(sessionId);
    if (sessionId == null || session == null) {
      return context.unknownSession(sessionId);
    }

    final String expression = request.arguments!['expression'] as String;
    try {
      final String result = await session.serviceExtensions!.evaluate(
        expression,
      );
      return CallToolResult(content: [TextContent(text: result)]);
    } on RPCError catch (e) {
      return context.rpcError(e);
    }
  }
}
