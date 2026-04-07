import 'dart:io' as io;

import 'package:dart_mcp/stdio.dart';
import 'package:flutter_agent_tools/shorthand_mcp.dart';

void main() {
  ShorthandServer(stdioChannel(input: io.stdin, output: io.stdout));
}
