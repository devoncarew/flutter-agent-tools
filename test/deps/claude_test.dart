import 'package:flutter_slipstream/src/deps/claude.dart';
import 'package:test/test.dart';

void main() {
  group('handlePubAddClaude', () {
    test('warns on discontinued package', () async {
      final input = {
        'tool_name': 'Bash',
        'tool_input': {'command': 'flutter pub add flutter_markdown'},
      };

      // TODO: We should use a mock httpClient here.
      final actual = await handlePubAddClaude(input);
      expect(actual, isNotEmpty);

      final line = actual.first;
      expect(line, contains('flutter_markdown'));
      expect(line, contains('discontinued'));
    });
  });

  group('handlePubspecGuardClaude', () {
    test('warns on discontinued package', () async {
      final input = {
        'tool_name': 'Edit',
        'tool_input': {
          'file_path': 'pubspec.yaml',
          'old_string': '\ndependencies:',
          'new_string': '\ndependencies:\n  flutter_markdown: any',
        },
      };

      // TODO: We should use a mock httpClient here.
      final actual = await handlePubspecGuardClaude(input);
      expect(actual, isNotEmpty);

      final line = actual.first;
      expect(line, contains('flutter_markdown'));
      expect(line, contains('discontinued'));
    });
  });
}
