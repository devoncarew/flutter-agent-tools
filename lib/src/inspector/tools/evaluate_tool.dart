import 'package:dart_mcp/server.dart';
import 'package:vm_service/vm_service.dart' show RPCError;

import '../tool_context.dart';

/// Implements the `evaluate` MCP tool.
///
/// Evaluates a Dart expression on the running app's main isolate and returns
/// the result as a string.
class EvaluateTool extends InspectorTool {
  @override
  final Tool definition = Tool(
    name: 'evaluate',
    description:
        'Evaluates a Dart expression on the running app\'s main isolate and '
        'returns the result as a string. Use for binding-layer and '
        'platform-layer state not visible in the widget tree: FlutterView '
        'properties (physicalSize, devicePixelRatio), MediaQueryData, '
        'or any runtime value. By default runs in the root library scope '
        '(main.dart), so top-level declarations and globals are in scope. '
        'Pass library_uri to evaluate in a different library scope — for '
        'example, "package:flutter/src/widgets/widget_inspector.dart" makes '
        'RendererBinding, SemanticsNode, CheckedState, and Tristate available.',
    inputSchema: Schema.object(
      properties: {
        'session_id': Schema.string(
          description: 'The session ID returned by run_app.',
        ),
        'expression': Schema.string(
          description:
              'The Dart expression to evaluate. Must produce a value with a '
              'useful toString(). Example: '
              '"WidgetsBinding.instance.platformDispatcher'
              '.views.first.devicePixelRatio.toString()"',
        ),
        'library_uri': Schema.string(
          description:
              'Optional. The URI of the library scope in which to evaluate '
              'the expression. Defaults to the app\'s root library (main.dart). '
              'Use "package:flutter/src/widgets/widget_inspector.dart" to '
              'access Flutter rendering and semantics APIs such as '
              'RendererBinding, SemanticsNode, CheckedState, and Tristate.',
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
    final String? libraryUri = request.arguments!['library_uri'] as String?;
    try {
      final String result = await session.serviceExtensions!.evaluate(
        expression,
        libraryUri: libraryUri,
      );
      return CallToolResult(content: [TextContent(text: result)]);
    } on RPCError catch (e) {
      return context.rpcError(e);
    }
  }
}
