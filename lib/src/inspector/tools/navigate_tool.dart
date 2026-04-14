import 'package:dart_mcp/server.dart';
import 'package:vm_service/vm_service.dart' show RPCError;

import '../tool_context.dart';

/// Implements the `navigate` MCP tool.
///
/// Navigates the app to a route path via the slipstream_agent routing adapter.
/// Requires the slipstream_agent companion package with a router registered:
///
/// ```dart
/// SlipstreamAgent.init(router: GoRouterAdapter(appRouter));
/// ```
///
/// When the companion is not installed, returns an actionable error.
class NavigateTool extends InspectorTool {
  @override
  final Tool definition = Tool(
    name: 'navigate',
    description:
        'Navigates the app to a route path. Requires the slipstream_agent '
        'companion package with a router adapter registered via '
        'SlipstreamAgent.init(router: GoRouterAdapter(appRouter)).\n\n'
        'Supports any routing library for which an adapter exists: GoRouter, '
        'AutoRouter, Beamer, or a custom adapter. Use get_route first to see '
        'the current path and understand the app\'s route structure.\n\n'
        'Example path: "/podcast/123".',
    inputSchema: Schema.object(
      properties: {
        'path': Schema.string(
          description:
              'The route path to navigate to. Must start with "/". '
              'Example: "/podcast/123".',
        ),
      },
      required: ['path'],
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

    if (!session.hasCompanion) {
      return CallToolResult(
        isError: true,
        content: [
          TextContent(
            text:
                'navigate: the slipstream_agent companion package is not '
                'installed in this app.\n\n'
                'Add it as a dependency and register a router adapter:\n\n'
                '  dependencies:\n'
                '    slipstream_agent: ^0.1.0\n\n'
                'Then in main():\n\n'
                '  if (kDebugMode) {\n'
                '    SlipstreamAgent.init(router: GoRouterAdapter(appRouter));\n'
                '  }',
          ),
        ],
      );
    }

    final String path = request.arguments!['path'] as String;
    if (!path.startsWith('/')) {
      return CallToolResult(
        isError: true,
        content: [TextContent(text: 'navigate: path must start with "/".')],
      );
    }

    try {
      final result = await session.serviceExtensions!.slipstreamNavigate(path);
      if (!result.ok) {
        return CallToolResult(
          isError: true,
          content: [TextContent(text: result.error ?? 'navigate failed')],
        );
      }
      return CallToolResult(content: [TextContent(text: 'Navigated to $path')]);
    } on RPCError catch (e) {
      return context.rpcError(e);
    }
  }
}
