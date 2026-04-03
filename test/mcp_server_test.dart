import 'package:dart_mcp/server.dart';
import 'package:flutter_agent_tools/mcp_server.dart';
import 'package:test/test.dart';

import 'test_utils.dart';

void main() {
  group('echo tool', () {
    late TestEnvironment<TestMCPClient, FlutterAgentServer> env;

    setUp(() async {
      env = TestEnvironment(TestMCPClient(), FlutterAgentServer.new);
      await env.initializeServer();
    });

    test('returns input text unchanged', () async {
      final result = await env.serverConnection.callTool(
        CallToolRequest(name: 'echo', arguments: {'text': 'hello'}),
      );

      expect(result.isError, isNot(true));
      expect((result.content.first as TextContent).text, 'hello');
    });
  });
}
