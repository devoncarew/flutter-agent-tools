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

    test('returns a message when no app is running', () async {
      final result = await env.serverConnection.callTool(
        CallToolRequest(name: 'close_app', arguments: {}),
      );

      expect(result.isError, isNot(true));
      expect((result.content.first as TextContent).text, 'No app was running.');
    });
  });
}
