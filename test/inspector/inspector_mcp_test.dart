import 'package:dart_mcp/server.dart';
import 'package:flutter_slipstream/src/inspector/inspector_mcp.dart';
import 'package:test/test.dart';

import '../test_utils.dart';

void main() {
  group('close_app tool', () {
    late TestEnvironment<TestMCPClient, InspectorMCPServer> env;

    setUp(() async {
      env = TestEnvironment(TestMCPClient(), InspectorMCPServer.new);
      await env.initializeServer();
    });

    test('returns an error for an unknown session ID', () async {
      final result = await env.serverConnection.callTool(
        CallToolRequest(
          name: 'close_app',
          arguments: {'session_id': 'unknown'},
        ),
      );

      expect(result.isError, true);
      expect((result.content.first as TextContent).text, contains('unknown'));
    });
  });
}
