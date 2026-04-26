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
    description: 'Evaluates a Dart expression on the running app\'s main '
        'isolate and returns the result as a string. Use for runtime state '
        'not visible in the widget tree: FlutterView properties, '
        'MediaQueryData, controller state, etc. Runs in the root library '
        'scope (main.dart) by default; pass library_uri for a different scope.',
    inputSchema: Schema.object(
      properties: {
        'expression': Schema.string(
          description: 'Dart expression to evaluate. Example: '
              '"WidgetsBinding.instance.platformDispatcher'
              '.views.first.devicePixelRatio.toString()"',
        ),
        'library_uri': Schema.string(
          description: 'Library scope for evaluation. Defaults to main.dart. '
              'Use "package:flutter/src/widgets/widget_inspector.dart" for '
              'RendererBinding, SemanticsNode, CheckedState, and Tristate.',
        ),
      },
      required: ['expression'],
    ),
  );

  @override
  Future<CallToolResult> handle(
    CallToolRequest request,
    ToolContext context,
  ) async {
    context.validateParams(request, definition.inputSchema.required!);

    final session = context.activeSession;
    if (session == null) return context.noActiveSession();

    // Unescape HTML entities that models sometimes introduce when generating
    // expressions containing generic type parameters (e.g. &lt;T&gt; → <T>).
    // This happens because the Anthropic API encodes tool-call content in an
    // XML-like structure, and models trained on that format occasionally
    // HTML-escape angle brackets even inside opaque string arguments.
    // &lt;/&gt; are never valid Dart, so unescaping is always correct here.
    final String expression = (request.arguments!['expression'] as String)
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&amp;', '&');
    final String? libraryUri = request.arguments!['library_uri'] as String?;
    try {
      final extensions = session.serviceExtensions!;
      if (session.hasCompanion) {
        final msg =
            expression.length > 60
                ? '${expression.substring(0, 59)}…'
                : expression;
        extensions.slipstreamLog('evaluate', details: '"$msg"', kind: 'read');
      }
      final String result = await extensions.evaluate(
        expression,
        libraryUri: libraryUri,
      );
      final String text = result.isEmpty ? "''" : result;
      return CallToolResult(content: [TextContent(text: text)]);
    } on RPCError catch (e) {
      return context.rpcError(e);
    }
  }
}
