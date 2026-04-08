import 'dart:io' as io;

import 'package:dart_mcp/stdio.dart';
import 'package:flutter_agent_tools/src/inspector/inspector_mcp.dart';

void main() {
  InspectorMCPServer(stdioChannel(input: io.stdin, output: io.stdout));
}
