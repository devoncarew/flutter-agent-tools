// Generates the MCP commands tables in README.md.
//
// Run with: dart run tool/generate_docs.dart

import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:dart_mcp/client.dart';
import 'package:flutter_slipstream/src/inspector/inspector_mcp.dart';
import 'package:flutter_slipstream/src/shorthand/packages_mcp.dart';
import 'package:stream_channel/stream_channel.dart';

void main() async {
  final docFile = File(path.join('docs', 'slipstream_tools.md'));
  final buf = StringBuffer();
  buf.writeln('# Slipstream');
  buf.writeln();
  buf.writeln('MCP servers, instructions, and tools,');
  buf.writeln();

  // packages server
  var (initializeResult, tools) = await _listTools(PackagesMCPServer.new);
  var serverInfo = initializeResult.serverInfo;
  await _updateSection(marker: '<!-- ${serverInfo.name} -->', tools: tools);
  writeServerDocs(buf, initializeResult, tools);

  // inspector server
  (initializeResult, tools) = await _listTools(InspectorMCPServer.new);
  serverInfo = initializeResult.serverInfo;
  await _updateSection(marker: '<!-- ${serverInfo.name} -->', tools: tools);
  writeServerDocs(buf, initializeResult, tools);

  docFile.writeAsStringSync(buf.toString());

  print('README.md, ${docFile.path} updated.');
}

void writeServerDocs(
  StringBuffer buf,
  InitializeResult initializeResult,
  List<Tool> tools,
) {
  final server = initializeResult.serverInfo;
  buf.writeln('## server `${server.name}`');
  buf.writeln();
  buf.writeln(initializeResult.instructions);

  for (final tool in tools) {
    buf.writeln();
    buf.writeln('### tool `${tool.name}`');
    buf.writeln();
    buf.writeln(tool.description);

    // inputSchema
    buf.writeln();
    final inputSchema = tool.inputSchema;
    for (final param in inputSchema.properties!.keys) {
      final schema = inputSchema.properties![param]!;
      final required = inputSchema.required!.contains(param);
      final requiredDesc = required ? ' (required) ' : '';
      buf.writeln('- `$param`: $requiredDesc${schema.description}');
    }
  }
}

/// Starts [serverFactory] in-process, lists its tools, and returns them.
Future<(InitializeResult, List<Tool>)> _listTools(
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

  final initializeResult = await connection.initialize(
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

  return (initializeResult, toolsResult.tools);
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
