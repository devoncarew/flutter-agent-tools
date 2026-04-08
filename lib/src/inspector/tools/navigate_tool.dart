import 'package:dart_mcp/server.dart';
import 'package:vm_service/vm_service.dart' show RPCError;

import '../tool_context.dart';

/// Implements the `navigate` MCP tool.
///
/// Navigates to a go_router path by calling `GoRouter.go()` on the app's
/// router instance via VM service evaluate.
class NavigateTool extends InspectorTool {
  @override
  final Tool definition = Tool(
    name: 'navigate',
    description:
        'Navigates the app to a go_router path. Calls GoRouter.go(path) on '
        'the running app — no app modification required. '
        'Only works with apps that use go_router. '
        'Use get_route first to see the current path and understand '
        'the app\'s route structure. '
        'Example path: "/podcast/123".',
    inputSchema: Schema.object(
      properties: {
        'session_id': Schema.string(
          description: 'The session ID returned by run_app.',
        ),
        'path': Schema.string(
          description:
              'The go_router path to navigate to. Must start with "/". '
              'Example: "/podcast/123".',
        ),
      },
      required: ['session_id', 'path'],
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

    final String path = request.arguments!['path'] as String;
    if (!path.startsWith('/')) {
      return CallToolResult(
        isError: true,
        content: [TextContent(text: 'navigate: path must start with "/".')],
      );
    }

    try {
      final extensions = session.serviceExtensions!;
      final String? vmId = await extensions.resolveGoRouterVmId();
      if (vmId == null) {
        return CallToolResult(
          isError: true,
          content: [
            TextContent(
              text:
                  'navigate: go_router not found in the widget tree. '
                  'This tool only works with apps that use go_router.',
            ),
          ],
        );
      }

      // Escape the path for embedding in a Dart string literal.
      final escapedPath = path.replaceAll("'", "\\'");
      await extensions.evaluateOnObject(
        vmId,
        "widget.goRouter.go('$escapedPath')",
      );

      return CallToolResult(content: [TextContent(text: 'Navigated to $path')]);
    } on RPCError catch (e) {
      return context.rpcError(e);
    }
  }
}
