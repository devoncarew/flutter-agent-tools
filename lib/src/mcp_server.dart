import 'dart:async';

import 'package:dart_mcp/server.dart';

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
  }

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
}
