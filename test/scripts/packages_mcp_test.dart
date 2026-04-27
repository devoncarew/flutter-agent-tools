import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:test/test.dart';

import 'support.dart';

void main() {
  group('packages_mcp.dart', () {
    test('starts and lists expected tools', () async {
      final process = await Process.start(Platform.resolvedExecutable, [
        'run',
        path.join('bin', 'packages_mcp.dart'),
      ]);
      addTearDown(process.kill);

      final tools = await listMcpTools(
        process,
      ).timeout(const Duration(seconds: 30));

      expect(
        tools,
        containsAll(['package_summary', 'library_stub', 'class_stub']),
      );
    });
  });
}
