import 'dart:io' as io;

import 'package:dart_mcp/stdio.dart';
import 'package:flutter_agent_tools/src/shorthand/packages_mcp.dart';

void main() {
  PackagesMCPServer(stdioChannel(input: io.stdin, output: io.stdout));
}
