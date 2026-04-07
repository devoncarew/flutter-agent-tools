import 'package:dart_mcp/server.dart';
import 'package:flutter_agent_tools/inspector_mcp.dart';
import 'package:test/test.dart';

import 'test_utils.dart';

void main() {
  group('flutter_close_app tool', () {
    late TestEnvironment<TestMCPClient, FlutterAgentServer> env;

    setUp(() async {
      env = TestEnvironment(TestMCPClient(), FlutterAgentServer.new);
      await env.initializeServer();
    });

    test('returns an error for an unknown session ID', () async {
      final result = await env.serverConnection.callTool(
        CallToolRequest(
          name: 'flutter_close_app',
          arguments: {'session_id': 'unknown'},
        ),
      );

      expect(result.isError, true);
      expect((result.content.first as TextContent).text, contains('unknown'));
    });
  });
}
