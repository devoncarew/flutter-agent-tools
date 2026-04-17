import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:test/test.dart';

import 'support.dart';

void main() {
  final scriptsDir = path.join(Directory.current.path, 'scripts');

  group('packages_mcp.sh', () {
    test('starts and lists expected tools', () async {
      final process = await Process.start('bash', [
        path.join(scriptsDir, 'packages_mcp.sh'),
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
