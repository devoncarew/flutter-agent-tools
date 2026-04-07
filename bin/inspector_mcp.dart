import 'dart:io' as io;

import 'package:dart_mcp/stdio.dart';
import 'package:flutter_agent_tools/inspector_mcp.dart';

void main() {
  InspectorServer(stdioChannel(input: io.stdin, output: io.stdout));
}
