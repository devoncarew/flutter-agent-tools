import 'package:flutter_slipstream/src/deps/claude.dart';
import 'package:test/test.dart';

import 'support.dart';

void main() {
  group('handlePubAddClaude', () {
    test('warns on discontinued package', () async {
      final input = {
        'tool_name': 'Bash',
        'tool_input': {'command': 'flutter pub add flutter_markdown'},
      };

      final actual = await handlePubAddClaude(
        input,
        httpClient: discontinuedClient(
          'flutter_markdown',
          'flutter_markdown_plus',
        ),
      );
      expect(actual, isNotEmpty);

      final line = actual.first;
      expect(line, contains('flutter_markdown'));
      expect(line, contains('discontinued'));
    });

    test('warns on old major version', () async {
      final input = {
        'tool_name': 'Bash',
        'tool_input': {'command': "flutter pub add 'http:^0.13.0'"},
      };

      final actual = await handlePubAddClaude(
        input,
        httpClient: latestVersionClient('http', '1.3.0'),
      );
      expect(actual, isNotEmpty);
      expect(actual.first, contains('http'));
      expect(actual.first, contains('major version'));
    });

    test('returns empty for non-pub-add Bash commands', () async {
      final input = {
        'tool_name': 'Bash',
        'tool_input': {'command': 'flutter run'},
      };

      final actual = await handlePubAddClaude(
        input,
        httpClient: noNetworkClient(),
      );
      expect(actual, isEmpty);
    });

    test('returns empty for non-Bash tools', () async {
      final input = {
        'tool_name': 'Edit',
        'tool_input': {'command': 'flutter pub add http'},
      };

      final actual = await handlePubAddClaude(
        input,
        httpClient: noNetworkClient(),
      );
      expect(actual, isEmpty);
    });
  });

  group('handlePubspecGuardClaude', () {
    test('warns on discontinued package added via Edit', () async {
      final input = {
        'tool_name': 'Edit',
        'tool_input': {
          'file_path': 'pubspec.yaml',
          'old_string': '\ndependencies:',
          'new_string': '\ndependencies:\n  flutter_markdown: any',
        },
      };

      final actual = await handlePubspecGuardClaude(
        input,
        httpClient: discontinuedClient(
          'flutter_markdown',
          'flutter_markdown_plus',
        ),
      );
      expect(actual, isNotEmpty);

      final line = actual.first;
      expect(line, contains('flutter_markdown'));
      expect(line, contains('discontinued'));
    });

    test('warns on discontinued package added via Write', () async {
      const newContent = '''
name: my_app
dependencies:
  flutter_markdown: any
''';
      final input = {
        'tool_name': 'Write',
        'tool_input': {'file_path': 'pubspec.yaml', 'content': newContent},
      };

      final actual = await handlePubspecGuardClaude(
        input,
        httpClient: discontinuedClient('flutter_markdown', null),
      );
      expect(actual, isNotEmpty);
      expect(actual.first, contains('flutter_markdown'));
      expect(actual.first, contains('discontinued'));
    });

    test('returns empty when no new packages are added', () async {
      final input = {
        'tool_name': 'Edit',
        'tool_input': {
          'file_path': 'pubspec.yaml',
          'old_string': 'http: ^1.0.0',
          'new_string': 'http: ^1.1.0',
        },
      };

      // Version constraint change on existing package — no network needed.
      final actual = await handlePubspecGuardClaude(
        input,
        httpClient: noNetworkClient(),
      );
      expect(actual, isEmpty);
    });

    test('returns empty for non-pubspec files', () async {
      final input = {
        'tool_name': 'Edit',
        'tool_input': {
          'file_path': 'lib/main.dart',
          'old_string': 'foo',
          'new_string': 'bar',
        },
      };

      final actual = await handlePubspecGuardClaude(
        input,
        httpClient: noNetworkClient(),
      );
      expect(actual, isEmpty);
    });
  });
}
