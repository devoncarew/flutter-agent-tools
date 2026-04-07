// Generates the MCP commands tables in README.md.
//
// Run with: dart run tool/generate_readme.dart

import 'dart:async';
import 'dart:io';

import 'package:dart_mcp/client.dart';
import 'package:flutter_agent_tools/inspector_mcp.dart';
import 'package:flutter_agent_tools/shorthand_mcp.dart';
import 'package:stream_channel/stream_channel.dart';

void main() async {
  await _updateSection(
    marker: '<!-- dart-api -->',
    tools: await _listTools(ShorthandServer.new),
  );
  await _updateSection(
    marker: '<!-- flutter-inspect -->',
    tools: await _listTools(InspectorServer.new),
  );
  print('README.md updated.');
}

/// Starts [serverFactory] in-process, lists its tools, and returns them.
Future<List<Tool>> _listTools(
  Function(StreamChannel<String>) serverFactory,
) async {
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

  final server = serverFactory(serverChannel);
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

  return toolsResult.tools;
}

/// Replaces the content between the two [marker] tags in README.md.
Future<void> _updateSection({
  required String marker,
  required List<Tool> tools,
}) async {
  final buf = StringBuffer();
  buf.writeln('<!-- prettier-ignore-start -->');
  buf.writeln('| Command | Description |');
  buf.writeln('|---------|-------------|');
  for (final tool in tools) {
    final desc = tool.description ?? '';
    final period = desc.indexOf('.');
    final summary = period >= 0 ? desc.substring(0, period + 1) : desc;
    buf.writeln('| `${tool.name}` | $summary |');
  }
  buf.writeln('<!-- prettier-ignore-end -->');

  final readme = File('README.md');
  final original = readme.readAsStringSync();

  final start = original.indexOf(marker);
  final end = original.indexOf(marker, start + marker.length);

  if (start == -1 || end == -1) {
    stderr.writeln('Could not find $marker markers in README.md');
    exitCode = 1;
    return;
  }

  final updated =
      '${original.substring(0, start + marker.length)}\n'
      '${buf.toString()}'
      '${original.substring(end)}';

  readme.writeAsStringSync(updated);
}

base class _ScriptClient extends MCPClient {
  _ScriptClient() : super(Implementation(name: 'readme-gen', version: '0.1.0'));
}
