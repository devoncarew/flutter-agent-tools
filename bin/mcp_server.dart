import 'dart:io' as io;

import 'package:dart_mcp/stdio.dart';
import 'package:flutter_agent_tools/mcp_server.dart';

void main() {
  FlutterAgentServer(stdioChannel(input: io.stdin, output: io.stdout));
}
