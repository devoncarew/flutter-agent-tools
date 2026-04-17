import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Sends the MCP initialize handshake to [process], then calls tools/list and
/// returns the tool names. Kills the process when done.
Future<List<String>> listMcpTools(Process process) async {
  final iter = StreamIterator(
    process.stdout.transform(utf8.decoder).transform(const LineSplitter()),
  );

  // Reads the next non-empty, non-notification line (i.e. a response).
  Future<Map<String, dynamic>> nextResponse(int id) async {
    while (await iter.moveNext()) {
      final line = iter.current.trim();
      if (line.isEmpty) continue;
      final msg = jsonDecode(line) as Map<String, dynamic>;
      // Skip server-initiated notifications (no 'id' field).
      if (msg.containsKey('id') && msg['id'] == id) return msg;
    }
    throw StateError('Stream ended before response id=$id');
  }

  void send(Map<String, dynamic> msg) => process.stdin.writeln(jsonEncode(msg));

  // initialize
  send({
    'jsonrpc': '2.0',
    'id': 1,
    'method': 'initialize',
    'params': {
      'protocolVersion': '2024-11-05',
      'capabilities': {},
      'clientInfo': {'name': 'smoke-test', 'version': '0.0.1'},
    },
  });
  await nextResponse(1);

  // notifications/initialized
  send({'jsonrpc': '2.0', 'method': 'notifications/initialized', 'params': {}});

  // tools/list
  send({'jsonrpc': '2.0', 'id': 2, 'method': 'tools/list', 'params': {}});
  final toolsResponse = await nextResponse(2);

  process.kill();
  await iter.cancel();

  final tools = (toolsResponse['result']?['tools'] as List? ?? []).cast<Map>();
  return tools.map((t) => t['name'] as String).toList();
}
