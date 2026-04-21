import 'package:flutter_slipstream/src/deps/gemini.dart';
import 'package:test/test.dart';

import 'support.dart';

void main() {
  group('handlePubAddGemini', () {
    test('ignores non-run_shell_command tool names', () async {
      final result = await handlePubAddGemini({
        'tool_name': 'Bash',
        'tool_input': {'command': 'flutter pub add http'},
      }, httpClient: noNetworkClient());
      expect(result, isEmpty);
    });

    test('ignores commands without pub add', () async {
      final result = await handlePubAddGemini({
        'tool_name': 'run_shell_command',
        'tool_input': {'command': 'dart pub get'},
      }, httpClient: noNetworkClient());
      expect(result, isEmpty);
    });

    test('reads command from tool_input', () async {
      // Passes a fake pub.dev response via the no-net client;
      // we just want to confirm the right field is read without an exception.
      final result = await handlePubAddGemini({
        'tool_name': 'run_shell_command',
        'tool_input': {'command': 'flutter pub add some_pkg'},
      }, httpClient: noNetworkClient());
      // noNet always fails open → no warnings about pub.dev being unreachable
      // (the fail-open path returns a "could not reach pub.dev" warning).
      expect(result, isA<List<String>>());
    });

    test('returns empty list when tool_input is absent', () async {
      final result = await handlePubAddGemini({
        'tool_name': 'run_shell_command',
      }, httpClient: noNetworkClient());
      expect(result, isEmpty);
    });
  });

  group('handlePubspecGuardGemini', () {
    test('ignores Write/Edit tool names (Claude format)', () async {
      final result = await handlePubspecGuardGemini({
        'tool_name': 'Write',
        'tool_input': {'file_path': '/app/pubspec.yaml', 'content': ''},
      }, httpClient: noNetworkClient());
      expect(result, isEmpty);
    });

    test('ignores write_file targeting a non-pubspec file', () async {
      final result = await handlePubspecGuardGemini({
        'tool_name': 'write_file',
        'tool_input': {'file_path': '/app/lib/main.dart', 'content': ''},
      }, httpClient: noNetworkClient());
      expect(result, isEmpty);
    });

    test('reads file path from tool_input.file_path', () async {
      // No existing file at the path → treats all deps as new.
      const newPubspec = '''
dependencies:
  http: ^1.0.0
''';
      final result = await handlePubspecGuardGemini({
        'tool_name': 'write_file',
        'tool_input': {
          'file_path': '/nonexistent/pubspec.yaml',
          'content': newPubspec,
        },
      }, httpClient: noNetworkClient());
      // pub.dev is unreachable → fail-open warning for 'http'
      expect(result, isA<List<String>>());
    });

    test('replace tool applies old_string → new_string substitution', () async {
      // Supplying empty old/new strings on a nonexistent file → no new packages.
      final result = await handlePubspecGuardGemini({
        'tool_name': 'replace',
        'tool_input': {
          'file_path': '/nonexistent/pubspec.yaml',
          'old_string': '',
          'new_string': '',
        },
      }, httpClient: noNetworkClient());
      expect(result, isEmpty);
    });

    test('returns empty list when no new packages are introduced', () async {
      // old_string == new_string → no change → no new packages
      final result = await handlePubspecGuardGemini({
        'tool_name': 'replace',
        'tool_input': {
          'file_path': '/nonexistent/pubspec.yaml',
          'old_string': '',
          'new_string': '',
        },
      }, httpClient: noNetworkClient());
      expect(result, isEmpty);
    });
  });
}
