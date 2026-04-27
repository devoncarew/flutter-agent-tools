import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:test/test.dart';

import 'support.dart';

void main() {
  group('inspector_mcp.dart', () {
    test('starts and lists expected tools', () async {
      final process = await Process.start(Platform.resolvedExecutable, [
        'run',
        path.join('bin', 'inspector_mcp.dart'),
      ]);
      addTearDown(process.kill);

      final tools = await listMcpTools(
        process,
      ).timeout(const Duration(seconds: 30));

      expect(
        tools,
        containsAll([
          'run_app',
          'reload',
          'get_output',
          'take_screenshot',
          'inspect_layout',
          'evaluate',
          'get_route',
          'navigate',
          'perform_tap',
          'perform_set_text',
          'perform_scroll',
          'get_semantics',
          'close_app',
        ]),
      );
    });
  });
}
