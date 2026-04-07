// Generates the MCP commands table in README.md.
//
// Run with: dart run tool/generate_readme.dart

import 'dart:async';
import 'dart:io';

import 'package:dart_mcp/client.dart';
import 'package:flutter_agent_tools/inspector_mcp.dart';
import 'package:stream_channel/stream_channel.dart';

const _marker = '<!-- flutter commands -->';

void main() async {
  // Wire up an in-process client/server pair.
  final clientController = StreamController<String>();
  final serverController = StreamController<String>();

  final clientChannel = StreamChannel<String>.withCloseGuarantee(
    serverController.stream,
    clientController.sink,
  );
  final serverChannel = StreamChannel<String>.withCloseGuarantee(
    clientController.stream,
    serverController.sink,
  );

  final server = FlutterAgentServer(serverChannel);
  final client = _ScriptClient();
  final connection = client.connectServer(clientChannel);

  await connection.initialize(
    InitializeRequest(
      protocolVersion: ProtocolVersion.latestSupported,
      capabilities: client.capabilities,
      clientInfo: client.implementation,
    ),
  );
  connection.notifyInitialized(InitializedNotification());
  await server.initialized;

  final toolsResult = await connection.listTools(ListToolsRequest());

  await client.shutdown();
  await server.shutdown();

  // Build the markdown table.
  final buf = StringBuffer();
  buf.writeln('<!-- prettier-ignore-start -->');
  buf.writeln('| Command | Description |');
  buf.writeln('|---------|-------------|');
  for (final tool in toolsResult.tools) {
    buf.write('| `${tool.name}` | ${tool.description} |');
    buf.writeln();
  }
  buf.writeln('<!-- prettier-ignore-end -->');

  // Splice the table into README.md between the two markers.
  final readme = File('README.md');
  final original = readme.readAsStringSync();

  final start = original.indexOf(_marker);
  final end = original.indexOf(_marker, start + _marker.length);

  if (start == -1 || end == -1) {
    stderr.writeln('Could not find $_marker markers in README.md');
    exitCode = 1;
    return;
  }

  final updated =
      '${original.substring(0, start + _marker.length)}\n'
      '${buf.toString()}'
      '${original.substring(end)}';

  readme.writeAsStringSync(updated);
  print('README.md updated.');
}

base class _ScriptClient extends MCPClient {
  _ScriptClient() : super(Implementation(name: 'readme-gen', version: '0.1.0'));
}
